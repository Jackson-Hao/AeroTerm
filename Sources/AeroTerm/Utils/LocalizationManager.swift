import Foundation
import SwiftUI

@MainActor
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    private var activeBundle: Bundle = Bundle.main

    private init() {
        let baseBundle = Bundle.module
        if let path = baseBundle.path(forResource: "en-US", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.activeBundle = bundle
        } else if let path = Bundle.main.path(forResource: "en-US", ofType: "lproj"),
                  let bundle = Bundle(path: path) {
            self.activeBundle = bundle
        } else {
            self.activeBundle = baseBundle
        }
    }

    public func text(_ key: String) -> String {
        Self.lookup(key, in: activeBundle)
    }

    public func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), arguments: args)
    }

    nonisolated public static func lookup(_ key: String) -> String {
        lookup(key, in: resolvedBundle())
    }

    nonisolated public static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: lookup(key), arguments: args)
    }

    nonisolated private static func resolvedBundle() -> Bundle {
        let base = Bundle.module
        if let path = base.path(forResource: "en-US", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = Bundle.main.path(forResource: "en-US", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return base
    }

    nonisolated private static func lookup(_ key: String, in bundle: Bundle) -> String {
        let notFound = "__NOT_FOUND__"
        let localized = NSLocalizedString(key, bundle: bundle, value: notFound, comment: "")
        return localized != notFound ? localized : key
    }
}

extension View {
    public func localizedString(_ key: String) -> String {
        LocalizationManager.shared.text(key)
    }
}
