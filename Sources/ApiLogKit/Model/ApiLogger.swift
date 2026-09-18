//
//  ApiLogger.swift
//  ApiLogKit
//

import Combine
import Foundation

/// Handle to an in-flight entry, returned by `ApiLogger.beginLog(...)` and
/// handed back to `completeLog(_:with:)` once the response arrives.
public struct ApiLogToken {
    let id: UUID
    let bucket: LogEventType
}

public final class ApiLogger {
    public static let shared = ApiLogger()

    private init() {}

    // Backing storage is held inside Combine subjects so observers (e.g. the
    // log list) can react to new entries in real time. All mutation runs on
    // `queue` — `CurrentValueSubject` isn't safe under concurrent writes.
    private let logsSubject = CurrentValueSubject<[ApiLog], Never>([])
    private let eventTrackerSubject = CurrentValueSubject<[ApiLog], Never>([])
    private let thirdPartySubject = CurrentValueSubject<[ApiLog], Never>([])
    private var isEnableEventTrackerLog: Bool = false
    private var isEnableThirdPartyTracker: Bool = false
    private let queue = DispatchQueue(label: "apilogkit.logger.queue")
    private let flagLock = NSLock()

    /// Emits the full API log array whenever it changes. Replays the current
    /// value to new subscribers, so a freshly presented view fills immediately.
    public var logsPublisher: AnyPublisher<[ApiLog], Never> {
        logsSubject.eraseToAnyPublisher()
    }

    /// Emits the full EventTracker log array whenever it changes.
    public var eventTrackerLogsPublisher: AnyPublisher<[ApiLog], Never> {
        eventTrackerSubject.eraseToAnyPublisher()
    }

    /// Emits the full 3rd-party traffic log array whenever it changes.
    public var thirdPartyLogsPublisher: AnyPublisher<[ApiLog], Never> {
        thirdPartySubject.eraseToAnyPublisher()
    }

    /// Master switch — when false, `addLog`/`addAppsFlyerLog` are no-ops.
    /// Hosts typically gate this on their environment (e.g. dev builds only).
    public var isEnabled: Bool = true

    public var isEventTrackerLogEnabled: Bool {
        isEnableEventTrackerLog
    }

    public func enableEventTrackerLog(_ isEnabled: Bool) {
        isEnableEventTrackerLog = isEnabled
    }

    /// Whether 3rd-party traffic capture is currently active. Read from arbitrary
    /// networking threads on every request, hence the lock.
    public var isThirdPartyTrackerEnabled: Bool {
        flagLock.lock()
        defer { flagLock.unlock() }
        return isEnableThirdPartyTracker
    }

    /// Turns on automatic capture of `URLSession` traffic from code you don't
    /// control — closed-source SDKs and the like — into a separate "3rd Party"
    /// bucket. Manual `addLog` recording is unaffected.
    ///
    /// Call this **at app launch, before any SDK initialises**: only sessions
    /// created after installation are intercepted. Configure
    /// `ApiLogKitConfig.thirdPartyTracker` first, in particular `ignoredHosts`.
    ///
    /// Installation is one-way — passing `false` later stops capture, but the
    /// interceptor stays installed for the rest of the process lifetime.
    public func enableThirdPartyTracker(_ isEnabled: Bool) {
        flagLock.lock()
        isEnableThirdPartyTracker = isEnabled
        flagLock.unlock()

        if isEnabled {
            ThirdPartyTracker.shared.install()
        }
    }

    public func addLog(_ log: ApiLog) {
        append(log, to: .api)
    }

    public func addEventTrackerLog(_ log: ApiLog) {
        append(log, to: .eventTracker)
    }

    /// Appends an intercepted 3rd-party request, trimming oldest-first to
    /// `ApiLogKitConfig.thirdPartyTracker.maxEntries`. This bucket fills without
    /// the host app doing anything, so it must not grow unbounded.
    public func addThirdPartyLog(_ log: ApiLog) {
        append(log, to: .thirdParty)
    }

    // MARK: - In-flight entries

    /// Records a request that has been sent but hasn't come back yet, and
    /// returns a handle for completing it.
    ///
    /// The entry appears in the list immediately, greyed out and marked pending,
    /// so a request that is slow — or never answered at all — is visible while
    /// it is happening rather than only in hindsight. Pass the returned token to
    /// `completeLog(_:with:)` when the response arrives.
    ///
    ///     let token = ApiLogger.shared.beginLog(method: "POST", url: url,
    ///                                           requestHeader: headers,
    ///                                           requestBody: parameters)
    ///     // …once the response lands:
    ///     ApiLogger.shared.completeLog(token, with: ApiLog(response: response, …))
    ///
    /// A token whose entry is never completed simply stays pending — nothing
    /// leaks, and the row makes the stuck request obvious.
    @discardableResult
    public func beginLog(
        method: String,
        url: String,
        requestHeader: [String: Any] = [:],
        requestBody: [String: Any] = [:],
        requestBodyText: String? = nil
    ) -> ApiLogToken {
        let log = ApiLog(
            method: method,
            url: url,
            requestHeader: requestHeader,
            requestBody: requestBody,
            requestBodyText: requestBodyText
        )
        return begin(log, in: .api)
    }

