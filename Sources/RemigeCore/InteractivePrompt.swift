import Foundation

/// Text that asks a human for input on a terminal. Remige runs upgrades with
/// stdin closed, so these prompts can only be answered after the command is
/// handed to Terminal.
public enum InteractivePrompt {
    private static let patterns: [NSRegularExpression] = {
        let sources = [
            #"(?i)\b(password|passphrase)\s+is\s+required\b"#,
            #"(?i)\[sudo\]\s+password"#,
            #"(?i)\bsudo\b[^\n]*(password|tty|askpass|permission|denied|required)"#,
            #"(?im)^\s*(enter\s+)?(your\s+)?(password|passphrase)\b[^:\n]*:\s*$"#,
            #"(?im)(password|passphrase)\s+for\s+[^:\n]+:\s*$"#,
            #"(?i)\b(a\s+)?(terminal|tty)\s+is\s+required\b"#,
            #"(?i)\brequires?\s+(a\s+)?(terminal|tty)\b"#,
            #"(?i)\bno\s+tty\s+present\b"#,
            #"(?i)\bstdin\s+is\s+not\s+a\s+tty\b"#,
            #"(?i)\b(press|hit)\s+(any\s+key|enter|return)\b"#,
            #"(?i)\[(y/n|yes/no)\]|\((y/n|yes/no)\)"#,
            #"(?i)\bare\s+you\s+sure\b[^\n]*\?"#,
            #"(?i)\b(not|please)\s+(signed\s+in|sign\s+in)\b"#,
            #"(?i)\bsign\s+in\s+to\b"#,
            #"(?i)\b(authentication|authorization|approval)\s+(is\s+)?required\b"#,
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    public static func matches(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }
}
