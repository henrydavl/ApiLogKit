//
//  ApiLogListViewModel.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import Combine
import Foundation

/// Identifiable wrapper so `ApiLog` can be used in `ForEach`.
struct ApiLogItem: Identifiable {
    /// Mirrors the log's own identity — see `ApiLog.id`. Generating a fresh id
    /// here would give every row a new identity on each reload.
    var id: UUID { log.id }
    let log: ApiLog
}

final class ApiLogListViewModel: ObservableObject {
    @Published var items: [ApiLogItem] = []
    @Published var searchText: String = ""
    @Published private(set) var logType: LogEventType = .api

    /// When paused, incoming logs are still collected but the list stops
    /// refreshing, so reading a log isn't disturbed by live traffic.
    @Published private(set) var isPaused: Bool = false

    /// Number of logs in the current bucket that arrived since the list was
    /// last refreshed. Only meaningful while paused.
    @Published private(set) var pendingCount: Int = 0

    /// Status / method / host facets applied on top of the search query.
    @Published private(set) var filter = ApiLogFilter()

    /// Live mirrors of the logger's data, kept up to date via Combine so logs
    /// added while this screen is on-screen (e.g. from Developer Options) show
    /// up without closing and reopening the inspector.
    private var apiLogs: [ApiLog] = []
    private var eventTrackerLogs: [ApiLog] = []
    private var thirdPartyLogs: [ApiLog] = []
    private var cancellables = Set<AnyCancellable>()

    /// Size of the source bucket at the time `items` was last built, used to
    /// derive `pendingCount` while paused.
    private var renderedSourceCount: Int = 0

    var isEventTrackerLogEnabled: Bool { ApiLogger.shared.isEventTrackerLogEnabled }
    var isThirdPartyTrackerEnabled: Bool { ApiLogger.shared.isThirdPartyTrackerEnabled }
    var isDevOptionsEnabled: Bool { ApiLogKitConfig.developerOptionsProvider != nil }

    var title: String {
        switch logType {
        case .api:          return "API Logs"
        case .eventTracker: return "EventTracker"
        case .thirdParty:   return "3rd Party"
        }
    }

    /// `logs` is retained for source compatibility; the data source is now the
    /// live `ApiLogger.shared` publishers, which replay their current value on
    /// subscription, so the initial snapshot is no longer needed.
    init(logs: [ApiLog] = []) {
        ApiLogger.shared.logsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.apiLogs = logs
                self?.reloadIfLive()
            }
            .store(in: &cancellables)

        ApiLogger.shared.eventTrackerLogsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.eventTrackerLogs = logs
                self?.reloadIfLive()
            }
            .store(in: &cancellables)

        ApiLogger.shared.thirdPartyLogsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.thirdPartyLogs = logs
                self?.reloadIfLive()
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

    private var currentSource: [ApiLog] {
        switch logType {
        case .api:          return apiLogs
        case .eventTracker: return eventTrackerLogs
        case .thirdParty:   return thirdPartyLogs
        }
    }

    /// Applies a live logger update, unless the user paused the stream — in
    /// which case only the pending badge moves.
    private func reloadIfLive() {
        guard !isPaused else {
            pendingCount = max(0, currentSource.count - renderedSourceCount)
            return
        }
        reload()
    }

    func reload() {
        let source = currentSource

        let query = searchText.maxCharacter(50).trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered = source
        if logType.isHTTP, query.count >= 3 {
            filtered = source.filter { $0.url.localizedCaseInsensitiveContains(query) }
        }
        if filter.isActive {
            filtered = filtered.filter { filter.matches($0) }
        }

        // Newest first, matching the legacy `logs.reverse()`.
        items = filtered.reversed().map { ApiLogItem(log: $0) }
        renderedSourceCount = source.count
        pendingCount = 0
    }

    // MARK: - Actions

    /// Toggles the live stream. Resuming immediately folds in whatever arrived
    /// while paused.
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            pendingCount = max(0, currentSource.count - renderedSourceCount)
        } else {
            reload()
        }
    }

    func switchTo(_ type: LogEventType) {
        // Guard against switching to a bucket that isn't enabled.
        if type == .eventTracker, !isEventTrackerLogEnabled {
            switchTo(.api)
            return
        }
        if type == .thirdParty, !isThirdPartyTrackerEnabled {
            switchTo(.api)
            return
        }
        guard type != logType else { return }
        logType = type
        // Facets are derived from the bucket's own contents — a host carried over
        // from another tab would filter everything out with no obvious cause.
        filter = ApiLogFilter()
        reload()
    }

    // MARK: - Filtering

    /// EventTracker entries are synthesised and carry no status code or host, so
    /// those facets are hidden for that bucket.
    var showsStatusFilter: Bool { logType.isHTTP }

    /// Methods present in the current bucket, so the menu only offers values
    /// that can actually match.
    var availableMethods: [String] {
        Set(currentSource.map { $0.method.uppercased() }).sorted()
    }

    /// Hosts present in the current bucket.
    var availableHosts: [String] {
        Set(currentSource.compactMap { $0.host }).sorted()
    }

    func toggleStatus(_ status: StatusClass) {
        filter.toggle(status, in: \.statuses)
        reload()
    }

    func toggleMethod(_ method: String) {
        filter.toggle(method.uppercased(), in: \.methods)
        reload()
    }

    func toggleHost(_ host: String) {
        filter.toggle(host.lowercased(), in: \.hosts)
        reload()
    }

    func clearFilters() {
        guard filter.isActive else { return }
        filter = ApiLogFilter()
        reload()
    }

    func clear() {
        ApiLogger.shared.clearLogs()
        items = []
        renderedSourceCount = 0
        pendingCount = 0
    }

    // MARK: - Export

    /// Raw textual dump of every visible log (same format as the legacy export).
    func exportText() -> String {
        items.map { ApiLogExporter.rawLog(for: $0.log) }.joined()
    }
}
