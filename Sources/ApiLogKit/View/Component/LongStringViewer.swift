//
//  LongStringViewer.swift
//  ApiLogKit
//
//  Full-screen viewer for string values too long to lay out inline in the JSON
//  tree — base64 images, tokens, encrypted payloads. The text is split into
//  chunks rendered lazily, so only what's on screen is laid out.
//

import SwiftUI
import UIKit

struct LongStringItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

struct LongStringViewer: View {
    let item: LongStringItem

    @Environment(\.dismiss) private var dismiss

    @State private var chunks: [String] = []
    @State private var image: UIImage?
    @State private var showsImage = true
    @State private var copied = false

    private static let fontSize: CGFloat = 12
    nonisolated private static let linesPerChunk = 40

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                infoBar
                Divider()
                if let image, showsImage {
                    imagePreview(image)
                } else {
                    textBody
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = item.value
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await detectImage() }
    }

    // MARK: - Info

    private var infoBar: some View {
        HStack(spacing: 12) {
            Text(summary)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
            if image != nil {
                Picker("Display", selection: $showsImage) {
                    Text("Image").tag(true)
                    Text("Text").tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var summary: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(item.value.utf8.count), countStyle: .file)
        guard let image else { return size }
        let pixels = "\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale))"
        return "\(size) · base64 image \(pixels)"
    }

    // MARK: - Image

    private func imagePreview(_ image: UIImage) -> some View {
        ScrollView {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(16)
        }
    }

    /// Decodes off the main thread; most long strings aren't images, and a
    /// multi-megabyte decode would otherwise delay the sheet.
    private func detectImage() async {
        let value = item.value
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decodeBase64Image(value)
        }.value
        image = decoded
    }

    /// Accepts bare base64 or a `data:image/...;base64,` URI.
    nonisolated private static func decodeBase64Image(_ value: String) -> UIImage? {
        var payload = Substring(value)
        if payload.hasPrefix("data:"), let comma = payload.firstIndex(of: ",") {
            payload = payload[payload.index(after: comma)...]
        }
        guard let data = Data(base64Encoded: String(payload), options: .ignoreUnknownCharacters) else {
            return nil
        }
        return UIImage(data: data)
    }

    // MARK: - Text

    private var textBody: some View {
        GeometryReader { geometry in
            let charsPerLine = Self.charsPerLine(width: geometry.size.width - 32)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(chunks.indices, id: \.self) { index in
                        Text(chunks[index])
                            .font(.system(size: Self.fontSize, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .overlay {
                if chunks.isEmpty { ProgressView() }
            }
            .task(id: charsPerLine) {
                let value = item.value
                chunks = await Task.detached(priority: .userInitiated) {
                    Self.chunk(value, charsPerLine: charsPerLine)
                }.value
            }
        }
    }

    /// Characters that fit on one line of the monospaced font, less one so a
    /// hard-wrapped line never spills onto a second.
    private static func charsPerLine(width: CGFloat) -> Int {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        guard advance > 0, width > 0 else { return 80 }
        return max(20, Int(width / advance) - 1)
    }

    /// Values without whitespace (base64, tokens) are hard-wrapped to the line
    /// width: left to itself, `Text` breaks them at `/` and `+` and at every
    /// chunk boundary, leaving ragged lines throughout. Display only — Copy
    /// always takes the original value.
    nonisolated private static func chunk(_ value: String, charsPerLine: Int) -> [String] {
        let hardWrap = !value.contains(where: \.isWhitespace)
        let lineLength = hardWrap ? charsPerLine : charsPerLine * linesPerChunk
        let linesPerPiece = hardWrap ? linesPerChunk : 1

        var result: [String] = []
        var lines: [Substring] = []
        var start = value.startIndex
        while start < value.endIndex {
            let end = value.index(start, offsetBy: lineLength, limitedBy: value.endIndex) ?? value.endIndex
            lines.append(value[start..<end])
            start = end
            if lines.count == linesPerPiece {
                result.append(lines.joined(separator: "\n"))
                lines.removeAll(keepingCapacity: true)
            }
        }
        if !lines.isEmpty { result.append(lines.joined(separator: "\n")) }
        return result
    }
}
