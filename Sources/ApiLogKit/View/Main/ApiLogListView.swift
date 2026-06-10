//
//  ApiLogListView.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import SwiftUI

public struct ApiLogListView: View {
    @StateObject private var viewModel: ApiLogListViewModel
    @State private var shareItem: ShareItem?
    @State private var showClearConfirmation = false
    @State private var showDevOptions = false

    /// Optional close handler, used when the screen is presented modally.
    private let onClose: (() -> Void)?

    public init(logs: [ApiLog], onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: ApiLogListViewModel(logs: logs))
        self.onClose = onClose
    }

    public var body: some View {
        NavigationView {
            list
                .navigationTitle(viewModel.logType == .api ? "API Logs" : "AppsFlyer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        // `if` lives inside the item's ViewBuilder; branching at the
                        // toolbar-content level (`buildOptional`) is iOS 16+.
                        if let onClose {
                            Button("Close", action: onClose)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        menu
                    }
                }
                .searchable(text: $viewModel.searchText, prompt: "Search URL")
                .onChange(of: viewModel.searchText) { _ in viewModel.reload() }
                .background(devOptionsLink)
        }
        .navigationViewStyle(.stack)
        .sheet(item: $shareItem) { item in
            ShareSheet(text: item.text)
        }
        .confirmationDialog(
            "Are you sure you want to clear the logs?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { viewModel.clear() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(viewModel.items) { item in
                ZStack {
                    ApiLogRowView(log: item.log, logType: viewModel.logType)
                    NavigationLink {
                        ApiLogDetailView(log: item.log, logType: viewModel.logType)
                    } label: { EmptyView() }
                    .opacity(0)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Menu

    private var menu: some View {
        Menu {
            Button {
                viewModel.switchTo(.api)
            } label: {
                Label("API Logs", systemImage: viewModel.logType == .api ? "checkmark" : "list.bullet")
            }

            if viewModel.isAppsFlyerEnabled {
                Button {
                    viewModel.switchTo(.appsFlyer)
                } label: {
                    Label(
                        "AppsFlyer",
                        systemImage: viewModel.logType == .appsFlyer ? "checkmark" : "chart.line.uptrend.xyaxis"
                    )
                }
            }

            Button {
                shareItem = ShareItem(text: viewModel.exportText())
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            if viewModel.isDevOptionsEnabled {
                Button {
                    showDevOptions = true
                } label: {
                    Label("Developer Options", systemImage: "gear")
                }
            }

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Developer Options navigation

    private var devOptionsLink: some View {
        NavigationLink(isActive: $showDevOptions) {
            if let provider = ApiLogKitConfig.developerOptionsProvider {
                provider({ showDevOptions = false })
                    .navigationBarHidden(true)
            }
        } label: {
            EmptyView()
        }
    }
}

#if DEBUG
#Preview {
    ApiLogListView(logs: ApiLog.previewSamples)
}
#endif
