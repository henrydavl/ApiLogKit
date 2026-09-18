//
//  PersistedApiLogTests.swift
//  ApiLogKitTests
//
//  The `[String: Any]` → JSON-string round trip is the part most likely to lose
//  data silently, so it gets the most attention here.
//

import XCTest
@testable import ApiLogKit

final class PersistedApiLogTests: XCTestCase {

    // MARK: - Dictionary coding

    func testNestedDictionarySurvivesRoundTrip() {
        let original: [String: Any] = [
            "user": ["id": 42, "name": "Ada"],
            "tags": ["a", "b"],
            "active": true
        ]

        let restored = PersistedApiLog.decode(PersistedApiLog.encode(original))

        let user = restored["user"] as? [String: Any]
        XCTAssertEqual(user?["id"] as? Int, 42, "nested objects must survive — the JSON tree viewer renders them")
        XCTAssertEqual(user?["name"] as? String, "Ada")
        XCTAssertEqual(restored["tags"] as? [String], ["a", "b"])
        XCTAssertEqual(restored["active"] as? Bool, true)
    }

    func testEmptyDictionaryRoundTrips() {
        XCTAssertEqual(PersistedApiLog.encode([:]), "{}")
        XCTAssertTrue(PersistedApiLog.decode("{}").isEmpty)
    }

    /// Header dictionaries sometimes hold values `JSONSerialization` rejects.
    /// Those must degrade to a description, not take the whole entry down.
    func testNonJSONValuesAreCoercedRatherThanDropped() {
        let original: [String: Any] = ["when": Date(timeIntervalSince1970: 0), "ok": 1]

        let encoded = PersistedApiLog.encode(original)
        let restored = PersistedApiLog.decode(encoded)

        XCTAssertNotEqual(encoded, "{}", "an unencodable value must not discard the whole dictionary")
        XCTAssertEqual(restored.count, 2)
        XCTAssertNotNil(restored["when"] as? String)
    }

    func testMalformedJSONDecodesToEmpty() {
        XCTAssertTrue(PersistedApiLog.decode("not json").isEmpty)
        XCTAssertTrue(PersistedApiLog.decode("[1,2,3]").isEmpty, "a top-level array isn't a dictionary")
    }

    // MARK: - Truncation

    func testTruncationRespectsBudgetAndMarksTheBody() {
        let body = String(repeating: "x", count: 5_000)

        let truncated = PersistedApiLog.truncate(body, toBytes: 1_000)

        XCTAssertTrue(truncated.hasPrefix(String(repeating: "x", count: 1_000)))
        XCTAssertTrue(truncated.contains("truncated"), "a clipped body must say so")
        XCTAssertLessThan(truncated.count, body.count)
    }

    func testShortBodyIsLeftAlone() {
        let body = #"{"ok":true}"#
        XCTAssertEqual(PersistedApiLog.truncate(body, toBytes: 1_000), body)
    }

    /// Slicing a byte budget mid-character must not leave replacement characters
    /// stuck to the marker.
    func testTruncationHandlesMultibyteCharacters() {
        let body = String(repeating: "日", count: 100) // 3 bytes each

        let truncated = PersistedApiLog.truncate(body, toBytes: 10)

        XCTAssertFalse(truncated.contains("\u{FFFD}"))
        XCTAssertTrue(truncated.hasPrefix("日日日"))
    }

    // MARK: - Entry round trip

    func testApiLogRoundTrip() {
        let original = ApiLog(
            responseCode: "201",
            method: "POST",
            url: "https://api.example.com/v1/users",
            responseTime: "0.42",
            size: "2048",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            responseHeader: ["Content-Type": "application/json"],
            responseBody: #"{"id":1}"#,
            requestHeader: ["Accept": "application/json"],
            requestBody: ["name": "Ada"]
        )

        let restored = PersistedApiLog(original, maxBodyBytes: 64 * 1024).toApiLog()

        XCTAssertEqual(restored.responseCode, "201")
        XCTAssertEqual(restored.method, "POST")
        XCTAssertEqual(restored.url, original.url)
        XCTAssertEqual(restored.responseTime, "0.42")
        XCTAssertEqual(restored.size, "2048")
        XCTAssertEqual(restored.date, original.date)
        XCTAssertEqual(restored.responseBody, original.responseBody)
        XCTAssertEqual(restored.requestHeader["Accept"] as? String, "application/json")
        XCTAssertEqual(restored.requestBody["name"] as? String, "Ada")
        XCTAssertEqual(restored.state, .finished)
    }

    func testRestoredEntryGetsFreshIdentity() {
        let original = ApiLog(
            responseCode: "200", method: "GET", url: "https://example.com",
            responseTime: "0.1", size: "1", date: Date(),
            responseHeader: [:], responseBody: "", requestHeader: [:], requestBody: [:]
        )

        let restored = PersistedApiLog(original, maxBodyBytes: 1_024).toApiLog()

        XCTAssertNotEqual(restored.id, original.id, "a restored entry is new to this session")
    }

    func testRawRequestBodyTextIsPreserved() {
        var original = ApiLog(
            responseCode: "200", method: "POST", url: "https://example.com",
            responseTime: "0.1", size: "1", date: Date(),
            responseHeader: [:], responseBody: "", requestHeader: [:], requestBody: [:]
        )
        original.requestBodyText = "grant_type=refresh_token&token=abc"

        let restored = PersistedApiLog(original, maxBodyBytes: 1_024).toApiLog()

        XCTAssertEqual(restored.requestBodyText, "grant_type=refresh_token&token=abc")
    }

    // MARK: - Archive

    func testArchiveEncodesAndDecodes() {
        let log = PersistedApiLog(
            ApiLog(
                responseCode: "200", method: "GET", url: "https://example.com",
                responseTime: "0.1", size: "1", date: Date(),
                responseHeader: [:], responseBody: "", requestHeader: [:], requestBody: [:]
            ),
            maxBodyBytes: 1_024
        )
        let archive = PersistedLogArchive(api: [log], eventTracker: [], thirdParty: [log])

        let data = try! JSONEncoder().encode(archive)
        let decoded = try! JSONDecoder().decode(PersistedLogArchive.self, from: data)

        XCTAssertEqual(decoded.version, PersistedLogArchive.currentVersion)
        XCTAssertEqual(decoded.api.count, 1)
        XCTAssertTrue(decoded.eventTracker.isEmpty)
        XCTAssertEqual(decoded.thirdParty.count, 1)
    }
}
