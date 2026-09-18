//
//  ApiLogDetailViewModel.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import Combine
import Foundation

/// Identifiable wrapper around `Log` for use in `ForEach`.
struct ApiLogDetailRow: Identifiable {
    let id = UUID()
    let log: Log
    var key: String { log.key }
    var value: String { log.value }
}

final class ApiLogDetailViewModel: ObservableObject {
    /// Republished so the screen fills in when an entry opened while in flight
    /// gets its response.
    @Published private(set) var log: ApiLog

    let logType: LogEventType
    let sections: [LogSection]

    /// Parsed JSON for the body sections (nil when the body isn't JSON).
    private(set) var requestJSON: JSONNode?
    private(set) var responseJSON: JSONNode?

    /// Expansion-state models for the JSON tree views (shared between the tree
    /// and its expand/collapse controls so the controls stay in a stable row).
    private(set) var requestTree: JSONTreeModel?
    private(set) var responseTree: JSONTreeModel?

    private var rowsBySection: [LogSection: [ApiLogDetailRow]] = [:]
    private var cancellables = Set<AnyCancellable>()

    private static let chunkSize = 2_000

    /// True while the request is still in flight — the response sections are
    /// empty because there's nothing to show yet, not because anything is wrong.
    var isPending: Bool { log.state == .pending }

    init(log: ApiLog, logType: LogEventType) {
        self.log = log
        self.logType = logType
        self.sections = LogSection.allCases.filter { $0.isAvailable(for: logType) }
        rebuild()
        observeCompletion()
    }

    // MARK: - Live updates

    /// Watches this one entry for its pending → finished transition.
    ///
    /// Deliberately cheap: once the entry is finished the first guard fails
    /// immediately, so a busy logger emitting on every request costs nothing
    /// here. An entry only ever completes once, so there's nothing else to
    /// watch for.
    private func observeCompletion() {
        guard isPending else { return }

        ApiLogger.shared.publisher(for: logType)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                guard let self, self.isPending,
                      let updated = logs.first(where: { $0.id == self.log.id }),
                      updated.state == .finished
                else { return }

                self.log = updated
                self.rebuild()
            }
            .store(in: &cancellables)
    }

    /// Re-derives every display value from `log`.
    private func rebuild() {
        // Intercepted logs carry a raw payload instead of a dictionary; parse it
        // so JSON bodies still get the tree viewer, and fall through to plain text
        // for form-encoded or binary payloads.
        let requestJSON = log.requestBodyText.flatMap { JSONNode.parse($0) }
            ?? JSONNode.from(dictionary: log.requestBody)
        let responseJSON = JSONNode.parse(log.responseBody)
        self.requestJSON = requestJSON
        self.responseJSON = responseJSON
        self.requestTree = requestJSON.map { JSONTreeModel(root: $0) }
        self.responseTree = responseJSON.map { JSONTreeModel(root: $0) }

        let requestHeader = Self.logs(from: log.requestHeader)
        let responseHeader = Self.logs(from: log.responseHeader)

        // Body text mode: prefer pretty-printed JSON when the body parses,
        // otherwise fall back to the original payload.
        let requestBodyText = requestJSON?.prettyPrinted()
            ?? log.requestBodyText
            ?? Self.keyValueDump(log.requestBody)
        let responseBodyText = responseJSON?.prettyPrinted() ?? log.responseBody
        let requestBody = Self.chunked([Log(key: "", value: requestBodyText)])
        let responseBody = Self.chunked([Log(key: "", value: responseBodyText)])

        rowsBySection = [
            .requestURL: [ApiLogDetailRow(log: Log(key: "", value: log.url))],
            .requestHeader: requestHeader.map { ApiLogDetailRow(log: $0) },
            .requestBody: requestBody.map { ApiLogDetailRow(log: $0) },
            .responseHeader: responseHeader.map { ApiLogDetailRow(log: $0) },
            .responseBody: responseBody.map { ApiLogDetailRow(log: $0) }
        ]
    }

    // MARK: - Data access

    func title(for section: LogSection) -> String {
        section.title(for: logType)
    }

    func rows(for section: LogSection) -> [ApiLogDetailRow] {
        rowsBySection[section] ?? []
    }

    /// Parsed JSON tree for a section, if the body is JSON.
    func jsonNode(for section: LogSection) -> JSONNode? {
        switch section {
        case .requestBody:  return requestJSON
        case .responseBody: return responseJSON
        default:            return nil
        }
    }

    /// Shared expansion-state model for a section's JSON tree.
    func treeModel(for section: LogSection) -> JSONTreeModel? {
        switch section {
        case .requestBody:  return requestTree
        case .responseBody: return responseTree
        default:            return nil
        }
    }

    /// Whether any body section can be shown as a JSON tree.
    var hasJSONBody: Bool {
        requestJSON != nil || responseJSON != nil
    }

    /// Full value copied when the section's "Copy" button is tapped.
    func copyValue(for section: LogSection) -> String {
        switch section {
        case .requestURL:     return log.url
        case .requestHeader:  return "\(log.requestHeader)"
        case .requestBody:    return requestJSON?.prettyPrinted() ?? log.requestBodyText ?? "\(log.requestBody)"
        case .responseHeader: return "\(log.responseHeader)"
        case .responseBody:   return responseJSON?.prettyPrinted() ?? log.responseBody
        }
    }

    // MARK: - Export

    func exportRawLog() -> String { ApiLogExporter.rawLog(for: log) }
    func exportCurl() -> String { ApiLogExporter.curl(for: log) }

    // MARK: - Helpers

    private static func logs(from dictionary: [String: Any], isJsonize: Bool = false) -> [Log] {
        dictionary.map { key, value in
            let stringValue = String(describing: value)
            return Log(key: key, value: isJsonize ? stringValue.jsonize() : stringValue)
        }
    }

    /// Readable `key: value` dump, used only when a body dictionary isn't JSON.
    private static func keyValueDump(_ dictionary: [String: Any]) -> String {
        dictionary.keys.sorted()
            .map { "\($0): \(String(describing: dictionary[$0]!).jsonize())" }
            .joined(separator: "\n")
    }

    /// Splits oversized values into `chunkSize` pieces so SwiftUI `Text`
    /// doesn't choke on very long strings (mirrors the legacy chunking).
    private static func chunked(_ logs: [Log]) -> [Log] {
        logs.flatMap { log -> [Log] in
            guard log.value.count > chunkSize else { return [log] }
            var result: [Log] = []
            var offset = log.value.startIndex
            var isFirst = true
            while offset < log.value.endIndex {
                let distance = log.value.distance(from: offset, to: log.value.endIndex)
                let end = log.value.index(offset, offsetBy: min(chunkSize, distance))
                result.append(Log(key: isFirst ? log.key : "", value: String(log.value[offset..<end])))
                offset = end
                isFirst = false
            }
            return result
        }
    }
}
