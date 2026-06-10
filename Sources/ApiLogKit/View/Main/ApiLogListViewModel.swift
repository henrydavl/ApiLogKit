//
//  ApiLogListViewModel.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import Foundation

/// Identifiable wrapper so `ApiLog` (a plain struct) can be used in `ForEach`.
struct ApiLogItem: Identifiable {
    let id = UUID()
    let log: ApiLog
}

final class ApiLogListViewModel: ObservableObject {
    @Published var items: [ApiLogItem] = []
    @Published var searchText: String = ""
    @Published private(set) var logType: LogEventType = .api

    /// Logs passed in at presentation time, used as the `.api` data source
    /// (mirrors the legacy controller, which is created with `getLogs()`).
    private let apiLogs: [ApiLog]

    var isAppsFlyerEnabled: Bool { ApiLogger.shared.isAppsFlyerLogEnabled }
    var isDevOptionsEnabled: Bool { ApiLogKitConfig.developerOptionsProvider != nil }

    init(logs: [ApiLog]) {
        self.apiLogs = logs
        reload()
    }

    // MARK: - Data

    func reload() {
        let source: [ApiLog]
        switch logType {
        case .api:
            source = apiLogs
        case .eventTracker:
            source = ApiLogger.shared.getAppsFlyerLogs()
        }

        let query = searchText.maxCharacter(50).trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered = source
        if logType == .api, query.count >= 3 {
            filtered = source.filter { $0.url.localizedCaseInsensitiveContains(query) }
        }

        // Newest first, matching the legacy `logs.reverse()`.
        items = filtered.reversed().map { ApiLogItem(log: $0) }
    }

    // MARK: - Actions

    func switchTo(_ type: LogEventType) {
        // Guard against switching to AppsFlyer when it isn't enabled.
        if type == .eventTracker, !isAppsFlyerEnabled {
            switchTo(.api)
            return
        }
        guard type != logType else { return }
        logType = type
        reload()
    }

    func clear() {
        ApiLogger.shared.clearLogs()
        items = []
    }

    // MARK: - Export

    /// Raw textual dump of every visible log (same format as the legacy export).
    func exportText() -> String {
        items.map { ApiLogExporter.rawLog(for: $0.log) }.joined()
    }
}
