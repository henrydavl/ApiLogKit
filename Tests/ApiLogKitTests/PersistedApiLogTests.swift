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

    /// Identity is now carried across the round trip rather than regenerated.
    ///
    /// It used to be regenerated on the grounds that a restored entry is new to
    /// this session, which was harmless while the archive was the only store.
    /// The journal changed that: an in-flight entry is written when the request
    /// leaves and again when it completes, and the two lines are collapsed by
    /// id. A fresh id on read would turn every completed request into two
    /// entries.
    func testRestoredEntryKeepsItsIdentity() {
        let original = ApiLog(
            responseCode: "200", method: "GET", url: "https://example.com",
            responseTime: "0.1", size: "1", date: Date(),
            responseHeader: [:], responseBody: "", requestHeader: [:], requestBody: [:]
        )

        let restored = PersistedApiLog(original, maxBodyBytes: 1_024).toApiLog()

        XCTAssertEqual(restored.id, original.id, "the journal collapses an entry's lines by id")
    }

    /// In-flight entries used to be dropped at save time; they are now stored,
    /// because a request that never came back is the strongest evidence there
    /// is about a crash.
    func testPendingEntrySurvivesTheRoundTripStillPending() {
        let original = ApiLog(method: "POST", url: "https://example.com/checkout")

        let restored = PersistedApiLog(original, maxBodyBytes: 1_024).toApiLog()

        XCTAssertEqual(restored.state, .pending)
        XCTAssertEqual(restored.id, original.id)
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
