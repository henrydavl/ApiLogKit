//
//  PersistenceOptions.swift
//  ApiLogKit
//
//  Retention budget for logs written to disk.
//

import Foundation

public struct PersistenceOptions {

    /// Entries kept per bucket, newest first. Deliberately lower than the
    /// in-memory caps — this budget is multiplied by the body size below, and
    /// the archive is rewritten in full on every save.
    public var maxEntries: Int = 200

    /// Per-body cap on disk. Bodies are truncated with a visible marker rather
    /// than dropped, so a clipped payload can't be mistaken for the real one.
    ///
    /// The in-memory cap (`ThirdPartyTrackerOptions.maxBodyBytes`) is 512 KB;
    /// persisting at that size would mean a worst case of hundreds of megabytes,
    /// hence the much smaller default here.
    public var maxBodyBytes: Int = 64 * 1024

    public init() {}
}
