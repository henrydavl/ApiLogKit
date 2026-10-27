//
//  LogEventType.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

/// Raw-valued and `Codable` so the on-disk journal can record which bucket an
/// entry belongs to; the cases are unchanged.
public enum LogEventType: String, Codable {
    case api
    case eventTracker
    case thirdParty

    /// True for buckets backed by real HTTP traffic. EventTracker entries are
    /// synthesised from analytics events and have no headers or status code.
    public var isHTTP: Bool { self != .eventTracker }
}
