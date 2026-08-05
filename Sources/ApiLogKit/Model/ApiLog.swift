//
//  ApiLog.swift
//  ApiLogKit
//

import Foundation

public struct ApiLog: Identifiable {
    /// Stable identity, assigned once when the entry is created.
    ///
    /// The list rebuilds its rows on every logger emission, so this must not be
    /// derived from the log's contents or regenerated on rebuild — SwiftUI uses
    /// it to match old rows to new ones, and a changing id tears down the row
    /// (popping any detail screen pushed from it).
    public let id = UUID()

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
