//
//  InternalHelpers.swift
//  ApiLogKit
//
//  Vendored utilities (kept `internal` so they never collide with the host
//  app's own extensions of the same name).
//

import Foundation

extension String {

    /// Pretty-prints the string if it contains JSON; otherwise returns self.
    func jsonize() -> String {
        if let jsonData = data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData, options: .mutableContainers),
           let prettyPrintedData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyPrintedString = String(data: prettyPrintedData, encoding: .utf8) {
            return prettyPrintedString
        }
        return self
    }

    /// Truncates the string to at most `maxLength` characters.
    func maxCharacter(_ maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(prefix(maxLength))
    }
}

extension Data {

    /// Pretty-prints the data if it contains JSON; otherwise decodes as UTF-8.
    func jsonize() -> String {
        if let json = try? JSONSerialization.jsonObject(with: self, options: .mutableContainers),
           let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            return String(decoding: jsonData, as: UTF8.self)
        }
        return String(data: self, encoding: .utf8) ?? ""
    }
}

extension URLRequest {

    /// The complete request payload.
    ///
    /// By the time a `URLProtocol` sees a request the URL Loading System has
    /// usually moved the payload out of `httpBody` and into `httpBodyStream`, so
    /// reading `httpBody` alone yields `nil` for most real traffic.
    ///
    /// Draining the stream **consumes** it, so the caller must re-attach the
    /// returned data as `httpBody` on the request it forwards — otherwise the
    /// body is silently lost. Reads to completion rather than to a cap for that
    /// reason; `ApiLogURLProtocol` keeps oversized uploads out of here by
    /// declining to intercept them in the first place.
    func apilogkit_drainBody() -> Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 8_192
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

extension Date {

    /// Row-timestamp format used across the log screens
    /// (e.g. "Wednesday, 10 June 2026, 13:56:02").
    func apiLogFormatted() -> String {
        let formatter = DateFormatter()
        formatter.locale = ApiLogKitConfig.dateLocale
        formatter.dateFormat = "EEEE, dd MMMM yyyy, HH:mm:ss"
        return formatter.string(from: self)
    }
}
