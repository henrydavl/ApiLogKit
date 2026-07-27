//
//  ApiLogURLProtocol.swift
//  ApiLogKit
//
//  Captures URLSession traffic the host app has no call site for — closed-source
//  SDKs and the like — by sitting in the URL Loading System as a `URLProtocol`.
//
//  Flow: `canInit` decides whether we touch a request at all, `startLoading`
//  re-issues it on an ApiLogKit-owned session, and the delegate relays every
//  callback back to the original client while recording a copy.
//

import Foundation

final class ApiLogURLProtocol: URLProtocol {

    /// Marker set on the forwarded request so `canInit` doesn't intercept our own
    /// re-issued copy and recurse forever.
    fileprivate static let handledKey = "com.apilogkit.thirdPartyHandled"

    /// Requests declaring a payload larger than this are left alone. Capturing a
    /// streamed body means draining it into memory to re-attach it (see
    /// `apilogkit_drainBody`), which isn't worth doing for large uploads.
    private static let maxInterceptableUploadBytes = 10 * 1024 * 1024

    private let taskLock = NSLock()
    private var forwardingTask: URLSessionTask?

    private var startDate = Date()
    private var capturedRequestBody: Data?

    // Touched only from the session's (serial) delegate queue.
    private var response: HTTPURLResponse?
    private var capturedResponseBody = Data()
    private var measuredDuration: TimeInterval?

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        guard ApiLogger.shared.isEnabled,
              ApiLogger.shared.isThirdPartyTrackerEnabled,
              URLProtocol.property(forKey: handledKey, in: request) == nil,
              let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              !declaresOversizedBody(request),
              ApiLogKitConfig.thirdPartyTracker.allows(request)
        else { return false }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool { false }

    override func startLoading() {
        startDate = Date()

        var forwarded = request
        // Draining consumes `httpBodyStream`, so the payload has to be re-attached
        // as `httpBody` or the forwarded request goes out empty.
        if let body = request.apilogkit_drainBody() {
            forwarded.httpBodyStream = nil
            forwarded.httpBody = body
            let limit = max(0, ApiLogKitConfig.thirdPartyTracker.maxBodyBytes)
            capturedRequestBody = Data(body.prefix(limit))
        }

        guard let tagged = (forwarded as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: tagged)

        let task = Self.session.dataTask(with: tagged as URLRequest)
        taskLock.lock()
        self.forwardingTask = task
        taskLock.unlock()

        Self.registry.register(self, for: task)
        task.resume()
    }

    override func stopLoading() {
        taskLock.lock()
        let inFlight = forwardingTask
        forwardingTask = nil
        taskLock.unlock()

        guard let inFlight else { return }
        Self.registry.deregister(inFlight)
        inFlight.cancel()
    }

    // MARK: - Interception policy

    /// True when the request advertises a payload too large to buffer.
    private static func declaresOversizedBody(_ request: URLRequest) -> Bool {
        guard let value = request.value(forHTTPHeaderField: "Content-Length"),
              let length = Int(value)
        else { return false }
        return length > maxInterceptableUploadBytes
    }

    // MARK: - Forwarding session

    /// One shared session for every intercepted request — a session per request
    /// would give up connection reuse for the whole app. Our own protocol class is
    /// stripped from the configuration as a second line of defence against
    /// recursion, on top of `handledKey`.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = (configuration.protocolClasses ?? [])
            .filter { ObjectIdentifier($0) != ObjectIdentifier(ApiLogURLProtocol.self) }
        return URLSession(configuration: configuration, delegate: SessionDelegate(), delegateQueue: nil)
    }()

    /// Maps a task back to the protocol instance that started it, since all tasks
    /// share one session and therefore one delegate.
    fileprivate static let registry = TaskRegistry()

    // MARK: - Delegate callbacks

    fileprivate func didReceive(_ response: URLResponse) {
        self.response = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    fileprivate func didReceive(_ data: Data) {
        // The client always gets every byte; only our retained copy is truncated.
        let limit = max(0, ApiLogKitConfig.thirdPartyTracker.maxBodyBytes)
        let remaining = limit - capturedResponseBody.count
        if remaining > 0 {
            capturedResponseBody.append(data.prefix(remaining))
        }
        client?.urlProtocol(self, didLoad: data)
    }

    fileprivate func didFinishCollecting(_ metrics: URLSessionTaskMetrics) {
        measuredDuration = metrics.taskInterval.duration
    }

    fileprivate func didComplete(with error: Error?) {
        taskLock.lock()
        forwardingTask = nil
        taskLock.unlock()

        ApiLogger.shared.addThirdPartyLog(
            ApiLog(
                request: request,
                requestBody: capturedRequestBody,
                response: response,
                responseBody: capturedResponseBody,
                error: error,
                duration: measuredDuration ?? Date().timeIntervalSince(startDate),
                date: startDate
            )
        )

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

// MARK: - Task registry

final class TaskRegistry {
    private var storage: [Int: ApiLogURLProtocol] = [:]
    private let lock = NSLock()

    func register(_ handler: ApiLogURLProtocol, for task: URLSessionTask) {
        lock.lock()
        storage[task.taskIdentifier] = handler
        lock.unlock()
    }

    func deregister(_ task: URLSessionTask) {
        lock.lock()
        storage[task.taskIdentifier] = nil
        lock.unlock()
    }

    func handler(for task: URLSessionTask) -> ApiLogURLProtocol? {
        lock.lock()
        defer { lock.unlock() }
        return storage[task.taskIdentifier]
    }
}

// MARK: - Shared session delegate

private final class SessionDelegate: NSObject, URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        ApiLogURLProtocol.registry.handler(for: dataTask)?.didReceive(response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        ApiLogURLProtocol.registry.handler(for: dataTask)?.didReceive(data)
    }

    /// Follow redirects transparently, which is what `URLSession` does by default
    /// anyway — the caller sees the final response and we log the final URL.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request)
    }

    /// The intercepted request no longer runs on the SDK's own session, so its
    /// authentication delegate never fires. Default handling is the best we can
    /// do — this is why certificate-pinned SDKs need to go in `ignoredHosts`.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        ApiLogURLProtocol.registry.handler(for: task)?.didFinishCollecting(metrics)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let handler = ApiLogURLProtocol.registry.handler(for: task)
        ApiLogURLProtocol.registry.deregister(task)
        handler?.didComplete(with: error)
    }
}
