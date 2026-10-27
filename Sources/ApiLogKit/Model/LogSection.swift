//
//  LogSection.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import Foundation

public struct Log {
    var key: String
    var value: String
}

public enum LogSection: Int, CaseIterable {
    /// The crash this entry is blamed for. Listed **first**, and only on an
    /// entry that carries one: when you open that row you are not browsing
    /// traffic, you are looking for what killed the app, so the stack trace
    /// belongs above the payload rather than under it.
    case crash = -1
    case requestURL = 0
    case requestHeader
    case requestBody
    case responseHeader
    case responseBody

    public func title(for logType: LogEventType) -> String {
        switch self {
        case .crash:
            return "Crash"
        case .requestURL:
            return logType == .eventTracker ? "Event Name" : "Request URL"
        case .requestHeader:
            return "Request Header"
        case .requestBody:
            return logType == .eventTracker ? "Event Parameters" : "Request Body"
        case .responseHeader:
            return "Response Header"
        case .responseBody:
            return "Response Body"
        }
    }

    public func isAvailable(for logType: LogEventType) -> Bool {
        switch self {
        case .requestURL, .requestBody, .responseBody:
            return true
        case .requestHeader, .responseHeader:
            return logType.isHTTP
        // Availability is per log type; whether the entry actually carries a
        // crash is decided by the detail view model, which can see the entry.
        case .crash:
            return true
        }
    }
}
