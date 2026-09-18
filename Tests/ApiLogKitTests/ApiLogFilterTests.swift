//
//  ApiLogFilterTests.swift
//  ApiLogKitTests
//

import XCTest
@testable import ApiLogKit

final class ApiLogFilterTests: XCTestCase {

    private func makeLog(
        url: String = "https://api.example.com/v1/users",
        code: String = "200",
        method: String = "GET"
    ) -> ApiLog {
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

    // MARK: - Status classification

    func testStatusClassification() {
        XCTAssertEqual(StatusClass(code: "204"), .success)
        XCTAssertEqual(StatusClass(code: "301"), .redirect)
        XCTAssertEqual(StatusClass(code: "404"), .clientError)
        XCTAssertEqual(StatusClass(code: "503"), .serverError)
    }

    /// The interceptor stores `URLError` codes and sentinels for calls that never
    /// reached a server; all of them must read as failures, not as some 2xx.
    func testUnreachableCallsClassifyAsFailed() {
        XCTAssertEqual(StatusClass(code: "-1009"), .failed, "URLError.notConnectedToInternet")
        XCTAssertEqual(StatusClass(code: "-1"), .failed)
        XCTAssertEqual(StatusClass(code: "0"), .failed)
        XCTAssertEqual(StatusClass(code: ""), .failed)
        XCTAssertEqual(StatusClass(code: "not a number"), .failed)
    }

    func testPendingEntryClassifiesAsPendingNotFailed() {
        let pending = ApiLog(method: "POST", url: "https://api.example.com/login")
        XCTAssertEqual(
            StatusClass(log: pending), .pending,
            "an in-flight entry has an empty code but must not be bucketed as a failure"
        )
    }

    // MARK: - Matching

    func testEmptyFilterMatchesEverything() {
        let filter = ApiLogFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertTrue(filter.matches(makeLog()))
        XCTAssertTrue(filter.matches(makeLog(code: "500")))
    }

    func testStatusFacetMatchesAnySelected() {
        var filter = ApiLogFilter()
        filter.statuses = [.clientError, .serverError]

        XCTAssertTrue(filter.matches(makeLog(code: "404")))
        XCTAssertTrue(filter.matches(makeLog(code: "500")))
        XCTAssertFalse(filter.matches(makeLog(code: "200")))
    }

    func testMethodFacetIsCaseInsensitive() {
        var filter = ApiLogFilter()
        filter.methods = ["POST"]

        XCTAssertTrue(filter.matches(makeLog(method: "post")))
        XCTAssertFalse(filter.matches(makeLog(method: "GET")))
    }

    func testHostFacetMatchesExactHost() {
        var filter = ApiLogFilter()
        filter.hosts = ["api.example.com"]

        XCTAssertTrue(filter.matches(makeLog(url: "https://api.example.com/v1/users")))
        XCTAssertFalse(filter.matches(makeLog(url: "https://cdn.example.com/img.png")))
    }

    /// EventTracker entries hold an event name in `url`, so they have no host.
    func testHostFacetExcludesEntriesWithoutHost() {
        var filter = ApiLogFilter()
        filter.hosts = ["api.example.com"]

        let event = ApiLog(eventName: "purchase_completed", requestBody: [:], responseBody: "")
        XCTAssertFalse(filter.matches(event))
    }

    /// Facets combine with AND: an entry has to satisfy every active one.
    func testFacetsCombineWithAnd() {
        var filter = ApiLogFilter()
        filter.statuses = [.clientError]
        filter.methods = ["POST"]

        XCTAssertTrue(filter.matches(makeLog(code: "404", method: "POST")))
        XCTAssertFalse(filter.matches(makeLog(code: "404", method: "GET")),
                       "matching status alone is not enough")
        XCTAssertFalse(filter.matches(makeLog(code: "200", method: "POST")),
                       "matching method alone is not enough")
    }

    // MARK: - Toggling

    func testToggleAddsThenRemoves() {
        var filter = ApiLogFilter()

        filter.toggle(StatusClass.success, in: \.statuses)
        XCTAssertEqual(filter.statuses, [.success])
        XCTAssertTrue(filter.isActive)

        filter.toggle(StatusClass.success, in: \.statuses)
        XCTAssertTrue(filter.statuses.isEmpty)
        XCTAssertFalse(filter.isActive)
    }
}
