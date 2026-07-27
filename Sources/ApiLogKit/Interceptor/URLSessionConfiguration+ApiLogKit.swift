//
//  URLSessionConfiguration+ApiLogKit.swift
//  ApiLogKit
//
//  `URLProtocol.registerClass(_:)` only covers `URLSession.shared` and the legacy
//  `NSURLConnection` stack — it does nothing for a session an SDK builds from its
//  own configuration, which is the case we actually care about. Swizzling the
//  configuration factories is how the protocol gets in front of those sessions.
//
//  Deliberately not swizzled: `background(withIdentifier:)`. Background sessions
//  run out of process and don't support `URLProtocol` at all.
//

import Foundation
import ObjectiveC

extension URLSessionConfiguration {

    /// Installs the swizzle exactly once, mirroring the idiom in `ShakeDetector`.
    static let apilogkit_swizzleOnce: Void = {
        // `default` and `ephemeral` are class properties, so their getters live on
        // the metaclass rather than on `URLSessionConfiguration` itself.
        guard let metaclass = object_getClass(URLSessionConfiguration.self) else { return }

        exchange(
            #selector(getter: URLSessionConfiguration.default),
            with: #selector(getter: URLSessionConfiguration.apilogkit_default),
            on: metaclass
        )
        exchange(
            #selector(getter: URLSessionConfiguration.ephemeral),
            with: #selector(getter: URLSessionConfiguration.apilogkit_ephemeral),
            on: metaclass
        )
    }()

    static func apilogkit_installSwizzle() { _ = apilogkit_swizzleOnce }

    // MARK: - Replacements

    // `dynamic` matters here: it forces dispatch through `objc_msgSend`, so once
    // the implementations have been exchanged these names resolve to the
    // *original* factories. Without it Swift could bind the call statically and
    // recurse forever.

    @objc dynamic class var apilogkit_default: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.apilogkit_default
        configuration.apilogkit_injectProtocol()
        return configuration
    }

    @objc dynamic class var apilogkit_ephemeral: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.apilogkit_ephemeral
        configuration.apilogkit_injectProtocol()
        return configuration
    }

    // MARK: - Helpers

    /// Puts the interceptor first in line, without duplicating it.
    private func apilogkit_injectProtocol() {
        var classes = protocolClasses ?? []
        classes.removeAll { ObjectIdentifier($0) == ObjectIdentifier(ApiLogURLProtocol.self) }
        classes.insert(ApiLogURLProtocol.self, at: 0)
        protocolClasses = classes
    }

    private static func exchange(_ original: Selector, with replacement: Selector, on cls: AnyClass) {
        guard let originalMethod = class_getInstanceMethod(cls, original),
              let replacementMethod = class_getInstanceMethod(cls, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}
