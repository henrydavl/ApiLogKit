//
//  ApiLogPreviewData.swift
//  Core
//
//  Sample `ApiLog` data used only by SwiftUI previews.
//

#if DEBUG
import Foundation

extension ApiLog {
    /// A single successful request used for detail / row previews.
    static var previewSample: ApiLog {
        ApiLog(
            responseCode: "200",
            method: "POST",
            url: "https://api.bri.co.id/v1/merchant/profile",
            responseTime: "0.42",
            size: "2048",
            date: Date(),
            responseHeader: [
                "Content-Type": "application/json",
                "Server": "nginx"
            ],
            responseBody: #"""
            {"status":"success","data":{"merchant":{"id":12345,"name":"Toko Maju Jaya","active":true},"balance":1500000,"tags":["gold","verified","priority"],"items":[{"sku":"A1","qty":2},{"sku":"B2","qty":1}],"signature":"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"},"meta":null}
            """#,
            requestHeader: [
                "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
                "Accept": "application/json"
            ],
            requestBody: [
                "username": "merchant01",
                "deviceId": "A1B2C3D4"
            ]
        )
    }

    /// A mixed list (success / not-found / server error) for list previews.
    static var previewSamples: [ApiLog] {
        [
            previewSample,
            ApiLog(
                responseCode: "404",
                method: "GET",
                url: "https://api.bri.co.id/v1/merchant/missing",
                responseTime: "0.18",
                size: "128",
                date: Date().addingTimeInterval(-60),
                responseHeader: ["Content-Type": "application/json"],
                responseBody: #"{"status":"error","message":"Not found"}"#,
                requestHeader: ["Accept": "application/json"],
                requestBody: [:]
            ),
            ApiLog(
                responseCode: "500",
                method: "POST",
                url: "https://api.bri.co.id/v1/payment/charge",
                responseTime: "1.27",
                size: "256",
                date: Date().addingTimeInterval(-120),
                responseHeader: ["Content-Type": "application/json"],
                responseBody: #"{"status":"error","message":"Internal server error"}"#,
                requestHeader: ["Authorization": "Bearer xxx"],
                requestBody: ["amount": 50000]
            )
        ]
    }
}
#endif
