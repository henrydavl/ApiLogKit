//
//  ApiLogHostingController.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//
//  Usage (modal):
//      let vc = ApiLogHostingController(logs: ApiLogger.shared.getLogs())
//      present(vc, animated: true)
//

import SwiftUI
import UIKit

public final class ApiLogHostingController: UIHostingController<ApiLogListView> {

    public init(logs: [ApiLog]) {
        // `onClose` needs a reference to the controller, which isn't available
        // until after `super.init`. Capture a weak holder and fill it in below.
        weak var holder: ApiLogHostingController?
        super.init(rootView: ApiLogListView(logs: logs, onClose: { holder?.close() }))
        holder = self
        // `.overFullScreen` (not `.fullScreen`) so presenting over a sheet/bottom
        // sheet doesn't tear down the presenter — otherwise the underlying sheet
        // comes back mis-laid-out after dismiss.
        modalPresentationStyle = .overFullScreen
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        // `.overFullScreen` can let content behind show through, since a hosting
        // controller's view background defaults to clear. Force it opaque.
        view.backgroundColor = .systemBackground
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func close() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}
