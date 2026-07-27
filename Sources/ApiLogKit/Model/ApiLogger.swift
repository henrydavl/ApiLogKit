//
//  ApiLogger.swift
//  ApiLogKit
//

import Combine
import Foundation

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
        guard isEnabled else { return }
        queue.async { self.logsSubject.value.append(log) }
    }

    public func addEventTrackerLog(_ log: ApiLog) {
        guard isEnabled else { return }
        queue.async { self.eventTrackerSubject.value.append(log) }
    }

    /// Appends an intercepted 3rd-party request, trimming oldest-first to
    /// `ApiLogKitConfig.thirdPartyTracker.maxEntries`. This bucket fills without
    /// the host app doing anything, so it must not grow unbounded.
    public func addThirdPartyLog(_ log: ApiLog) {
        guard isEnabled else { return }
        let limit = max(1, ApiLogKitConfig.thirdPartyTracker.maxEntries)
        queue.async {
            self.thirdPartySubject.value.append(log)
            let overflow = self.thirdPartySubject.value.count - limit
            if overflow > 0 {
                self.thirdPartySubject.value.removeFirst(overflow)
            }
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

    /// Installs a shake gesture that automatically presents the log inspector
    /// from any screen — no `motionEnded` override needed in the host app.
    /// Call this once during app startup (e.g. AppDelegate / SceneDelegate).
    public func enableShakeToOpen() {
        ShakeDetector.shared.install()
    }
}
