//
//  RestoredLogTests.swift
//  ApiLogKitTests
//
//  Entries loaded from disk have to be tellable apart from ones recorded in
//  this session.
//

import XCTest
@testable import ApiLogKit

final class RestoredLogTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ApiLogger.shared.isEnabled = true
        ApiLogger.shared.clearLogs()
    }

    private func makeLog(url: String, code: String = "200") -> ApiLog {
        ApiLog(
            responseCode: code,
            method: "GET",
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

    // MARK: - Flagging

    func testRecordedLogsAreNotMarkedRestored() {
        ApiLogger.shared.addLog(makeLog(url: "https://example.com/fresh"))

        XCTAssertFalse(ApiLogger.shared.getLogs()[0].isRestored)
    }

    func testPendingEntriesAreNotMarkedRestored() {
        ApiLogger.shared.beginLog(method: "POST", url: "https://example.com/inflight")

        XCTAssertFalse(ApiLogger.shared.getLogs()[0].isRestored)
    }

    func testRestoredEntriesAreMarkedAcrossEveryBucket() {
        ApiLogger.shared.restore(
            api: [makeLog(url: "https://example.com/a")],
            eventTracker: [makeLog(url: "event_name")],
            thirdParty: [makeLog(url: "https://sdk.example.com/b")]
        )

        XCTAssertTrue(ApiLogger.shared.getLogs()[0].isRestored)
        XCTAssertTrue(ApiLogger.shared.getEventTrackerLogs()[0].isRestored)
        XCTAssertTrue(ApiLogger.shared.getThirdPartyLogs()[0].isRestored)
    }

    /// Restored entries are older, so they go in front of the session's own.
    func testRestoredEntriesArePrependedAndStayContiguous() {
        ApiLogger.shared.addLog(makeLog(url: "https://example.com/new-1"))
        ApiLogger.shared.addLog(makeLog(url: "https://example.com/new-2"))

        ApiLogger.shared.restore(
            api: [makeLog(url: "https://example.com/old-1"), makeLog(url: "https://example.com/old-2")],
            eventTracker: [],
            thirdParty: []
        )

        let logs = ApiLogger.shared.getLogs()
        XCTAssertEqual(logs.map(\.url), [
            "https://example.com/old-1",
            "https://example.com/old-2",
            "https://example.com/new-1",
            "https://example.com/new-2"
        ])
        XCTAssertEqual(logs.map(\.isRestored), [true, true, false, false],
                       "the restored block must be contiguous — the divider depends on it")
    }

    /// Completing a request recorded in this session must not inherit the flag
    /// from anywhere, and restoring must not disturb an in-flight entry.
    func testCompletionOfASessionRequestStaysUnrestored() {
        let token = ApiLogger.shared.beginLog(method: "POST", url: "https://example.com/login")
        ApiLogger.shared.restore(api: [makeLog(url: "https://example.com/old")], eventTracker: [], thirdParty: [])

        ApiLogger.shared.completeLog(token, with: makeLog(url: "https://example.com/login", code: "201"))

        let live = ApiLogger.shared.getLogs().first { $0.url == "https://example.com/login" }
        XCTAssertEqual(live?.responseCode, "201")
        XCTAssertEqual(live?.isRestored, false)
    }

    // MARK: - Round trip

    /// The archive doesn't store the flag — it's applied on the way in — so a
    /// log restored twice is still just "restored".
    func testFlagIsNotStoredButReappliedOnRestore() {
        let persisted = PersistedApiLog(makeLog(url: "https://example.com/a"), maxBodyBytes: 1_024)
        XCTAssertFalse(persisted.toApiLog().isRestored, "decoding alone doesn't mark anything")

        ApiLogger.shared.restore(api: [persisted.toApiLog()], eventTracker: [], thirdParty: [])

        XCTAssertTrue(ApiLogger.shared.getLogs()[0].isRestored)
    }
}
