//
//  ApiLogDetailViewModelTests.swift
//  ApiLogKitTests
//
//  The detail screen can be opened on a request that hasn't come back yet, so it
//  has to fill itself in when the response lands.
//

import XCTest
@testable import ApiLogKit

final class ApiLogDetailViewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ApiLogger.shared.isEnabled = true
        ApiLogger.shared.clearLogs()
    }

    private func makeFinished(url: String, code: String = "200", body: String) -> ApiLog {
        ApiLog(
            responseCode: code,
            method: "POST",
            url: url,
            responseTime: "0.42",
            size: "\(body.utf8.count)",
            date: Date(),
            responseHeader: ["Content-Type": "application/json"],
            responseBody: body,
            requestHeader: ["Accept": "application/json"],
            requestBody: ["user": "ada"]
        )
    }

    /// Waits for `condition` to come true on the main queue.
    private func wait(for condition: @escaping () -> Bool, timeout: TimeInterval = 2) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        wait(for: [expectation], timeout: timeout)
    }

    func testDetailStartsPendingForAnInFlightEntry() {
        let token = ApiLogger.shared.beginLog(method: "POST", url: "https://example.com/login")
        _ = token

        let pending = ApiLogger.shared.getLogs()[0]
        let viewModel = ApiLogDetailViewModel(log: pending, logType: .api)

        XCTAssertTrue(viewModel.isPending)
        XCTAssertTrue(viewModel.rows(for: .responseBody).first?.value.isEmpty ?? false,
                      "there is no response to show yet")
    }

    /// The request side is fully known while in flight — which is the whole
    /// reason the screen stays reachable for a pending entry.
    func testRequestSideIsAvailableWhilePending() {
        ApiLogger.shared.beginLog(
            method: "POST",
            url: "https://example.com/login",
            requestHeader: ["Accept": "application/json"],
            requestBody: ["user": "ada"]
        )

        let pending = ApiLogger.shared.getLogs()[0]
        let viewModel = ApiLogDetailViewModel(log: pending, logType: .api)

        XCTAssertEqual(viewModel.rows(for: .requestURL).first?.value, "https://example.com/login")
        XCTAssertFalse(viewModel.rows(for: .requestHeader).isEmpty)
        XCTAssertTrue(viewModel.rows(for: .requestBody).first?.value.contains("ada") ?? false)
    }

    func testDetailFillsInWhenTheEntryCompletes() {
        let token = ApiLogger.shared.beginLog(method: "POST", url: "https://example.com/login")
        let pending = ApiLogger.shared.getLogs()[0]
        let viewModel = ApiLogDetailViewModel(log: pending, logType: .api)
        XCTAssertTrue(viewModel.isPending)

        ApiLogger.shared.completeLog(
            token,
            with: makeFinished(url: "https://example.com/login", code: "201", body: #"{"token":"abc"}"#)
        )

        wait(for: { viewModel.isPending == false })

        XCTAssertEqual(viewModel.log.responseCode, "201")
        XCTAssertTrue(
            viewModel.rows(for: .responseBody).first?.value.contains("abc") ?? false,
            "the derived body rows must be rebuilt, not just the raw log"
        )
        XCTAssertFalse(viewModel.rows(for: .responseHeader).isEmpty)
        XCTAssertNotNil(viewModel.responseJSON, "the JSON tree should exist once a body arrives")
    }

    /// The screen watches one entry, not the bucket — traffic from elsewhere must
    /// not overwrite what's on screen.
    func testUnrelatedTrafficDoesNotDisturbTheDetail() {
        ApiLogger.shared.beginLog(method: "POST", url: "https://example.com/login")
        let pending = ApiLogger.shared.getLogs()[0]
        let viewModel = ApiLogDetailViewModel(log: pending, logType: .api)

        // A different request completes while this one is still in flight.
        let other = ApiLogger.shared.beginLog(method: "GET", url: "https://example.com/other")
        ApiLogger.shared.completeLog(
            other,
            with: makeFinished(url: "https://example.com/other", body: #"{"other":true}"#)
        )

        let settled = expectation(description: "let any emissions land")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 1)

        XCTAssertTrue(viewModel.isPending, "another entry completing must not resolve this one")
        XCTAssertEqual(viewModel.log.url, "https://example.com/login")
    }

    func testDetailOpenedOnFinishedEntryStaysPut() {
        ApiLogger.shared.addLog(makeFinished(url: "https://example.com/done", body: #"{"ok":true}"#))
        let finished = ApiLogger.shared.getLogs()[0]

        let viewModel = ApiLogDetailViewModel(log: finished, logType: .api)

        XCTAssertFalse(viewModel.isPending)
        XCTAssertEqual(viewModel.log.responseCode, "200")
    }
}
