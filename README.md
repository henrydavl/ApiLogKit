# ApiLogKit

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

// Track analytics events in a separate "AppsFlyer" tab.
ApiLogger.shared.enableAppsFlyerLog(true)
ApiLogger.shared.addAppsFlyerLog(
    ApiLog(eventName: "purchase_completed", requestBody: params, responseBody: response)
)
```

## License

MIT
