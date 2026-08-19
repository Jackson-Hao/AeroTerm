import Foundation
import SwiftUI

let languageDefaultsKey = "AeroTerm.AppLanguage.v1"

@MainActor
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    private var activeBundle: Bundle = Bundle.main

    private init() {
        apply(savedLanguage())
    }

    public func apply(_ language: AppLanguage) {
        activeBundle = Self.bundle(forLproj: language.lprojName)
        objectWillChange.send()
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

    private func savedLanguage() -> AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: languageDefaultsKey),
           let language = AppLanguage(rawValue: raw) {
            return language
        }
        return .system
    }

    nonisolated private static func resolvedBundle() -> Bundle {
        let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: languageDefaultsKey) ?? "") ?? .system
        return bundle(forLproj: language.lprojName)
    }

    nonisolated private static func bundle(forLproj name: String) -> Bundle {
        let candidates = [name, name.lowercased(), "en-US"]
        for candidate in candidates {
            if let path = Bundle.module.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return Bundle.module
    }

    nonisolated private static func lookup(_ key: String, in bundle: Bundle) -> String {
        let notFound = "__NOT_FOUND__"
        let localized = NSLocalizedString(key, bundle: bundle, value: notFound, comment: "")
        if localized != notFound {
            return localized
        }
        if bundle !== Bundle.module,
           let path = Bundle.module.path(forResource: "en-US", ofType: "lproj"),
           let english = Bundle(path: path) {
            let fallback = NSLocalizedString(key, bundle: english, value: notFound, comment: "")
            if fallback != notFound {
                return fallback
            }
        }
        return key
    }
}

extension View {
    public func localizedString(_ key: String) -> String {
        LocalizationManager.shared.text(key)
    }
}
