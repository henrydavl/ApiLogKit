//
//  ApiLogExporter.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import Foundation

enum ApiLogExporter {

    /// Human-readable dump of a single log entry.
    static func rawLog(for log: ApiLog) -> String {
        var output = "\(log.url)\n\n"
        output += "---------- Request Header\n"
        for (key, value) in log.requestHeader {
            output += "\(key): \(String(describing: value).jsonize())\n\n"
        }

        output += "---------- Request Body\n"
        if let bodyText = log.requestBodyText {
            output += "\(bodyText.jsonize())\n"
        } else {
            for (_, value) in log.requestBody {
                output += "\(String(describing: value).jsonize())\n"
            }
        }

        output += "\n---------- Response Header\n"
        for (key, value) in log.responseHeader {
            output += "\(key): \(String(describing: value).jsonize())\n\n"
        }

        output += "---------- Response Body\n"
        output += "\(log.responseBody)\n\n"
        output += "======================>>>>>>>\n\n\n"
        return output
    }

    /// `curl` command reproducing the request.
    static func curl(for log: ApiLog) -> String {
        var curl = "curl -X \(log.method) \\\n"
        curl += "  \(shellQuoted(log.url)) \\\n"

        for (key, value) in log.requestHeader {
            curl += "  -H \(shellQuoted("\(key): \(value)")) \\\n"
        }

        if let bodyText = log.requestBodyText, !bodyText.isEmpty {
            // Raw payload — already encoded for the wire, so sent verbatim.
            curl += "  --data-binary \(shellQuoted(unescapingSlashes(bodyText))) \\\n"
        } else if !log.requestBody.isEmpty {
            if isJSON(contentType(of: log)), let json = jsonText(log.requestBody) {
                curl += "  --data-binary \(shellQuoted(json)) \\\n"
            } else {
                // `--data-urlencode` because `--data` sends the value as-is: a
                // base64 `+` then reaches the server as a space, and `&` or `=`
                // split the field.
                for (key, value) in log.requestBody {
                    let formValue = unescapingSlashes(String(describing: value))
                    curl += "  --data-urlencode \(shellQuoted("\(key)=\(formValue)")) \\\n"
                }
            }
        }

        if curl.hasSuffix(" \\\n") {
            curl = String(curl.dropLast(3))
        }
        return curl
    }

    // MARK: - Helpers

    /// Single-quotes `text` for a POSIX shell. Inside single quotes nothing is
    /// special except `'` itself, which has to close the quote, add an escaped
    /// quote and reopen: `'\''`.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Rewrites `\/` as `/` in a string that holds JSON.
    ///
    /// `\/` is JSON's optional escape for `/`, and `JSONSerialization` writes it
    /// by default, so a base64 field reads `\/9j\/4AAQ…`. It's the same JSON
    /// value, but the backslashes turn the base64 invalid for anyone who copies
    /// it out of the export. Strings that aren't JSON are returned unchanged, and
    /// an escaped backslash (`\\`) before a `/` is left alone.
    static func unescapingSlashes(_ text: String) -> String {
        guard text.contains("\\/"),
              let first = text.first(where: { !$0.isWhitespace }), first == "{" || first == "[",
              (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
        else { return text }

        var result = String.UnicodeScalarView()
        var pendingBackslash = false
        for scalar in text.unicodeScalars {
            if pendingBackslash {
                if scalar != "/" { result.append("\\") }
                result.append(scalar)
                pendingBackslash = false
            } else if scalar == "\\" {
                pendingBackslash = true
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }

    private static func contentType(of log: ApiLog) -> String? {
        log.requestHeader.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }
            .map { String(describing: $0.value) }
    }

    private static func isJSON(_ contentType: String?) -> Bool {
        contentType?.lowercased().contains("json") ?? false
    }

    /// Compact JSON for a dictionary body, or nil if it holds values
    /// `JSONSerialization` can't encode.
    private static func jsonText(_ dictionary: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(
                withJSONObject: dictionary,
                options: [.sortedKeys, .withoutEscapingSlashes]
              )
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
