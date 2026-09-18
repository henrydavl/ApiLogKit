//
//  ShareSheet.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [PlainTextItem(text)],
            applicationActivities: nil
        )
        // The system copy activity runs its own data detector over the text and
        // writes a `public.url` representation alongside it, so pasting landed
        // the URL alone in any app that prefers one. Nothing an item source
        // declares prevents that — measured, not assumed — so the activity is
        // dropped here and the menu offers a "Copy" that writes the pasteboard
        // directly instead.
        controller.excludedActivityTypes = [.copyToPasteboard]
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Declares an export as plain text, so the system doesn't treat it as a link.
///
/// Handing `UIActivityViewController` a bare `String` lets UIKit run data
/// detectors over it. Every export here begins with the request URL — see
/// `ApiLogExporter.rawLog` — so the detector found a link at offset zero and
/// presented the whole dump as a web page: the sheet showed a Safari icon
/// titled with the host, and the copy activity wrote *two* pasteboard
/// representations, `public.utf8-plain-text` with the full text and
/// `public.url` with only that first line.
///
/// Which one you got back depended on where you pasted. Anything that prefers
/// a URL — Safari's address bar, a chat composer, an issue tracker — took the
/// URL and silently dropped the rest, while a plain text field pasted
/// everything. That's why it only happened sometimes.
///
/// Naming the type explicitly keeps the payload a single text item.
private final class PlainTextItem: NSObject, UIActivityItemSource {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    /// Only used to size the preview, so it stays empty rather than copying the
    /// whole log twice.
    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        ""
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        text
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.plainText.identifier
    }

    /// Used as the filename by "Save to Files" and as the subject by Mail.
    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "API log"
    }

    /// Supplying metadata with a title and no URL stops the sheet resolving the
    /// detected link itself and previewing the export as a web page.
    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "API log"
        return metadata
    }
}
