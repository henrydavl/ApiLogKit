//
//  ApiLogger.swift
//  ApiLogKit
//

import Foundation

public final class ApiLogger {
    public static let shared = ApiLogger()

    private init() {}

    private var logs: [ApiLog] = []
    private var appsFlyerLog: [ApiLog] = []
    private var isEnableAppsFlyerLog: Bool = false
    private let queue = DispatchQueue(label: "apilogkit.logger.queue")

    /// Master switch — when false, `addLog`/`addAppsFlyerLog` are no-ops.
    /// Hosts typically gate this on their environment (e.g. dev builds only).
    public var isEnabled: Bool = true

    public var isAppsFlyerLogEnabled: Bool {
        isEnableAppsFlyerLog
    }

    public func enableAppsFlyerLog(_ isEnabled: Bool) {
        isEnableAppsFlyerLog = isEnabled
    }

    public func addLog(_ log: ApiLog) {
        guard isEnabled else { return }
        queue.async { self.logs.append(log) }
    }

    public func addAppsFlyerLog(_ log: ApiLog) {
        guard isEnabled else { return }
        queue.async { self.appsFlyerLog.append(log) }
    }

    public func getLogs() -> [ApiLog] {
        queue.sync { self.logs }
    }

    public func getAppsFlyerLogs() -> [ApiLog] {
        queue.sync { self.appsFlyerLog }
    }

    public func clearLogs() {
        queue.async {
            self.logs.removeAll()
            self.appsFlyerLog.removeAll()
        }
    }
}
