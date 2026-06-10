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
