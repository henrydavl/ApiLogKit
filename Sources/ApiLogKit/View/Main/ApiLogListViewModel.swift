//
//  ApiLogListViewModel.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import Combine
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

    /// Live mirrors of the logger's data, kept up to date via Combine so logs
    /// added while this screen is on-screen (e.g. from Developer Options) show
    /// up without closing and reopening the inspector.
    private var apiLogs: [ApiLog] = []
    private var eventTrackerLogs: [ApiLog] = []
    private var cancellables = Set<AnyCancellable>()

    var isEventTrackerLogEnabled: Bool { ApiLogger.shared.isEventTrackerLogEnabled }
    var isDevOptionsEnabled: Bool { ApiLogKitConfig.developerOptionsProvider != nil }

    /// `logs` is retained for source compatibility; the data source is now the
    /// live `ApiLogger.shared` publishers, which replay their current value on
    /// subscription, so the initial snapshot is no longer needed.
    init(logs: [ApiLog] = []) {
        ApiLogger.shared.logsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.apiLogs = logs
                self?.reload()
            }
            .store(in: &cancellables)

        ApiLogger.shared.eventTrackerLogsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.eventTrackerLogs = logs
                self?.reload()
            }
            .store(in: &cancellables)

        // Debounced search — replaces the view's `.onChange(of:)` reload.
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    // MARK: - Data

    func reload() {
        let source: [ApiLog]
        switch logType {
        case .api:
            source = apiLogs
        case .eventTracker:
            source = eventTrackerLogs
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
        // Guard against switching to EventTracker when it isn't enabled.
        if type == .eventTracker, !isEventTrackerLogEnabled {
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
