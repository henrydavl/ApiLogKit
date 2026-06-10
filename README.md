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

Requires **iOS 15+**. No third-party dependencies.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/<you>/ApiLogKit.git", from: "0.1.0"),
]
```

Or in Xcode: *File ▸ Add Package Dependencies…* and paste the repo URL.

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

From SwiftUI:

```swift
ApiLogListView(logs: ApiLogger.shared.getLogs())
```

From UIKit (e.g. a shake gesture or debug menu):

```swift
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
