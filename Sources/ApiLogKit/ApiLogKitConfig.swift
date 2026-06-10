//
//  ApiLogKitConfig.swift
//  ApiLogKit
//
//  Host-app integration points. Everything is optional; the library works
//  out of the box with defaults.
//

import SwiftUI

public enum ApiLogKitConfig {

    /// Locale used when formatting log dates (row timestamps).
    public static var dateLocale: Locale = .current

    /// Optional hook for a host-provided "Developer Options" screen.
    ///
    /// When set, the log list's menu shows a "Developer Options" entry that
    /// pushes the returned view. The closure receives an `onDismiss` callback
    /// the host view should call to pop itself.
    ///
    ///     ApiLogKitConfig.developerOptionsProvider = { onDismiss in
    ///         AnyView(MyDevOptionsView(onDismiss: onDismiss))
    ///     }
    public static var developerOptionsProvider: ((_ onDismiss: @escaping () -> Void) -> AnyView)?
}
