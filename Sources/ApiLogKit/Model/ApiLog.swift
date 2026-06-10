//
//  ApiLog.swift
//  ApiLogKit
//

import Foundation

public struct ApiLog {
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
        requestBody: [String: Any]
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