    /// Fills in the response side of a pending entry, in place.
    ///
    /// The entry keeps its identity and its original start time — so the row
    /// stays where it is in the list instead of jumping to the top — and takes
    /// every other field from `log`. A token whose entry has since been cleared
    /// or trimmed away is ignored.
    public func completeLog(_ token: ApiLogToken, with log: ApiLog) {
        mutate(id: token.id, in: token.bucket) { entry in
            let id = entry.id
            let date = entry.date
            entry = log
            entry.state = .finished
            // `id` and `date` are restored rather than overwritten: identity keeps
            // SwiftUI from tearing the row down, and the start time keeps ordering
            // stable while the request is in flight.
            entry.restoreIdentity(id: id, date: date)
        }
    }

    /// Inserts a pending entry into `bucket` and returns its handle.
    func begin(_ log: ApiLog, in bucket: LogEventType) -> ApiLogToken {
        append(log, to: bucket)
        return ApiLogToken(id: log.id, bucket: bucket)
    }

    // MARK: - Storage

    private func subject(for bucket: LogEventType) -> CurrentValueSubject<[ApiLog], Never> {
        switch bucket {
        case .api:          return logsSubject
        case .eventTracker: return eventTrackerSubject
        case .thirdParty:   return thirdPartySubject
        }
    }

    /// The change stream for one bucket, for observers that already know which
    /// one they care about — the detail screen watching its own entry complete.
    func publisher(for bucket: LogEventType) -> AnyPublisher<[ApiLog], Never> {
        subject(for: bucket).eraseToAnyPublisher()
    }

    private func append(_ log: ApiLog, to bucket: LogEventType) {
        guard isEnabled else { return }
        // Only the 3rd-party bucket is capped: it fills on its own, whereas the
        // other two only grow when the host app asks them to.
        let limit = bucket == .thirdParty
            ? max(1, ApiLogKitConfig.thirdPartyTracker.maxEntries)
            : nil

        queue.async {
            let subject = self.subject(for: bucket)
            subject.value.append(log)
            if let limit {
                let overflow = subject.value.count - limit
                if overflow > 0 {
                    subject.value.removeFirst(overflow)
                }
            }
        }
    }

    /// Applies an in-place edit to the entry with `id`, if it's still around.
    private func mutate(id: UUID, in bucket: LogEventType, _ body: @escaping (inout ApiLog) -> Void) {
        queue.async {
            let subject = self.subject(for: bucket)
            guard let index = subject.value.firstIndex(where: { $0.id == id }) else { return }
            body(&subject.value[index])
        }
    }

    public func getLogs() -> [ApiLog] {
        queue.sync { self.logsSubject.value }
    }

    public func getEventTrackerLogs() -> [ApiLog] {
        queue.sync { self.eventTrackerSubject.value }
    }

    public func getThirdPartyLogs() -> [ApiLog] {
        queue.sync { self.thirdPartySubject.value }
    }

    public func clearLogs() {
        queue.async {
            self.logsSubject.value = []
            self.eventTrackerSubject.value = []
            self.thirdPartySubject.value = []
        }
    }

    // MARK: - Persistence

    /// Keeps logs across app launches by writing them to Application Support.
    ///
    /// Opt-in, and worth a moment's thought before switching on: it puts captured
    /// request and response bodies — including any `Authorization` headers and
    /// tokens they contain — on disk, where they outlive the process. Gate it the
    /// same way you gate `isEnabled`, and see `ApiLogKitConfig.persistence` for
    /// the retention budget.
    ///
    /// Call at launch. Anything already on disk is loaded immediately, ahead of
    /// logs recorded in this session; writes are debounced and flushed when the
    /// app backgrounds. Entries still in flight at exit aren't persisted, since a
    /// restored pending entry could never complete.
    public func enablePersistence(_ isEnabled: Bool) {
        if isEnabled {
            LogPersistence.shared.enable()
        } else {
            LogPersistence.shared.disable()
        }
    }

    /// Deletes the on-disk archive, leaving the in-memory buckets alone.
    public func clearPersistedLogs() {
        LogPersistence.shared.deleteArchive()
    }

    /// Seeds the buckets with entries loaded from disk.
    ///
    /// Restored logs are older than anything recorded in this session, so they go
    /// in front — the list sorts by insertion order.
    func restore(api: [ApiLog], eventTracker: [ApiLog], thirdParty: [ApiLog]) {
        queue.async {
            self.logsSubject.value = api + self.logsSubject.value
            self.eventTrackerSubject.value = eventTracker + self.eventTrackerSubject.value
            self.thirdPartySubject.value = thirdParty + self.thirdPartySubject.value
        }
    }

    /// Installs a shake gesture that automatically presents the log inspector
    /// from any screen — no `motionEnded` override needed in the host app.
    /// Call this once during app startup (e.g. AppDelegate / SceneDelegate).
    public func enableShakeToOpen() {
        ShakeDetector.shared.install()
    }
}
