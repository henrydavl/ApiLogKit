//
//  DemoTraffic.swift
//  ApiLogKitDemo
//
//  Synthetic traffic for the demo. Deliberately not real networking: the point
//  is a deterministic, offline way to watch a request sit in the list as
//  `Pending` and then fill in, which a live endpoint can't guarantee.
//
//  The scenarios span several hosts, methods and status classes so the filter
//  bar has something to filter.
//

import ApiLogKit
import Foundation

enum DemoTraffic {

    struct Scenario: Identifiable {
        let id = UUID()
        let label: String
        let method: String
        let url: String
        let status: String
        /// How long the request "takes" before its response lands.
        let delay: TimeInterval
        var requestBody: [String: Any] = [:]
        var responseBody: String = "{}"
    }

    // MARK: - Scenarios

    static let quick: [Scenario] = [
        Scenario(
            label: "GET products · 200",
            method: "GET",
            url: "https://api.shop.example.com/v1/products?page=1",
            status: "200",
            delay: 0.4,
            responseBody: #"""
            {"page":1,"total":3,"items":[{"sku":"A1","name":"Kopi Gayo","price":85000,"tags":["coffee","arabica"]},{"sku":"B2","name":"Teh Melati","price":42000,"tags":["tea"]},{"sku":"C3","name":"Gula Aren","price":25000,"tags":["sweetener"]}]}
            """#
        ),
        Scenario(
            label: "POST cart · 201",
            method: "POST",
            url: "https://api.shop.example.com/v1/cart",
            status: "201",
            delay: 0.9,
            requestBody: ["sku": "A1", "qty": 2, "note": "gift wrap"],
            responseBody: #"{"cartId":"c_8812","lines":[{"sku":"A1","qty":2,"subtotal":170000}],"total":170000}"#
        ),
        Scenario(
            label: "GET banner · 304",
            method: "GET",
            url: "https://cdn.assets.example.com/config/banner.json",
            status: "304",
            delay: 0.3,
            responseBody: ""
        ),
        Scenario(
            label: "GET user · 404",
            method: "GET",
            url: "https://api.shop.example.com/v1/users/99999",
            status: "404",
            delay: 0.5,
            responseBody: #"{"status":"error","code":"USER_NOT_FOUND","message":"No such user"}"#
        ),
        Scenario(
            label: "POST checkout · 500",
            method: "POST",
            url: "https://api.payments.example.com/v1/checkout",
            status: "500",
            delay: 1.2,
            requestBody: ["cartId": "c_8812", "method": "va_bri", "amount": 170000],
            responseBody: #"{"status":"error","code":"UPSTREAM_TIMEOUT","message":"Payment gateway did not respond"}"#
        ),
        Scenario(
            label: "DELETE cart item · 204",
            method: "DELETE",
            url: "https://api.shop.example.com/v1/cart/items/3",
            status: "204",
            delay: 0.6,
            responseBody: ""
        )
    ]

    /// Long enough to open the inspector and watch it sitting there in flight.
    static let slow = Scenario(
        label: "Slow inquiry · 12s",
        method: "POST",
        url: "https://api.payments.example.com/v1/inquiry",
        status: "200",
        delay: 12,
        requestBody: ["accountNo": "0021 3344 5566", "amount": 250_000],
        responseBody: #"{"status":"success","accountName":"HENRY D LIE","fee":2500}"#
    )

    /// Never completed on purpose — this is what a hung request looks like.
    static let stuck = Scenario(
        label: "Hung request",
        method: "GET",
        url: "https://api.payments.example.com/v1/status/pending-forever",
        status: "200",
        delay: .infinity,
        responseBody: ""
    )

    // MARK: - Firing

    private static let headers: [String: Any] = [
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Authorization": "Bearer demo.eyJzdWIiOiJkZW1vIn0.signature",
        "X-Request-Id": "req_demo"
    ]

    /// Records the request as in-flight, then completes it after `delay` —
    /// the same `beginLog` / `completeLog` pairing a real networking layer uses.
    static func fire(_ scenario: Scenario) {
        let token = ApiLogger.shared.beginLog(
            method: scenario.method,
            url: scenario.url,
            requestHeader: headers,
            requestBody: scenario.requestBody
        )

        guard scenario.delay.isFinite else { return }

        let start = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + scenario.delay) {
            ApiLogger.shared.completeLog(
                token,
                with: ApiLog(
                    responseCode: scenario.status,
                    method: scenario.method,
                    url: scenario.url,
                    responseTime: String(format: "%.2f", Date().timeIntervalSince(start)),
                    size: "\(scenario.responseBody.utf8.count)",
                    date: Date(),
                    responseHeader: [
                        "Content-Type": "application/json",
                        "Server": "demo-gateway",
                        "X-Trace-Id": "trace_\(Int.random(in: 1000...9999))"
                    ],
                    responseBody: scenario.responseBody,
                    requestHeader: headers,
                    requestBody: scenario.requestBody
                )
            )
        }
    }

    /// Fires every quick scenario, staggered so they don't all land at once.
    static func fireBurst() {
        for (index, scenario) in quick.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.25) {
                fire(scenario)
            }
        }
    }

    /// A real request, to exercise the URLProtocol interceptor and the 3rd Party
    /// tab. Fails harmlessly (and informatively) when the machine is offline.
    static func fireRealRequest() {
        let url = URL(string: "https://api.github.com/repos/henrydavl/ApiLogKit")!
        URLSession.shared.dataTask(with: url).resume()
    }

    /// An analytics-style entry for the EventTracker tab.
    static func fireTrackerEvent() {
        ApiLogger.shared.addEventTrackerLog(
            ApiLog(
                eventName: "purchase_completed",
                requestBody: [
                    "revenue": 170000,
                    "currency": "IDR",
                    "items": ["A1", "B2"]
                ],
                responseBody: #"{"received":true}"#
            )
        )
    }
}
