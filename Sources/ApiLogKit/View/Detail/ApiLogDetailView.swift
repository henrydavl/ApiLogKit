//
//  ApiLogDetailView.swift
//  Core
//
//  SwiftUI counterpart of the legacy `ApiLogDetailViewController`.
//

import SwiftUI
import UIKit

struct ApiLogDetailView: View {
    @StateObject private var viewModel: ApiLogDetailViewModel
    @State private var shareItem: ShareItem?

    // Copy confirmation toast.
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    // Render JSON bodies as raw text instead of the interactive tree.
    @State private var rawMode = false

    // Floating-button visibility, driven by top/bottom sentinel rows.
    @State private var atTop = true
    @State private var atBottom = false

    private let bottomAnchor = "apilog.detail.bottom"

    init(log: ApiLog, logType: LogEventType) {
        _viewModel = StateObject(wrappedValue: ApiLogDetailViewModel(log: log, logType: logType))
    }

    var body: some View {
        ScrollViewReader { proxy in
            list
                .listStyle(.plain)
                .overlay(alignment: .bottomTrailing) {
                    floatingButtons(proxy: proxy)
                }
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.hasJSONBody {
                    Button {
                        rawMode.toggle()
                    } label: {
                        Image(systemName: rawMode ? "curlybraces" : "text.alignleft")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                exportMenu
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(text: item.text)
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                toastBubble(toastMessage)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(viewModel.sections, id: \.self) { section in
                sectionHeader(section)
                    .id(section)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .onAppear { if section == viewModel.sections.first { atTop = true } }
                    .onDisappear { if section == viewModel.sections.first { atTop = false } }

                sectionBody(section)
            }

            // Bottom marker (only at the very end, so it adds no top whitespace).
            Color.clear
                .frame(height: 1)
                .id(bottomAnchor)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .onAppear { atBottom = true }
                .onDisappear { atBottom = false }
        }
        .environment(\.defaultMinListRowHeight, 0)
    }

    @ViewBuilder
    private func sectionBody(_ section: LogSection) -> some View {
        if let tree = viewModel.treeModel(for: section), !rawMode {
            // Controls live in their own fixed-height row so they don't shift
            // when expand/collapse resizes the tree row below.
            JSONTreeControls(model: tree)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            JSONTreeView(model: tree, onCopy: { copy($0) })
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        } else {
            let monospaced = viewModel.jsonNode(for: section) != nil
            ForEach(viewModel.rows(for: section)) { row in
                rowView(row, monospaced: monospaced)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { copy(row.value) }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func rowView(_ row: ApiLogDetailRow, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !row.key.isEmpty {
                Text(row.key)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Text(row.value)
                .font(monospaced ? .system(size: 13, design: .monospaced) : .system(size: 14))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }

    private func sectionHeader(_ section: LogSection) -> some View {
        HStack {
            Text(viewModel.title(for: section))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Button("Copy") {
                copy(viewModel.copyValue(for: section))
            }
            .font(.system(size: 13, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Copy + toast

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        showToast("Copied to clipboard")
    }

    private func showToast(_ message: String) {
        toastWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { toastMessage = message }

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

    // MARK: - Export menu

    private var exportMenu: some View {
        Menu {
            Button {
                shareItem = ShareItem(text: viewModel.exportRawLog())
            } label: {
                Label("Raw Log", systemImage: "doc.plaintext")
            }
            Button {
                shareItem = ShareItem(text: viewModel.exportCurl())
            } label: {
                Label("cURL Command", systemImage: "terminal")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }

    // MARK: - Floating buttons

    private var showScrollToTop: Bool { !atTop }
    private var showScrollToBottom: Bool { !atBottom }

    private func floatingButtons(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            if showScrollToTop {
                scrollButton(systemImage: "arrow.up") {
                    if let first = viewModel.sections.first {
                        withAnimation { proxy.scrollTo(first, anchor: .top) }
                    }
                }
            }
            if showScrollToBottom {
                scrollButton(systemImage: "arrow.down") {
                    withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                }
            }
        }
        .padding(16)
        .animation(.easeInOut(duration: 0.2), value: showScrollToTop)
        .animation(.easeInOut(duration: 0.2), value: showScrollToBottom)
    }

    private func scrollButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(.systemBackground))
                .padding(12)
                .background(Color(.label).opacity(0.75))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
    }
}
