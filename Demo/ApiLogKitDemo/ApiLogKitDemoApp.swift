//
//  ApiLogKitDemoApp.swift
//  ApiLogKitDemo
//

import ApiLogKit
import SwiftUI

@main
struct ApiLogKitDemoApp: App {

    init() {
        // Everything a host app would do at launch, in the order the README
        // prescribes: configure first, then switch things on.
        ApiLogger.shared.isEnabled = true

        // Analytics tab.
        ApiLogger.shared.enableEventTrackerLog(true)

        // 3rd-party capture. No `ignoredHosts` here because the demo *wants* its
        // own traffic intercepted — a real app would exclude its API.
        ApiLogger.shared.enableThirdPartyTracker(true)

        // Persistence is opt-in; the demo turns it on so relaunching shows the
        // previous session's logs.
        ApiLogKitConfig.persistence.maxEntries = 200
        ApiLogger.shared.enablePersistence(true)

        // Shake the simulator (⌃⌘Z) to open the inspector from anywhere.
        ApiLogger.shared.enableShakeToOpen()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
