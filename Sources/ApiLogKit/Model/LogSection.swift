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
    case requestURL = 0
    case requestHeader
    case requestBody
    case responseHeader
    case responseBody

    public func title(for logType: LogEventType) -> String {
        switch self {
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
            return logType == .api
        }
    }
}
