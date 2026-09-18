//
//  ApiLogFilter.swift
//  ApiLogKit
//
//  Filtering state for the log list. Each facet is a set: empty means "don't
//  filter on this", non-empty means "match any of these" — so facets combine
//  with AND between them and OR within them.
//

import Foundation

/// Status-code buckets offered by the status filter. Mirrors the badge colours
/// in `ApiLogRowView`.
enum StatusClass: CaseIterable, Hashable {
    case pending
    case success
    case redirect
    case clientError
    case serverError
    case failed

    /// Classifies an entry. In-flight entries have no meaningful code yet, so
    /// state is checked before the code.
    init(log: ApiLog) {
        if log.state == .pending {
            self = .pending
        } else {
            self.init(code: log.responseCode)
        }
    }

    /// Classifies a raw `ApiLog.responseCode`.
    ///
    /// Anything unparseable or outside the HTTP range lands in `.failed` — the
    /// interceptor stores `URLError` codes (negative) and `"-1"`/`"0"` sentinels
    /// there for calls that never reached the server.
    init(code: String) {
        guard let value = Int(code) else {
            self = .failed
            return
        }
        switch value {
        case 200..<300: self = .success
        case 300..<400: self = .redirect
        case 400..<500: self = .clientError
        case 500..<600: self = .serverError
        default:        self = .failed
        }
    }

    var title: String {
        switch self {
        case .pending:     return "Pending"
        case .success:     return "2xx Success"
        case .redirect:    return "3xx Redirect"
        case .clientError: return "4xx Client Error"
        case .serverError: return "5xx Server Error"
        case .failed:      return "Failed / No response"
        }
    }
}

struct ApiLogFilter {
    var statuses: Set<StatusClass> = []
    var methods: Set<String> = []
    var hosts: Set<String> = []

    var isActive: Bool {
        !statuses.isEmpty || !methods.isEmpty || !hosts.isEmpty
    }

    /// Total number of selected facets, used for the "Clear" affordance.
    var activeCount: Int {
        statuses.count + methods.count + hosts.count
    }

    func matches(_ log: ApiLog) -> Bool {
        if !statuses.isEmpty, !statuses.contains(StatusClass(log: log)) {
            return false
        }
        if !methods.isEmpty, !methods.contains(log.method.uppercased()) {
            return false
        }
        // Checked last so the URL parse in `ApiLog.host` only runs when the host
        // facet is actually in use — `reload()` filters the whole bucket on every
        // incoming log.
        if !hosts.isEmpty {
            guard let host = log.host, hosts.contains(host) else { return false }
        }
        return true
    }

    mutating func toggle<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<ApiLogFilter, Set<T>>) {
        if self[keyPath: keyPath].contains(value) {
            self[keyPath: keyPath].remove(value)
        } else {
            self[keyPath: keyPath].insert(value)
        }
    }
}

extension ApiLog {

    /// Host component of the logged URL, lowercased.
    ///
    /// `nil` for EventTracker entries, whose `url` holds an event name rather
    /// than a real URL.
    var host: String? {
        URLComponents(string: url)?.host?.lowercased()
    }
}
