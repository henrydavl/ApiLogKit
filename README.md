# ApiLogKit

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fhenrydavl%2FApiLogKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/henrydavl/ApiLogKit)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fhenrydavl%2FApiLogKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/henrydavl/ApiLogKit)

An in-app API log inspector for iOS, written in SwiftUI. Records HTTP request/response
logs (plus analytics events such as AppsFlyer) and presents them in a debug UI with:

- 📋 Log list with URL search, status-code badges, newest-first ordering
- 🌳 Interactive JSON viewer — collapsible objects/arrays with child counts,
  type-colored values, tap-to-expand long strings (base64-safe), expand/collapse all
- 📝 Tree ⇄ pretty-JSON text toggle per body section
- 📤 Export as raw log or ready-to-run cURL command
- 📎 Copy any value, subtree, or section with toast confirmation
- 🧭 Floating scroll-to-top/bottom buttons on long payloads
- 📳 Shake to open — one-line setup, works from any screen, no boilerplate
- 📦 3rd-party traffic tracker — capture `URLSession` calls from closed-source SDKs
  you have no call site for, in their own tab

Requires **iOS 15+**. No third-party dependencies.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/henrydavl/ApiLogKit.git", from: "0.2.0"),
]
```

Or in Xcode: *File ▸ Add Package Dependencies…* and paste:
`https://github.com/henrydavl/ApiLogKit.git`

## Usage

### 1. Record logs

```swift
import ApiLogKit

// Gate recording (e.g. dev builds only). Defaults to true.
ApiLogger.shared.isEnabled = isDevelopmentBuild

ApiLogger.shared.addLog(
    ApiLog(
        responseCode: "200",
        method: "POST",
        url: "https://api.example.com/v1/login",
        responseTime: "0.42",
        size: "2048",
        date: Date(),
        responseHeader: httpResponse.allHeaderFields as? [String: Any] ?? [:],
        responseBody: bodyString,
        requestHeader: requestHeaders,
        requestBody: requestParameters
    )
)
```

Using **Alamofire**? Keep a small convenience init in your app target:

```swift
import Alamofire
import ApiLogKit

extension ApiLog {
    init(response: AFDataResponse<Data?>, parameter: Parameters?, headers: [String: Any]) {
        self.init(
            responseCode: "\(response.response?.statusCode ?? 0)",
            method: response.request?.httpMethod ?? "-",
            url: response.request?.url?.absoluteString ?? "URL not found",
            responseTime: "\(response.metrics?.taskInterval.duration ?? 0)",
            size: "\(response.data?.count ?? 0)",
            date: Date(),
            responseHeader: (response.response?.allHeaderFields as? [String: Any]) ?? [:],
            responseBody: response.data.flatMap { String(data: $0, encoding: .utf8) } ?? "",
            requestHeader: headers,
            requestBody: parameter ?? [:]
        )
    }
}
```

### 2. Show the inspector

**Shake to open (recommended)** — call once at startup and the inspector appears
on any shake, from any screen, with no further setup:

```swift
// AppDelegate / SceneDelegate
ApiLogger.shared.isEnabled = isDevelopmentBuild
ApiLogger.shared.enableShakeToOpen()
```

**Manual presentation** — present it yourself from SwiftUI or UIKit whenever you like:

```swift
// SwiftUI
ApiLogListView(logs: ApiLogger.shared.getLogs())

// UIKit
let controller = ApiLogHostingController(logs: ApiLogger.shared.getLogs())
present(controller, animated: true)
```

### 3. Optional configuration

```swift
// Locale for row timestamps (defaults to .current).
ApiLogKitConfig.dateLocale = Locale(identifier: "id_ID")

// Plug your own Developer Options screen into the list's menu.
ApiLogKitConfig.developerOptionsProvider = { onDismiss in
    AnyView(MyDevOptionsView(onDismiss: onDismiss))
}

// Track analytics events in a separate "EventTracker" tab.
ApiLogger.shared.enableEventTrackerLog(true)
ApiLogger.shared.addEventTrackerLog(
    ApiLog(eventName: "purchase_completed", requestBody: params, responseBody: response)
)
```

## 3rd-party traffic tracker

`addLog` only reaches traffic you have a call site for. For a closed-source SDK you have
neither the request nor the response — so the tracker intercepts at the URL Loading System
level instead, with a `URLProtocol`, and files what it finds under a separate **3rd Party**
tab. Your own API keeps flowing through `addLog` into **API Logs** exactly as before.

```swift
// AppDelegate — as early as possible, and before any SDK initialises.
// Only sessions created *after* this call are intercepted.

// Your own API hosts. Skipped entirely, so they aren't duplicated into the
// 3rd-party tab and their networking is left completely untouched.
ApiLogKitConfig.thirdPartyTracker.ignoredHosts = ["api.myapp.com"]

ApiLogger.shared.enableThirdPartyTracker(isDevelopmentBuild)
```

Everything not excluded is captured — status code, timing, both sets of headers, and both
bodies, with the same JSON viewer and cURL export as the other tabs.

### Filtering

```swift
// Allowlist — when non-empty, only these hosts are captured.
ApiLogKitConfig.thirdPartyTracker.allowedHosts = ["appsflyer.com", "api2.branch.io"]

// Final say, if the host lists aren't enough.
ApiLogKitConfig.thirdPartyTracker.shouldCapture = { request in
    request.httpMethod != "OPTIONS"
}

// Retention. Unlike the manual tabs this one fills on its own.
ApiLogKitConfig.thirdPartyTracker.maxBodyBytes = 512 * 1024  // per body
ApiLogKitConfig.thirdPartyTracker.maxEntries = 500           // oldest dropped first
```

Host matching is suffix-based, so `example.com` also covers `api.example.com`.

### Limitations

Interception re-issues each request on an ApiLogKit-owned `URLSession`. That has real
consequences — worth reading before turning it on:

- **Certificate pinning breaks.** An SDK that pins via its own session delegate will fail
  its check while the tracker is on, because the request no longer runs on that session.
  Put such SDKs in `ignoredHosts`. This is inherent to the approach, not a bug.
- **Redirects are always followed.** An SDK that deliberately blocks redirects via its
  delegate no longer can.
- **Timing must be right.** Sessions built before `enableThirdPartyTracker(_:)` are never
  intercepted, and an SDK that assigns `configuration.protocolClasses` wholesale after
  creating its configuration drops the interceptor.
- **Not everything is `URLSession`.** Background sessions, `Network.framework`, gRPC, raw
  sockets and `WKWebView` traffic are all invisible to this.
- **Large uploads are skipped.** A request declaring more than 10 MB via `Content-Length`
  is left alone, since capturing a streamed body means buffering it.

Treat it as a dev-build tool — gate it the same way you gate `isEnabled`.

## License

MIT
