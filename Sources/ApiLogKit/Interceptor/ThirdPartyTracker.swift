//
//  ThirdPartyTracker.swift
//  ApiLogKit
//
//  Installation entry point for 3rd-party traffic capture, plus the mapping from
//  raw URL Loading System types onto `ApiLog`.
//

import Foundation

final class ThirdPartyTracker {
    static let shared = ThirdPartyTracker()
    private init() {}

    private var installed = false

    /// Puts the interceptor in front of both the shared session and any session
    /// built from a configuration created after this call. Idempotent, and
    /// deliberately one-way — unregistering mid-flight would strand in-progress
    /// requests, so `ApiLogger.shared.enableThirdPartyTracker(false)` gates
    /// capture in `canInit` instead of tearing this down.
    func install() {
        guard !installed else { return }
        installed = true

        URLProtocol.registerClass(ApiLogURLProtocol.self)
        URLSessionConfiguration.apilogkit_installSwizzle()
    }
}

// MARK: - Mapping

extension ApiLog {

    /// Builds a log entry from an intercepted exchange.
    ///
    /// `error` is folded into `responseCode` so failed calls still get a badge in
    /// the list rather than silently reading as a `0`.
    init(
        request: URLRequest,
        requestBody: Data?,
        response: HTTPURLResponse?,
        responseBody: Data,
        error: Error?,
        duration: TimeInterval,
        date: Date
    ) {
        let bodyText = requestBody.map { $0.jsonize() }

        self.init(
            responseCode: Self.responseCode(response: response, error: error),
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "Unknown URL",
            responseTime: String(format: "%.3f", duration),
            size: "\(responseBody.count)",
            date: date,
            responseHeader: (response?.allHeaderFields as? [String: Any]) ?? [:],
            responseBody: Self.responseText(responseBody, error: error),
            requestHeader: request.allHTTPHeaderFields ?? [:],
            requestBody: [:],
            // Intercepted payloads are arbitrary bytes — form-encoded, protobuf,
            // multipart — so they go through the raw-text field rather than being
            // forced into the `[String: Any]` shape.
            requestBodyText: bodyText
        )
    }

    private static func responseCode(response: HTTPURLResponse?, error: Error?) -> String {
        if let response { return "\(response.statusCode)" }
        if let error = error as? URLError { return "\(error.errorCode)" }
        return error == nil ? "0" : "-1"
    }

    private static func responseText(_ data: Data, error: Error?) -> String {
        if data.isEmpty, let error {
            return error.localizedDescription
        }
        return data.jsonize()
    }
}
