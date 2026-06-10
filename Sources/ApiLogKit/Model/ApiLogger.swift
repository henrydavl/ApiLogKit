//
//  ApiLogger.swift
//  ApiLogKit
//

import Foundation

public final class ApiLogger {
    public static let shared = ApiLogger()

    private init() {}

    private var logs: [ApiLog] = []
    private var eventTrackerLog: [ApiLog] = []
    private var isEnableEventTrackerLog: Bool = false
    private let queue = DispatchQueue(label: "apilogkit.logger.queue")

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
        queue.async { self.logs.append(log) }
    }

    public func addEventTrackerLog(_ log: ApiLog) {
        guard isEnabled else { return }
        queue.async { self.eventTrackerLog.append(log) }
    }

    public func getLogs() -> [ApiLog] {
        queue.sync { self.logs }
    }

    public func getEventTrackerLogs() -> [ApiLog] {
        queue.sync { self.eventTrackerLog }
    }

    public func clearLogs() {
        queue.async {
            self.logs.removeAll()
            self.eventTrackerLog.removeAll()
        }
    }

    /// Installs a shake gesture that automatically presents the log inspector
    /// from any screen — no `motionEnded` override needed in the host app.
    /// Call this once during app startup (e.g. AppDelegate / SceneDelegate).
    public func enableShakeToOpen() {
        ShakeDetector.shared.install()
    }
}
