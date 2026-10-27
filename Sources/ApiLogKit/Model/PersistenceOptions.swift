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

    /// Whether a crash is recorded and pinned to the exchange that was live
    /// when it happened. On by default — it is what makes persistence useful
    /// for debugging a crash rather than only for reading back old traffic.
    ///
    /// Both an uncaught `NSException` and the fatal signals Swift traps with
    /// (a force unwrap of nil, an out-of-range index, `fatalError`) are
    /// caught. Whatever handler was already installed is always called
    /// afterwards, so your crash reporter is unaffected; set this to `false`
    /// to keep ApiLogKit off the crash path entirely.
    ///
    /// Note that the entries themselves survive either way: durability comes
    /// from the write-ahead journal, not from the crash handler. This flag only
    /// controls whether the crash is *identified and linked*.
    public var captureCrashes: Bool = true

    public init() {}
}
