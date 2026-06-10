//
//  ShareSheet.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import SwiftUI
import UIKit

struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
