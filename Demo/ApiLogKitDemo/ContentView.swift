//
//  ContentView.swift
//  ApiLogKitDemo
//
//  A control panel for generating traffic, so every feature of the inspector has
//  something to show.
//

import ApiLogKit
import SwiftUI

struct ContentView: View {
    @State private var showInspector = false
    @State private var lastAction: String?

    var body: some View {
        NavigationView {
            List {
                inspectorSection
                inFlightSection
                trafficSection
                otherTabsSection
                persistenceSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("ApiLogKit Demo")
        }
        .navigationViewStyle(.stack)
        .fullScreenCover(isPresented: $showInspector) {
            ApiLogListView(logs: ApiLogger.shared.getLogs()) {
                showInspector = false
            }
        }
    }

    // MARK: - Sections

    private var inspectorSection: some View {
        Section {
            Button {
                showInspector = true
            } label: {
                Label("Open Inspector", systemImage: "list.bullet.rectangle")
            }
        } header: {
            Text("Inspector")
        } footer: {
            Text("Or shake the device — ⌃⌘Z in the Simulator — from any screen.")
        }
    }

    private var inFlightSection: some View {
        Section {
            Button {
                DemoTraffic.fire(DemoTraffic.slow)
                note("Started a 12s request")
            } label: {
                Label("Fire slow request (12s)", systemImage: "clock.arrow.circlepath")
            }

            Button {
                DemoTraffic.fire(DemoTraffic.stuck)
                note("Started a request that never completes")
            } label: {
                Label("Fire hung request (never completes)", systemImage: "exclamationmark.triangle")
            }
        } header: {
            Text("In-flight")
        } footer: {
            Text("Fire one of these, then open the inspector: the row appears immediately, dimmed and marked Pending, and fills in when the response lands. Filter by Status ▸ Pending to isolate them.")
        }
    }

    private var trafficSection: some View {
        Section {
            Button {
                DemoTraffic.fireBurst()
                note("Fired \(DemoTraffic.quick.count) requests")
            } label: {
                Label("Fire burst (all scenarios)", systemImage: "bolt.fill")
            }

            ForEach(DemoTraffic.quick) { scenario in
                Button {
                    DemoTraffic.fire(scenario)
                    note(scenario.label)
                } label: {
                    HStack {
                        Text(scenario.label)
                        Spacer()
                        Text(scenario.method)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("API traffic")
        } footer: {
            Text("Spans three hosts, four methods and the 2xx/3xx/4xx/5xx classes, so the Status, Method and Host filters all have something to offer.")
        }
    }

    private var otherTabsSection: some View {
        Section {
            Button {
                DemoTraffic.fireTrackerEvent()
                note("Logged an analytics event")
            } label: {
                Label("Log EventTracker event", systemImage: "chart.line.uptrend.xyaxis")
            }

            Button {
                DemoTraffic.fireRealRequest()
                note("Sent a real request to api.github.com")
            } label: {
                Label("Fire real network request", systemImage: "network")
            }
        } header: {
            Text("Other tabs")
        } footer: {
            Text("The real request goes through URLSession, so the 3rd-party interceptor captures it into the 3rd Party tab — including its own pending row. It records a failure if the machine is offline, which is equally worth seeing.")
        }
    }

    private var persistenceSection: some View {
        Section {
            Button(role: .destructive) {
                ApiLogger.shared.clearLogs()
                ApiLogger.shared.clearPersistedLogs()
                note("Cleared logs and archive")
            } label: {
                Label("Clear logs and archive", systemImage: "trash")
            }
        } header: {
            Text("Persistence")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Persistence is on. Fire some traffic, kill the app, relaunch — the logs are still there, restored ahead of the new session's.")
                if let lastAction {
                    Text("Last action: \(lastAction)")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }

    private func note(_ text: String) {
        lastAction = text
    }
}

#Preview {
    ContentView()
}
