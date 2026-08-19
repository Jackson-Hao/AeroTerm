import SwiftUI

enum JSONHighlighter {
    static func attributed(_ text: String, scheme: ColorScheme) -> AttributedString {
        var output = AttributedString(text)
        let palette = Palette(scheme: scheme)
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        apply(output: &output, text: text, ns: ns, range: full, palette: palette)
        return output
    }

    private static func apply(
        output: inout AttributedString,
        text: String,
        ns: NSString,
        range: NSRange,
        palette: Palette
    ) {
        var index = range.location
        let end = NSMaxRange(range)
        while index < end {
            let ch = ns.character(at: index)
            if ch == 0x22 { // "
                let (next, isKey) = scanString(ns, from: index, end: end)
                color(output: &output, text: text, nsRange: NSRange(location: index, length: next - index), color: isKey ? palette.key : palette.string)
                index = next
                continue
            }
            if isDigit(ch) || (ch == 0x2D && index + 1 < end && isDigit(ns.character(at: index + 1))) {
                let next = scanNumber(ns, from: index, end: end)
                color(output: &output, text: text, nsRange: NSRange(location: index, length: next - index), color: palette.number)
                index = next
                continue
            }
            if let (next, tokenColor) = scanKeyword(ns, from: index, end: end, palette: palette) {
                color(output: &output, text: text, nsRange: NSRange(location: index, length: next - index), color: tokenColor)
                index = next
                continue
            }
            if "{}[],:".unicodeScalars.contains(Unicode.Scalar(ch)!) {
                color(output: &output, text: text, nsRange: NSRange(location: index, length: 1), color: palette.punctuation)
            }
            index += 1
        }
    }

    private static func scanString(_ ns: NSString, from start: Int, end: Int) -> (Int, Bool) {
        var index = start + 1
        var escaped = false
        while index < end {
            let ch = ns.character(at: index)
            if escaped {
                escaped = false
            } else if ch == 0x5C {
                escaped = true
            } else if ch == 0x22 {
                index += 1
                break
            }
            index += 1
        }
        var look = index
        while look < end, isSpace(ns.character(at: look)) {
            look += 1
        }
        let isKey = look < end && ns.character(at: look) == 0x3A
        return (index, isKey)
    }

    private static func scanNumber(_ ns: NSString, from start: Int, end: Int) -> Int {
        var index = start
        if ns.character(at: index) == 0x2D { index += 1 }
        while index < end, isDigit(ns.character(at: index)) { index += 1 }
        if index < end, ns.character(at: index) == 0x2E {
            index += 1
            while index < end, isDigit(ns.character(at: index)) { index += 1 }
        }
        if index < end {
            let exp = ns.character(at: index)
            if exp == 0x65 || exp == 0x45 {
                index += 1
                if index < end {
                    let sign = ns.character(at: index)
                    if sign == 0x2B || sign == 0x2D { index += 1 }
                }
                while index < end, isDigit(ns.character(at: index)) { index += 1 }
            }
        }
        return index
    }

    private static func scanKeyword(
        _ ns: NSString,
        from start: Int,
        end: Int,
        palette: Palette
    ) -> (Int, Color)? {
        let remaining = end - start
        if remaining >= 4, ns.substring(with: NSRange(location: start, length: 4)) == "true" {
            return wordBoundary(ns, start: start, length: 4, end: end).map { ($0, palette.keyword) }
        }
        if remaining >= 5, ns.substring(with: NSRange(location: start, length: 5)) == "false" {
            return wordBoundary(ns, start: start, length: 5, end: end).map { ($0, palette.keyword) }
        }
        if remaining >= 4, ns.substring(with: NSRange(location: start, length: 4)) == "null" {
            return wordBoundary(ns, start: start, length: 4, end: end).map { ($0, palette.null) }
        }
        return nil
    }

    private static func wordBoundary(_ ns: NSString, start: Int, length: Int, end: Int) -> Int? {
        let next = start + length
        if next < end, isIdent(ns.character(at: next)) { return nil }
        if start > 0, isIdent(ns.character(at: start - 1)) { return nil }
        return next
    }

    private static func color(output: inout AttributedString, text: String, nsRange: NSRange, color: Color) {
        guard let range = Range(nsRange, in: text) else { return }
        guard let attrRange = Range(range, in: output) else { return }
        output[attrRange].foregroundColor = color
    }

    private static func isDigit(_ ch: unichar) -> Bool { ch >= 0x30 && ch <= 0x39 }
    private static func isSpace(_ ch: unichar) -> Bool { ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D }
    private static func isIdent(_ ch: unichar) -> Bool {
        isDigit(ch) || (ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A) || ch == 0x5F
    }

    private struct Palette {
        let key: Color
        let string: Color
        let number: Color
        let keyword: Color
        let null: Color
        let punctuation: Color

        init(scheme: ColorScheme) {
            let dark = scheme == .dark
            key = dark ? Color(red: 0.55, green: 0.78, blue: 1.0) : Color(red: 0.12, green: 0.36, blue: 0.72)
            string = dark ? Color(red: 0.91, green: 0.67, blue: 0.42) : Color(red: 0.72, green: 0.35, blue: 0.05)
            number = dark ? Color(red: 0.72, green: 0.82, blue: 0.55) : Color(red: 0.18, green: 0.48, blue: 0.22)
            keyword = dark ? Color(red: 0.78, green: 0.55, blue: 0.95) : Color(red: 0.52, green: 0.18, blue: 0.68)
            null = dark ? Color(red: 0.62, green: 0.62, blue: 0.68) : Color(red: 0.45, green: 0.45, blue: 0.50)
            punctuation = dark ? Color(red: 0.70, green: 0.70, blue: 0.74) : Color(red: 0.40, green: 0.40, blue: 0.44)
        }
    }
}
