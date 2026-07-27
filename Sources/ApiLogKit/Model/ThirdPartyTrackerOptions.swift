//
//  ThirdPartyTrackerOptions.swift
//  ApiLogKit
//
//  Tuning knobs for the 3rd-party traffic tracker.
//

import Foundation

public struct ThirdPartyTrackerOptions {

    /// Hosts that are never intercepted. Put your own API domains here so they
    /// keep flowing through your existing `addLog` pipeline untouched — and add
    /// any SDK that breaks under interception (certificate pinning, mainly).
    ///
    /// Matching is suffix-based on the host, so `example.com` also covers
    /// `api.example.com`.
    public var ignoredHosts: [String] = []

    /// When non-empty, acts as an allowlist — only these hosts are intercepted.
    /// Same suffix matching as `ignoredHosts`, which is applied first.
    public var allowedHosts: [String] = []

    /// Final say over whether a request is intercepted. Runs after the host
    /// lists; return `false` to leave the request alone entirely.
    public var shouldCapture: ((URLRequest) -> Bool)?

    /// Upper bound on how much of each request/response body is retained.
    /// Only the *captured copy* is truncated — the app still receives every byte.
    public var maxBodyBytes: Int = 512 * 1024

    /// Cap on retained entries. Unlike the manually populated buckets this one
    /// fills on its own, so it's trimmed oldest-first rather than growing without
    /// bound.
    public var maxEntries: Int = 500

    public init() {}

    // MARK: - Policy

    /// Whether `request` should be intercepted and logged.
    func allows(_ request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }

        if Self.matches(host, any: ignoredHosts) { return false }
        if !allowedHosts.isEmpty, !Self.matches(host, any: allowedHosts) { return false }
        if let shouldCapture, !shouldCapture(request) { return false }
        return true
    }

    /// Suffix match on host components, so `example.com` matches `example.com`
    /// and `api.example.com` but not `notexample.com`.
    private static func matches(_ host: String, any patterns: [String]) -> Bool {
        patterns.contains { pattern in
            let pattern = pattern.lowercased()
            guard !pattern.isEmpty else { return false }
            return host == pattern || host.hasSuffix("." + pattern)
        }
    }
}
