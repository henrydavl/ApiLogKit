//
//  ApiLogExporterTests.swift
//  ApiLogKitTests
//
//  The cURL export is only useful if running it sends what the app sent. A
//  base64 photo inside a form-encoded JSON field is the case that broke: `+`
//  went out unencoded and the `\/` escapes made the base64 uncopyable.
//

import XCTest
@testable import ApiLogKit

final class ApiLogExporterTests: XCTestCase {

    /// Bytes chosen so the base64 contains both `+` and `/`.
    private let photo = Data([0xFB, 0xEF, 0xBE, 0xFF, 0xFF, 0xFF, 0x00, 0x10]).base64EncodedString()

    /// What the host app logs: a JSON string written by `JSONSerialization`,
    /// which escapes every `/` as `\/`.
    private var payload: String {
        let data = try! JSONSerialization.data(withJSONObject: ["photo": photo, "name": "Menteng's"])
        return String(decoding: data, as: UTF8.self)
    }

    private func log(
        contentType: String = "application/x-www-form-urlencoded; charset=utf-8",
        body: [String: Any] = [:],
        bodyText: String? = nil
    ) -> ApiLog {
        ApiLog(
            responseCode: "200", method: "POST", url: "https://example.com/outlet",
            responseTime: "0.5", size: "0", date: Date(),
            responseHeader: [:], responseBody: "{}",
            requestHeader: ["Content-Type": contentType],
            requestBody: body, requestBodyText: bodyText
        )
    }

    /// The single-quoted shell words following `flag`, unquoted.
    private func arguments(after flag: String, in curl: String) -> [String] {
        curl.components(separatedBy: "  \(flag) ").dropFirst().map { chunk in
            var word = chunk
            if let end = word.range(of: "' \\\n") ?? word.range(of: "'", options: .backwards) {
                word = String(word[..<end.lowerBound]) + "'"
            }
            return String(word.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
        }
    }

    func testPayloadReallyEscapesSlashes() {
        XCTAssertTrue(payload.contains("\\/"), "precondition: the logged JSON carries \\/ escapes")
        XCTAssertTrue(photo.contains("+") && photo.contains("/"))
    }

    func testFormFieldsAreURLEncodedByCurl() {
        let curl = ApiLogExporter.curl(for: log(body: ["request": payload]))

        XCTAssertFalse(curl.contains("--data '"), "plain --data sends + unencoded, which the server reads as a space")
        XCTAssertTrue(curl.contains("--data-urlencode 'request="))
    }

    func testFormFieldValueIsTheSameJSONWithCopyableBase64() throws {
        let curl = ApiLogExporter.curl(for: log(body: ["request": payload]))
        let field = try XCTUnwrap(arguments(after: "--data-urlencode", in: curl).first)
        let value = String(field.dropFirst("request=".count))

        XCTAssertFalse(value.contains("\\/"))
        XCTAssertTrue(value.contains(photo), "base64 should appear exactly as encoded, ready to copy")

        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: String])
        let logged = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: String])
        XCTAssertEqual(sent, logged, "unescaping must not change the JSON value")
    }

    func testApostrophesSurviveShellQuoting() throws {
        let curl = ApiLogExporter.curl(for: log(body: ["request": payload]))

        XCTAssertFalse(curl.contains("Menteng\\'s"), "\\' does not escape a quote inside single quotes")
        XCTAssertTrue(curl.contains("Menteng'\\''s"))
    }

    func testJSONDictionaryBodyIsSentAsJSON() throws {
        let curl = ApiLogExporter.curl(for: log(contentType: "application/json", body: ["photo": photo, "qty": 2]))
        let body = try XCTUnwrap(arguments(after: "--data-binary", in: curl).first)

        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(sent["photo"] as? String, photo)
        XCTAssertEqual(sent["qty"] as? Int, 2)
        XCTAssertFalse(body.contains("\\/"))
    }

    func testRawBodyTextIsSentVerbatimApartFromSlashEscapes() throws {
        let form = "a=1&b=x%2By"
        let curl = ApiLogExporter.curl(for: log(bodyText: form))
        XCTAssertEqual(arguments(after: "--data-binary", in: curl), [form])
    }

    func testUnescapingLeavesEscapedBackslashesAlone() throws {
        let json = #"{"p":"a\/b","q":"c\\\/d","r":"e\\/f"}"#
        let unescaped = ApiLogExporter.unescapingSlashes(json)

        XCTAssertEqual(unescaped, #"{"p":"a/b","q":"c\\/d","r":"e\\/f"}"#)
        let before = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
        let after = try JSONSerialization.jsonObject(with: Data(unescaped.utf8)) as? [String: String]
        XCTAssertEqual(before, after)
    }

    func testUnescapingIgnoresNonJSON() {
        XCTAssertEqual(ApiLogExporter.unescapingSlashes(#"path\/to"#), #"path\/to"#)
    }

    func testRawLogNoLongerEscapesSlashes() {
        let raw = ApiLogExporter.rawLog(for: log(body: ["request": payload]))
        XCTAssertFalse(raw.contains("\\/"))
        XCTAssertTrue(raw.contains(photo))
    }
}
