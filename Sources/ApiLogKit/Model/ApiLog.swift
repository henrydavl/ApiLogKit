//
//  ApiLog.swift
//  ApiLogKit
//

import Foundation

/// Lifecycle of a logged exchange.
public enum ApiLogState {
    /// Request sent, no response yet. The response fields are placeholders.
    case pending
    /// The exchange finished — successfully or not. `responseCode` tells which.
    case finished
}

public struct ApiLog: Identifiable {
    /// Stable identity, assigned once when the entry is created.
    ///
    /// The list rebuilds its rows on every logger emission, so this must not be
    /// derived from the log's contents or regenerated on rebuild — SwiftUI uses
    /// it to match old rows to new ones, and a changing id tears down the row
    /// (popping any detail screen pushed from it).
    ///
    /// Read-only from outside: the only writer is `restoreIdentity(id:date:)`,
    /// which exists so a pending entry keeps its identity when its response
    /// fields are filled in.
    public private(set) var id = UUID()

    public var responseCode: String
    public var method: String
    public var url: String
    public var responseTime: String
    public var size: String
    public var date: Date
    public var responseHeader: [String: Any]
    public var responseBody: String
    public var requestHeader: [String: Any]
    public var requestBody: [String: Any]

    /// Raw request payload, used when the body isn't a dictionary — form-encoded,
    /// multipart or binary bodies captured by the 3rd-party tracker, for example.
    /// When set it takes precedence over `requestBody` for display and export.
    public var requestBodyText: String?

    /// Whether the exchange is still in flight.
    ///
    /// Defaults to `.finished`, so entries recorded through `addLog` — which is
    /// only called once a response exists — keep behaving exactly as before.
    /// Only the `beginLog`/`completeLog` pair and the 3rd-party interceptor
    /// produce `.pending` entries.
    public var state: ApiLogState = .finished

    /// Whether this entry was loaded from disk rather than recorded in this
    /// session — see `ApiLogger.enablePersistence(_:)`.
    ///
    /// Set only by the restore path, so anything the host app records is false
    /// by definition.
    public private(set) var isRestored: Bool = false

    public init(
        responseCode: String,
        method: String,
        url: String,
        responseTime: String,
        size: String,
        date: Date,
        responseHeader: [String: Any],
        responseBody: String,
        requestHeader: [String: Any],
        requestBody: [String: Any],
        requestBodyText: String? = nil
    ) {
        self.responseCode = responseCode
        self.method = method
        self.url = url
        self.responseTime = responseTime
        self.size = size
        self.date = date
        self.responseHeader = responseHeader
        self.responseBody = responseBody
        self.requestHeader = requestHeader
        self.requestBody = requestBody
        self.requestBodyText = requestBodyText
    }

    /// Carries a pending entry's identity and start time across the wholesale
    /// field replacement in `ApiLogger.completeLog(_:with:)`.
    mutating func restoreIdentity(id: UUID, date: Date) {
        self.id = id
        self.date = date
    }

    /// Flags this entry as coming from a previous session. Applied by
    /// `ApiLogger.restore(api:eventTracker:thirdParty:)`.
    mutating func markRestored() {
        isRestored = true
    }

    /// In-flight entry: the request side is known, the response side isn't yet.
    ///
    /// Produced by `ApiLogger.beginLog(...)`; the response fields are
    /// placeholders until `completeLog(_:with:)` fills them in.
    public init(
        method: String,
        url: String,
        requestHeader: [String: Any] = [:],
        requestBody: [String: Any] = [:],
        requestBodyText: String? = nil,
        date: Date = Date()
    ) {
        self.responseCode = ""
        self.method = method
        self.url = url
        self.responseTime = "0"
        self.size = "0"
        self.date = date
        self.responseHeader = [:]
        self.responseBody = ""
        self.requestHeader = requestHeader
        self.requestBody = requestBody
        self.requestBodyText = requestBodyText
        self.state = .pending
    }

    /// Analytics-style event entry (e.g. AppsFlyer) — no real HTTP fields.
    public init(
        eventName: String,
        requestBody: [String: Any],
        responseBody: String
    ) {
        self.responseCode = "00"
        self.method = "POST"
        self.url = eventName
        self.responseTime = "0"
        self.size = "0"
        self.date = Date()
        self.responseHeader = [:]
        self.responseBody = responseBody
        self.requestHeader = [:]
        self.requestBody = requestBody
    }
}
