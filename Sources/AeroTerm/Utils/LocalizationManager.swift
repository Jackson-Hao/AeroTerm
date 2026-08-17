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
        let notFound = "__NOT_FOUND__"
        let localized = NSLocalizedString(key, bundle: activeBundle, value: notFound, comment: "")
        return (localized != notFound) ? localized : key
    }
}

extension View {
    public func localizedString(_ key: String) -> String {
        LocalizationManager.shared.text(key)
    }
}
