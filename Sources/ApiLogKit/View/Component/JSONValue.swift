//
//  JSONValue.swift
//  Core
//
//  Lightweight JSON tree model used by the interactive JSON viewer in the
//  ApiLog detail screen. Built on top of `JSONSerialization` for robustness.
//

import Foundation

indirect enum JSONNode {
    case object([(key: String, value: JSONNode)])
    case array([JSONNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
    /// A string value that itself holds a JSON object/array — e.g. a request
    /// body passed as `["payload": jsonString]`. Display-only: the viewer
    /// unfolds `parsed`, while copy and export keep `raw` exactly as logged.
    case embedded(raw: String, parsed: JSONNode)

    /// A container has collapsible children.
    var isContainer: Bool {
        switch self {
        case .object, .array, .embedded: return true
        default: return false
        }
    }

    /// Number of direct children (0 for leaves).
    var childCount: Int {
        switch self {
        case .object(let pairs): return pairs.count
        case .array(let items): return items.count
        case .embedded(_, let parsed): return parsed.childCount
        default: return 0
        }
    }
}

// MARK: - Building

extension JSONNode {

    /// Parses a JSON string. Returns `nil` if it isn't a JSON object/array
    /// (so callers can fall back to plain text for HTML, fragments, etc.).
    static func parse(_ string: String) -> JSONNode? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return build(from: object)
    }

    /// Builds a node from a `[String: Any]` dictionary (e.g. request body).
    static func from(dictionary: [String: Any]) -> JSONNode? {
        guard !dictionary.isEmpty else { return nil }
        return build(from: dictionary)
    }

    private static func build(from any: Any) -> JSONNode {
        switch any {
        case let dict as [String: Any]:
            // JSONSerialization / Swift dictionaries are unordered; sort keys for
            // a stable, easy-to-scan display.
            let pairs = dict.keys.sorted().map { (key: $0, value: build(from: dict[$0]!)) }
            return .object(pairs)
        case let array as [Any]:
            return .array(array.map { build(from: $0) })
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.stringValue)
        case let string as String:
            if let parsed = parseEmbedded(string) {
                return .embedded(raw: string, parsed: parsed)
            }
            return .string(string)
        case is NSNull:
            return .null
        default:
            return .string(String(describing: any))
        }
    }

    /// Parses a string value that holds a JSON object/array. The leading-brace
    /// check keeps this cheap for the common case (plain text, base64, ids).
    private static func parseEmbedded(_ string: String) -> JSONNode? {
        guard let first = string.first(where: { !$0.isWhitespace }),
              first == "{" || first == "["
        else { return nil }
        guard let node = parse(string), node.childCount > 0 else { return nil }
        return node
    }
}

// MARK: - Serializing (for copy)

extension JSONNode {

    /// Pretty-printed JSON text for this node (used when copying a subtree).
    func prettyPrinted(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let childPad = String(repeating: "  ", count: indent + 1)

        switch self {
        case .object(let pairs):
            guard !pairs.isEmpty else { return "{}" }
            let body = pairs.map { pair in
                "\(childPad)\(Self.encode(string: pair.key)): \(pair.value.prettyPrinted(indent: indent + 1))"
            }.joined(separator: ",\n")
            return "{\n\(body)\n\(pad)}"
        case .array(let items):
            guard !items.isEmpty else { return "[]" }
            let body = items.map { "\(childPad)\($0.prettyPrinted(indent: indent + 1))" }
                .joined(separator: ",\n")
            return "[\n\(body)\n\(pad)]"
        case .string(let value):
            return Self.encode(string: value)
        case .number(let value):
            return value
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .embedded(let raw, _):
            return Self.encode(string: raw)
        }
    }

    /// Plain value used when copying a single leaf (no surrounding quotes).
    var rawValue: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value):   return value ? "true" : "false"
        case .null:              return "null"
        case .embedded(let raw, _): return raw
        case .object, .array:    return prettyPrinted()
        }
    }

    private static func encode(string: String) -> String {
        var result = "\""
        for character in string.unicodeScalars {
            switch character {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:   result.unicodeScalars.append(character)
            }
        }
        result += "\""
        return result
    }
}
