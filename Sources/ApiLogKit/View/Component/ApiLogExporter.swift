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
        for (_, value) in log.requestBody {
            output += "\(String(describing: value).jsonize())\n"
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
        curl += "  '\(log.url)' \\\n"

        for (key, value) in log.requestHeader {
            let headerValue = String(describing: value).replacingOccurrences(of: "'", with: "\\'")
            curl += "  -H '\(key): \(headerValue)' \\\n"
        }

        if !log.requestBody.isEmpty {
            for (key, value) in log.requestBody {
                let formValue = String(describing: value).replacingOccurrences(of: "'", with: "\\'")
                curl += "  --data '\(key)=\(formValue)' \\\n"
            }
        }

        if curl.hasSuffix(" \\\n") {
            curl = String(curl.dropLast(3))
        }
        return curl
    }
}
