//
//  EmbeddedJSONTests.swift
//  ApiLogKitTests
//
//  A body logged as `["payload": jsonString]` should unfold in the tree viewer,
//  while copy and export keep the value exactly as it was sent.
//

import XCTest
@testable import ApiLogKit

final class EmbeddedJSONTests: XCTestCase {

    private let payload = #"{"id":"8e59","latitude":-6.21,"image":"\/9j\/4AAQ"}"#

    func testJSONStringValueUnfoldsIntoATree() throws {
        let node = try XCTUnwrap(JSONNode.from(dictionary: ["payload": payload]))
        guard case .object(let pairs) = node,
              case .embedded(let raw, let parsed) = pairs[0].value
        else { return XCTFail("expected an embedded JSON value, got \(node)") }

        XCTAssertEqual(raw, payload)
        XCTAssertEqual(parsed.childCount, 3)
    }

    func testEmbeddedValueSerializesBackAsTheOriginalString() throws {
        let node = try XCTUnwrap(JSONNode.from(dictionary: ["payload": payload]))
        let reparsed = try JSONSerialization.jsonObject(with: Data(node.prettyPrinted().utf8)) as? [String: String]
        XCTAssertEqual(reparsed?["payload"], payload, "copy must not reshape the logged value")
    }

    func testCopyingTheEmbeddedLeafGivesTheOriginalString() throws {
        let node = try XCTUnwrap(JSONNode.from(dictionary: ["payload": payload]))
        guard case .object(let pairs) = node else { return XCTFail() }
        XCTAssertEqual(pairs[0].value.rawValue, payload)
    }

    func testPlainStringsStayStrings() throws {
        let node = try XCTUnwrap(JSONNode.from(dictionary: [
            "image": "/9j/4AAQSkZJRgABAQAASABIAAD",
            "note": "[not json",
            "empty": "{}"
        ]))
        guard case .object(let pairs) = node else { return XCTFail() }
        for pair in pairs {
            guard case .string = pair.value else {
                return XCTFail("\(pair.key) should stay a plain string")
            }
        }
    }

    func testDetailCopyValueIsUnchangedByUnfolding() {
        let log = ApiLog(
            responseCode: "200",
            method: "POST",
            url: "https://example.com/face/verification",
            responseTime: "0.42",
            size: "0",
            date: Date(),
            responseHeader: [:],
            responseBody: "{}",
            requestHeader: [:],
            requestBody: ["payload": payload]
        )
        let viewModel = ApiLogDetailViewModel(log: log, logType: .api)

        let copied = viewModel.copyValue(for: .requestBody)
        let reparsed = try? JSONSerialization.jsonObject(with: Data(copied.utf8)) as? [String: String]
        XCTAssertEqual(reparsed?["payload"], payload)
    }

    /// `JSONNodeView` may only contain itself inside a `ForEach`. A direct
    /// self-reference in its body type sends SwiftUI's static view count
    /// (`_viewListCount`) into endless recursion, which crashed iOS 17 with a
    /// main-thread stack overflow the moment a tree appeared. The iOS 26
    /// simulator never runs that walk, so rendering can't catch it — the type
    /// itself is checked instead.
    func testNodeViewOnlyNestsItselfThroughForEach() {
        var type = String(reflecting: JSONNodeView.Body.self)
        XCTAssertTrue(type.contains("ForEach<"), "expected children to come from a ForEach")

        // Drop every `ForEach<…>` (with its balanced generic arguments).
        while let start = type.range(of: "ForEach<") {
            var depth = 0
            var end = start.upperBound
            for index in type[start.lowerBound...].indices {
                if type[index] == "<" { depth += 1 }
                if type[index] == ">" {
                    depth -= 1
                    if depth == 0 { end = type.index(after: index); break }
                }
            }
            type.removeSubrange(start.lowerBound..<end)
        }

        XCTAssertFalse(type.contains("JSONNodeView"),
                       "JSONNodeView's body refers to JSONNodeView outside a ForEach")
    }

    func testEmbeddedContainersAreExpandedByDefault() throws {
        let node = try XCTUnwrap(JSONNode.from(dictionary: ["payload": payload]))
        let model = JSONTreeModel(root: node)
        XCTAssertTrue(model.isExpanded("$.payload"))
    }
}
