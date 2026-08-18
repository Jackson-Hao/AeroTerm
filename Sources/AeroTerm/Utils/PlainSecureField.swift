import SwiftUI
import AppKit

/// Secure field that does not opt into AutoFill / verification-code suggestions.
public struct PlainSecureField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    public init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    public func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField(string: text)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.focusRingType = .default
        field.contentType = nil
        field.isAutomaticTextCompletionEnabled = false
        return field
    }

    public func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSecureTextField else { return }
            text.wrappedValue = field.stringValue
        }

        public func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSSecureTextField else { return }
            field.contentType = nil
            if let editor = field.currentEditor() as? NSTextView {
                editor.isAutomaticTextCompletionEnabled = false
                editor.isAutomaticSpellingCorrectionEnabled = false
                editor.isAutomaticQuoteSubstitutionEnabled = false
                editor.isAutomaticDashSubstitutionEnabled = false
                editor.isAutomaticDataDetectionEnabled = false
                editor.isAutomaticLinkDetectionEnabled = false
                editor.isAutomaticTextReplacementEnabled = false
            }
        }
    }
}

extension View {
    func disablesPasswordAutofill() -> some View {
        disableAutocorrection(true)
    }
}
