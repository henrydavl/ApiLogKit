//
//  ApiLoggerTests.swift
//  ApiLogKitTests
//
//  `ApiLogger` is a singleton, so every test clears it first. `clearLogs()`
//  dispatches asynchronously onto the logger's queue while `getLogs()` reads it
//  synchronously — the sync read serialises behind the pending write, so the
//  reads below are deterministic without any waiting.
//

import XCTest
@testable import ApiLogKit

final class ApiLoggerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ApiLogger.shared.isEnabled = true
        ApiLogger.shared.clearLogs()
    }

    // MARK: - Helpers

    private func makeFinished(url: String, code: String = "200", method: String = "GET") -> ApiLog {
        ApiLog(
            responseCode: code,
            method: method,
            url: url,
            responseTime: "0.10",
            size: "12",
            date: Date(),
            responseHeader: [:],
            responseBody: "{}",
            requestHeader: [:],
            requestBody: [:]
        )
    }

    // MARK: - Basic recording

    func testAddLogAppendsFinishedEntry() {
        ApiLogger.shared.addLog(makeFinished(url: "https://example.com/a"))

        let logs = ApiLogger.shared.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].state, .finished, "addLog entries already have a response")
    }

    func testDisabledLoggerDropsEntries() {
        ApiLogger.shared.isEnabled = false
        defer { ApiLogger.shared.isEnabled = true }

        ApiLogger.shared.addLog(makeFinished(url: "https://example.com/a"))

        XCTAssertTrue(ApiLogger.shared.getLogs().isEmpty)
    }

    // MARK: - In-flight lifecycle

    func testBeginLogInsertsPendingEntry() {
        ApiLogger.shared.beginLog(method: "POST", url: "https://example.com/login")

        let logs = ApiLogger.shared.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].state, .pending)
        XCTAssertEqual(logs[0].method, "POST")
        XCTAssertEqual(logs[0].responseCode, "", "no status is known while in flight")
    }

    func testCompleteLogFillsEntryInPlace() {
        let token = ApiLogger.shared.beginLog(method: "POST", url: "https://example.com/login")
        ApiLogger.shared.completeLog(token, with: makeFinished(url: "https://example.com/login", code: "201"))

        let logs = ApiLogger.shared.getLogs()
        XCTAssertEqual(logs.count, 1, "completing must not append a second entry")
        XCTAssertEqual(logs[0].state, .finished)
        XCTAssertEqual(logs[0].responseCode, "201")
    }

    /// The row must not be torn down or reordered when it completes — SwiftUI
    /// matches rows by id, and the list sorts by insertion order.
    func testCompleteLogPreservesIdentityStartTimeAndPosition() {
        let token = ApiLogger.shared.beginLog(method: "GET", url: "https://example.com/slow")
        let pending = ApiLogger.shared.getLogs()[0]

        // A second request finishes while the first is still in flight.
        ApiLogger.shared.addLog(makeFinished(url: "https://example.com/fast"))

        ApiLogger.shared.completeLog(token, with: makeFinished(url: "https://example.com/slow"))

        let logs = ApiLogger.shared.getLogs()
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs[0].id, pending.id, "identity must survive completion")
        XCTAssertEqual(logs[0].date, pending.date, "start time is kept, not the response time")
        XCTAssertEqual(logs[0].url, "https://example.com/slow", "the entry stays in its original slot")
    }

    func testCompleteLogIgnoresClearedEntry() {
        let token = ApiLogger.shared.beginLog(method: "GET", url: "https://example.com/gone")
        ApiLogger.shared.clearLogs()

        ApiLogger.shared.completeLog(token, with: makeFinished(url: "https://example.com/gone"))

        XCTAssertTrue(ApiLogger.shared.getLogs().isEmpty, "a stale token must not resurrect an entry")
    }

    func testBeginLogRoutesToApiBucketOnly() {
        ApiLogger.shared.beginLog(method: "GET", url: "https://example.com/a")

        XCTAssertEqual(ApiLogger.shared.getLogs().count, 1)
        XCTAssertTrue(ApiLogger.shared.getThirdPartyLogs().isEmpty)
        XCTAssertTrue(ApiLogger.shared.getEventTrackerLogs().isEmpty)
    }

    // MARK: - Retention

    func testThirdPartyBucketTrimsOldestFirst() {
        let previous = ApiLogKitConfig.thirdPartyTracker.maxEntries
        ApiLogKitConfig.thirdPartyTracker.maxEntries = 3
        defer { ApiLogKitConfig.thirdPartyTracker.maxEntries = previous }

        for index in 0..<5 {
            ApiLogger.shared.addThirdPartyLog(makeFinished(url: "https://example.com/\(index)"))
        }

        let logs = ApiLogger.shared.getThirdPartyLogs()
        XCTAssertEqual(logs.count, 3)
        XCTAssertEqual(logs.map(\.url), [
            "https://example.com/2",
            "https://example.com/3",
            "https://example.com/4"
        ])
    }

    /// The manual buckets are deliberately uncapped — only the self-filling
    /// 3rd-party bucket is trimmed.
    func testApiBucketIsNotTrimmed() {
        let previous = ApiLogKitConfig.thirdPartyTracker.maxEntries
        ApiLogKitConfig.thirdPartyTracker.maxEntries = 2
        defer { ApiLogKitConfig.thirdPartyTracker.maxEntries = previous }

        for index in 0..<5 {
            ApiLogger.shared.addLog(makeFinished(url: "https://example.com/\(index)"))
        }

        XCTAssertEqual(ApiLogger.shared.getLogs().count, 5)
    }
}
