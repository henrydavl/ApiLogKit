//
//  ApiLogListView.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import SwiftUI
import UIKit

public struct ApiLogListView: View {
    @StateObject private var viewModel: ApiLogListViewModel
    @State private var shareItem: ShareItem?
    @State private var showClearConfirmation = false
    @State private var showDevOptions = false

    // Copy confirmation toast.
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    /// Drives the detail push. Held here rather than in the rows so that list
    /// churn from live logs can't tear the pushed screen down — see `detailLink`.
    @State private var selectedLog: ApiLog?

    /// Optional close handler, used when the screen is presented modally.
    private let onClose: (() -> Void)?

    public init(logs: [ApiLog], onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: ApiLogListViewModel(logs: logs))
        self.onClose = onClose
    }

    public var body: some View {
        NavigationView {
            list
                .navigationTitle(viewModel.title)
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
                        pauseButton
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        menu
                    }
                }
                .searchable(text: $viewModel.searchText, prompt: "Search URL")
                .background(detailLink)
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
        .overlay(alignment: .bottom) {
            if let toastMessage {
                toastBubble(toastMessage)
            }
        }
    }

    // MARK: - Copy + toast

    /// Writes the pasteboard directly rather than going through the share sheet,
    /// whose copy activity data-detects the leading request URL and pastes it
    /// alone into anything that prefers a URL.
    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        toastWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { toastMessage = "Copied to clipboard" }

        let item = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) { toastMessage = nil }
        }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    private func toastBubble(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(Color(.systemBackground))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.label).opacity(0.9))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        .padding(.bottom, 32)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - List

    private var list: some View {
        listContent
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if viewModel.isPaused {
                        pausedBanner
                    }
                    filterBar
                }
            }
    }

    @ViewBuilder
    private var listContent: some View {
        if viewModel.items.isEmpty, viewModel.filter.isActive {
            emptyState
        } else {
            List {
                ForEach(viewModel.items) { item in
                    // A plain Button, not a NavigationLink: the push is owned by
                    // `detailLink` outside the list.
                    Button {
                        selectedLog = item.log
                    } label: {
                        ApiLogRowView(log: item.log, logType: viewModel.logType)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
        }
    }

    /// Shown when filters exclude everything, so a blank list doesn't read as
    /// "no traffic".
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text("No logs match the current filter")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Clear filters") { viewModel.clearFilters() }
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if viewModel.showsStatusFilter {
                        statusChip
                    }
                    if !viewModel.availableMethods.isEmpty {
                        methodChip
                    }
                    if !viewModel.availableHosts.isEmpty {
                        hostChip
                    }
                    if viewModel.filter.isActive {
                        Button {
                            viewModel.clearFilters()
                        } label: {
                            Text("Clear")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Divider()
        }
        .background(Color(.systemBackground))
    }

    private var statusChip: some View {
        Menu {
            ForEach(StatusClass.allCases, id: \.self) { status in
                Button {
                    viewModel.toggleStatus(status)
                } label: {
                    Label(
                        status.title,
                        systemImage: viewModel.filter.statuses.contains(status) ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        } label: {
            chipLabel("Status", count: viewModel.filter.statuses.count)
        }
    }

    private var methodChip: some View {
        Menu {
            ForEach(viewModel.availableMethods, id: \.self) { method in
                Button {
                    viewModel.toggleMethod(method)
                } label: {
                    Label(
                        method,
                        systemImage: viewModel.filter.methods.contains(method) ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        } label: {
            chipLabel("Method", count: viewModel.filter.methods.count)
        }
    }

    private var hostChip: some View {
        Menu {
            ForEach(viewModel.availableHosts, id: \.self) { host in
                Button {
                    viewModel.toggleHost(host)
                } label: {
                    Label(
                        host,
                        systemImage: viewModel.filter.hosts.contains(host) ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        } label: {
            chipLabel("Host", count: viewModel.filter.hosts.count)
        }
    }

    private func chipLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(count > 0 ? "\(title) (\(count))" : title)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(.caption.weight(.medium))
        .foregroundColor(count > 0 ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(count > 0 ? Color.accentColor : Color(.secondarySystemBackground))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color(.systemGray4), lineWidth: count > 0 ? 0 : 1)
        )
    }

    // MARK: - Detail navigation

    /// A single link living outside the `List`, activated by `selectedLog`.
    ///
    /// A `NavigationLink` placed *inside* a `ForEach` row loses its active state
    /// whenever the list re-diffs — which, with live logs streaming in, pops the
    /// detail screen back to the list every time an entry arrives. Hoisting the
    /// link out means row churn can't reach it.
    private var detailLink: some View {
        NavigationLink(isActive: isShowingDetail) {
            if let selectedLog {
                ApiLogDetailView(log: selectedLog, logType: viewModel.logType)
            }
        } label: {
            EmptyView()
        }
    }

    private var isShowingDetail: Binding<Bool> {
        Binding(
            get: { selectedLog != nil },
            set: { isActive in
                if !isActive { selectedLog = nil }
            }
        )
    }

    // MARK: - Live stream controls

    private var pauseButton: some View {
        Button {
            viewModel.togglePause()
        } label: {
            Image(systemName: viewModel.isPaused ? "play.circle" : "pause.circle")
        }
        .accessibilityLabel(viewModel.isPaused ? "Resume live logs" : "Pause live logs")
    }

    /// Shown while paused so the list isn't silently stale.
    private var pausedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.fill")
            Text(viewModel.pendingCount > 0
                 ? "Paused — \(viewModel.pendingCount) new"
                 : "Paused")
            Spacer()
            Button("Resume") { viewModel.togglePause() }
                .font(.caption.weight(.semibold))
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.15))
    }

    // MARK: - Menu

    private var menu: some View {
        Menu {
            Button {
                viewModel.switchTo(.api)
            } label: {
                Label("API Logs", systemImage: viewModel.logType == .api ? "checkmark" : "list.bullet")
            }

            if viewModel.isEventTrackerLogEnabled {
                Button {
                    viewModel.switchTo(.eventTracker)
                } label: {
                    Label(
                        "EventTracker",
                        systemImage: viewModel.logType == .eventTracker ? "checkmark" : "chart.line.uptrend.xyaxis"
                    )
                }
            }

            if viewModel.isThirdPartyTrackerEnabled {
                Button {
                    viewModel.switchTo(.thirdParty)
                } label: {
                    Label(
                        "3rd Party",
                        systemImage: viewModel.logType == .thirdParty ? "checkmark" : "shippingbox"
                    )
                }
            }

            Button {
                copy(viewModel.exportText())
            } label: {
                Label("Copy Logs", systemImage: "doc.on.doc")
            }

            Button {
                shareItem = ShareItem(text: viewModel.exportText())
            } label: {
                Label("Share Logs…", systemImage: "square.and.arrow.up")
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
