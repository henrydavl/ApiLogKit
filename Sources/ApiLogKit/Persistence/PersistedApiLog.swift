//
//  PersistedApiLog.swift
//  ApiLogKit
//
//  On-disk representation of an `ApiLog`.
//
//  `ApiLog` can't be `Codable` directly: three of its fields are `[String: Any]`,
//  which has no `Codable` conformance. Rather than change that public shape, this
//  DTO stores those dictionaries as JSON strings and rebuilds them on load — so
//  nested request bodies survive the round trip and keep rendering in the JSON
//  tree viewer.
//

import Foundation

struct PersistedApiLog: Codable {
    var responseCode: String
    var method: String
    var url: String
    var responseTime: String
    var size: String
    var date: Date
    var responseHeader: String
    var responseBody: String
    var requestHeader: String
    var requestBody: String
    var requestBodyText: String?

    // MARK: - Conversion

    /// Bodies are truncated to `maxBodyBytes`; headers are small and kept whole.
    init(_ log: ApiLog, maxBodyBytes: Int) {
        self.responseCode = log.responseCode
        self.method = log.method
        self.url = log.url
        self.responseTime = log.responseTime
        self.size = log.size
        self.date = log.date
        self.responseHeader = Self.encode(log.responseHeader)
        self.responseBody = Self.truncate(log.responseBody, toBytes: maxBodyBytes)
        self.requestHeader = Self.encode(log.requestHeader)
        self.requestBody = Self.encode(log.requestBody)
        self.requestBodyText = log.requestBodyText.map { Self.truncate($0, toBytes: maxBodyBytes) }
    }

    /// Rebuilds a log entry. Restored entries get a fresh `id` — they're new to
    /// this session — and are always `.finished`, since anything still in flight
    /// when the app died is dropped before writing.
    func toApiLog() -> ApiLog {
        ApiLog(
            responseCode: responseCode,
            method: method,
            url: url,
            responseTime: responseTime,
            size: size,
            date: date,
            responseHeader: Self.decode(responseHeader),
            responseBody: responseBody,
            requestHeader: Self.decode(requestHeader),
            requestBody: Self.decode(requestBody),
            requestBodyText: requestBodyText
        )
    }

    // MARK: - Dictionary coding

    /// Serialises a dictionary to a JSON string.
    ///
    /// Header dictionaries occasionally hold non-JSON values (`NSDate`, custom
    /// types) that would make `JSONSerialization` throw, so anything unencodable
    /// is coerced to its string description first rather than lost.
    static func encode(_ dictionary: [String: Any]) -> String {
        guard !dictionary.isEmpty else { return "{}" }

        let source = JSONSerialization.isValidJSONObject(dictionary)
            ? dictionary
            : dictionary.mapValues { String(describing: $0) }

        guard let data = try? JSONSerialization.data(withJSONObject: source) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ string: String) -> [String: Any] {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }

    // MARK: - Truncation

    /// Cuts a string to a byte budget, marking it so a clipped body isn't
    /// mistaken for the server's actual response.
    static func truncate(_ string: String, toBytes limit: Int) -> String {
        let utf8 = Data(string.utf8)
        guard utf8.count > limit, limit > 0 else { return string }

        // Slicing mid-character yields U+FFFD; drop any trailing one so the
        // marker reads cleanly.
        var clipped = String(decoding: utf8.prefix(limit), as: UTF8.self)
        while clipped.last == "\u{FFFD}" { clipped.removeLast() }
        return clipped + "\n\n… truncated by ApiLogKit persistence"
    }
}

/// Everything written in one file, versioned so a future format change can be
/// detected and discarded rather than mis-parsed.
struct PersistedLogArchive: Codable {
    static let currentVersion = 1

    var version: Int = PersistedLogArchive.currentVersion
    var api: [PersistedApiLog] = []
    var eventTracker: [PersistedApiLog] = []
    var thirdParty: [PersistedApiLog] = []
}
