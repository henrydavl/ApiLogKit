//
//  JSONTreeView.swift
//  Core
//
//  Interactive, collapsible JSON viewer for the ApiLog detail screen.
//  Objects and arrays can be folded so long responses stay navigable.
//

import SwiftUI

// MARK: - Expansion state

final class JSONTreeModel: ObservableObject {
    @Published private var expandedPaths: Set<String>

    /// Strings longer than this are truncated in the tree (e.g. base64).
    let stringLimit = 300

    let root: JSONNode

    init(root: JSONNode) {
        self.root = root
        self.expandedPaths = JSONTreeModel.defaultExpanded(root)
    }

    func isExpanded(_ path: String) -> Bool { expandedPaths.contains(path) }

    func toggle(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    func expandAll() { expandedPaths = JSONTreeModel.allContainerPaths(root) }

    func collapseAll() { expandedPaths = [JSONTreeModel.rootPath] }

    // MARK: Path helpers

    static let rootPath = "$"

    /// Default: top two levels expanded, large arrays start collapsed.
    private static func defaultExpanded(_ root: JSONNode) -> Set<String> {
        var set: Set<String> = []
        func walk(_ node: JSONNode, path: String, depth: Int) {
            switch node {
            case .object(let pairs):
                if depth < 2 { set.insert(path) }
                for pair in pairs { walk(pair.value, path: path + "." + pair.key, depth: depth + 1) }
            case .array(let items):
                if depth < 2 && items.count <= 100 { set.insert(path) }
                for (index, item) in items.enumerated() { walk(item, path: path + "[\(index)]", depth: depth + 1) }
            default:
                break
            }
        }
        walk(root, path: rootPath, depth: 0)
        return set
    }

    private static func allContainerPaths(_ root: JSONNode) -> Set<String> {
        var set: Set<String> = []
        func walk(_ node: JSONNode, path: String) {
            switch node {
            case .object(let pairs):
                set.insert(path)
                for pair in pairs { walk(pair.value, path: path + "." + pair.key) }
            case .array(let items):
                set.insert(path)
                for (index, item) in items.enumerated() { walk(item, path: path + "[\(index)]") }
            default:
                break
            }
        }
        walk(root, path: rootPath)
        return set
    }
}

// MARK: - Expand / collapse controls

/// Kept in its own (fixed-height) row, separate from the tree, so the buttons
/// don't shift when expanding/collapsing resizes the tree.
struct JSONTreeControls: View {
    @ObservedObject var model: JSONTreeModel

    var body: some View {
        HStack(spacing: 12) {
            Button { model.expandAll() } label: {
                Label("Expand all", systemImage: "plus.square")
            }
            Button { model.collapseAll() } label: {
                Label("Collapse all", systemImage: "minus.square")
            }
            Spacer()
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Tree container

struct JSONTreeView: View {
    @ObservedObject var model: JSONTreeModel
    let onCopy: (String) -> Void

    var body: some View {
        JSONNodeView(
            model: model,
            key: nil,
            index: nil,
            node: model.root,
            path: JSONTreeModel.rootPath,
            onCopy: onCopy
        )
    }
}

// MARK: - Node

struct JSONNodeView: View {
    @ObservedObject var model: JSONTreeModel
    let key: String?       // object member key
    let index: Int?        // array element index
    let node: JSONNode
    let path: String
    let onCopy: (String) -> Void

    private let font = Font.system(size: 13, design: .monospaced)
    private let indent: CGFloat = 16
    private let chevronColumn: CGFloat = 12
    /// Leading inset for leaf rows so their text aligns under container text
    /// (chevron width + HStack spacing).
    private let textInset: CGFloat = 16

    var body: some View {
        switch node {
        case .object(let pairs) where !pairs.isEmpty:
            container(open: "{", close: "}", count: pairs.count) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    JSONNodeView(
                        model: model,
                        key: pair.key,
                        index: nil,
                        node: pair.value,
                        path: path + "." + pair.key,
                        onCopy: onCopy
                    )
                }
            }
        case .array(let items) where !items.isEmpty:
            container(open: "[", close: "]", count: items.count) {
                ForEach(Array(items.enumerated()), id: \.offset) { itemIndex, item in
                    JSONNodeView(
                        model: model,
                        key: nil,
                        index: itemIndex,
                        node: item,
                        path: path + "[\(itemIndex)]",
                        onCopy: onCopy
                    )
                }
            }
        default:
            leafRow
        }
    }

    // MARK: Container

    @ViewBuilder
    private func container<Content: View>(
        open: String,
        close: String,
        count: Int,
        @ViewBuilder children: () -> Content
    ) -> some View {
        let expanded = model.isExpanded(path)
        VStack(alignment: .leading, spacing: 3) {
            Button {
                model.toggle(path)
            } label: {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: chevronColumn, alignment: .leading)
                        .padding(.top, 3)
                    headerText(open: open, close: close, count: count, expanded: expanded)
                        .font(font)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .contextMenu { copyButton }

            if expanded {
                children()
                    .padding(.leading, indent)
                Text(close)
                    .foregroundColor(.secondary)
                    .font(font)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerText(open: String, close: String, count: Int, expanded: Bool) -> Text {
        if expanded {
            return prefixText + Text(open).foregroundColor(.secondary)
        }
        return prefixText
            + Text("\(open) … \(close)").foregroundColor(.secondary)
            + Text("  \(count)").foregroundColor(Color(.tertiaryLabel))
    }

    // MARK: Leaf

    /// True when this leaf is a string longer than the display limit.
    private var isTruncatableString: Bool {
        if case .string(let value) = node { return value.count > model.stringLimit }
        return false
    }

    private var leafRow: some View {
        // Plain leading padding (no Color.clear spacer / baseline alignment),
        // letting the Text wrap and self-size correctly.
        (prefixText + valueText)
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, textInset)
            .contentShape(Rectangle())
            .onTapGesture {
                // Long strings expand/collapse on tap; everything else copies.
                if isTruncatableString {
                    model.toggle(path)
                } else {
                    onCopy(node.rawValue)
                }
            }
            .contextMenu { copyButton }
    }

    // MARK: Pieces

    private var prefixText: Text {
        if let key {
            return Text("\"\(key)\"").foregroundColor(.primary)
                + Text(": ").foregroundColor(.secondary)
        }
        if let index {
            return Text("\(index): ").foregroundColor(Color(.tertiaryLabel))
        }
        return Text("")
    }

    private var valueText: Text {
        switch node {
        case .string(let value):
            if value.count > model.stringLimit, !model.isExpanded(path) {
                let head = String(value.prefix(model.stringLimit))
                return Text("\"\(head)…\"").foregroundColor(.green)
                    + Text("  tap to expand · \(value.count) chars").foregroundColor(Color(.tertiaryLabel))
            }
            return Text("\"\(value)\"").foregroundColor(.green)
        case .number(let value):
            return Text(value).foregroundColor(.blue)
        case .bool(let value):
            return Text(value ? "true" : "false").foregroundColor(.purple)
        case .null:
            return Text("null").foregroundColor(.secondary)
        case .object:
            return Text("{}").foregroundColor(.secondary)
        case .array:
            return Text("[]").foregroundColor(.secondary)
        }
    }

    private var copyButton: some View {
        Button {
            onCopy(node.rawValue)
        } label: {
            Label(node.isContainer ? "Copy subtree" : "Copy value", systemImage: "doc.on.doc")
        }
    }
}
