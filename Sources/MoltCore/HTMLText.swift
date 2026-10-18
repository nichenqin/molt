import Foundation

/// Lightweight HTML-to-text for terminal output. The app renders the original
/// HTML through AppKit for richer typography; the CLI stays text-only.
public enum HTMLText {
    public static func plain(from html: String) -> String {
        var value = html
        value = value.replacingOccurrences(
            of: #"<(script|style)[^>]*>[\s\S]*?</\1>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(
            of: #"</(p|div|h[1-6]|tr|blockquote)>"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(
            of: #"<li[^>]*>"#, with: "• ", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"</li>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(
            of: #"<h[1-6][^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: [.regularExpression])
        value = decodeEntities(value)
        value = value.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func decodeEntities(_ value: String) -> String {
        var result = value
        let named = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric entities.
        guard let expression = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return result
        }
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
        for match in matches.reversed() {
            guard let full = Range(match.range, in: result),
                let digitsRange = Range(match.range(at: 1), in: result)
            else { continue }
            let digits = String(result[digitsRange])
            let scalarValue: UInt32?
            if digits.lowercased().hasPrefix("x") {
                scalarValue = UInt32(digits.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(digits)
            }
            if let scalarValue, let scalar = Unicode.Scalar(scalarValue) {
                result.replaceSubrange(full, with: String(Character(scalar)))
            }
        }
        return result
    }
}
