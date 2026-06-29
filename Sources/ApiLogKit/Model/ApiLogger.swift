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
    private var isEnableEventTrackerLog: Bool = false
    private let queue = DispatchQueue(label: "apilogkit.logger.queue")

    /// Emits the full API log array whenever it changes. Replays the current
    /// value to new subscribers, so a freshly presented view fills immediately.
    public var logsPublisher: AnyPublisher<[ApiLog], Never> {
        logsSubject.eraseToAnyPublisher()
    }

    /// Emits the full EventTracker log array whenever it changes.
    public var eventTrackerLogsPublisher: AnyPublisher<[ApiLog], Never> {
        eventTrackerSubject.eraseToAnyPublisher()
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

    public func addLog(_ log: ApiLog) {
        guard isEnabled else { return }
        queue.async { self.logsSubject.value.append(log) }
    }

    public func addEventTrackerLog(_ log: ApiLog) {
        guard isEnabled else { return }
        queue.async { self.eventTrackerSubject.value.append(log) }
    }

    public func getLogs() -> [ApiLog] {
        queue.sync { self.logsSubject.value }
    }

    public func getEventTrackerLogs() -> [ApiLog] {
        queue.sync { self.eventTrackerSubject.value }
    }

    public func clearLogs() {
        queue.async {
            self.logsSubject.value = []
            self.eventTrackerSubject.value = []
        }
    }

    /// Installs a shake gesture that automatically presents the log inspector
    /// from any screen — no `motionEnded` override needed in the host app.
    /// Call this once during app startup (e.g. AppDelegate / SceneDelegate).
    public func enableShakeToOpen() {
        ShakeDetector.shared.install()
    }
}
