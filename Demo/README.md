# ApiLogKitDemo

A small host app for exercising ApiLogKit against the local package — useful for
seeing a change running, and for reproducing a bug report outside a real app.

## Running

The Xcode project is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and isn't checked in:

```bash
cd Demo && xcodegen generate && open ApiLogKitDemo.xcodeproj
```

Or straight to a simulator without opening Xcode:

```bash
cd Demo && xcodegen generate && xcodebuild -project ApiLogKitDemo.xcodeproj -scheme ApiLogKitDemo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build build && xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/ApiLogKitDemo.app && xcrun simctl launch booted com.apilogkit.demo
```

The app depends on the package by relative path (`path: ..`), so it always builds
whatever is in the working tree — no version bump or push needed.

## What it demonstrates

| Control | Shows |
| --- | --- |
| **Fire burst** | Traffic across 3 hosts, 4 methods and the 2xx/3xx/4xx/5xx classes — enough to make the Status, Method and Host filters meaningful |
| **Fire slow request (12s)** | A row that appears immediately as `Pending`, then fills in *in place* when the response lands |
| **Fire hung request** | A request that never completes, so the pending treatment stays on screen |
| **Log EventTracker event** | The EventTracker tab |
| **Fire real network request** | A genuine `URLSession` call, captured by the URLProtocol interceptor into the 3rd Party tab |
| **Relaunch the app** | Persistence — logs come back, minus anything that was still in flight |

Traffic is synthetic (`beginLog` / `completeLog` with a timer) rather than real
networking, so the pending → completed transition is deterministic and works
offline. The one exception is the real-request button, which is there to exercise
the interceptor.

Shake — `⌃⌘Z` in the Simulator — opens the inspector from anywhere.
