//
//  ShakeDetector.swift
//  ApiLogKit
//

import UIKit
import AudioToolbox

final class ShakeDetector {
    static let shared = ShakeDetector()
    private init() {}

    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        UIApplication.apilogkit_swizzleSendEvent()
    }

    func handle() {
        guard ApiLogger.shared.isEnabled else { return }
        DispatchQueue.main.async { self.present() }
    }

    private func present() {
        guard let rootVC = keyWindowRootVC() else { return }
        let top = topmostVC(from: rootVC)

        guard !(top is ApiLogHostingController) else { return }
        if let presented = top.presentedViewController, presented is ApiLogHostingController { return }

        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        top.present(ApiLogHostingController(logs: ApiLogger.shared.getLogs()), animated: true)
    }

    private func keyWindowRootVC() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    private func topmostVC(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController {
            return topmostVC(from: presented)
        }
        if let nav = root as? UINavigationController, let top = nav.topViewController {
            return topmostVC(from: top)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topmostVC(from: selected)
        }
        return root
    }
}

private extension UIApplication {
    static let swizzleSendEventOnce: Void = {
        guard
            let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
            let replacement = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.apilogkit_sendEvent(_:)))
        else { return }
        method_exchangeImplementations(original, replacement)
    }()

    static func apilogkit_swizzleSendEvent() { _ = swizzleSendEventOnce }

    @objc func apilogkit_sendEvent(_ event: UIEvent) {
        if event.type == .motion, event.subtype == .motionShake {
            ShakeDetector.shared.handle()
        }
        apilogkit_sendEvent(event)
    }
}
