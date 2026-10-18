import Foundation
import MoltCore

public struct CLIError: LocalizedError {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum CLIFormat {
    public struct Palette: Sendable {
        public var enabled: Bool

        public func dim(_ value: String) -> String { enabled ? "\u{1B}[2m\(value)\u{1B}[0m" : value }
        public func bold(_ value: String) -> String { enabled ? "\u{1B}[1m\(value)\u{1B}[0m" : value }
        public func green(_ value: String) -> String { enabled ? "\u{1B}[32m\(value)\u{1B}[0m" : value }
        public func cyan(_ value: String) -> String { enabled ? "\u{1B}[36m\(value)\u{1B}[0m" : value }
        public func yellow(_ value: String) -> String { enabled ? "\u{1B}[33m\(value)\u{1B}[0m" : value }
        public func red(_ value: String) -> String { enabled ? "\u{1B}[31m\(value)\u{1B}[0m" : value }
    }

    public static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    public static func relative(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86400))d ago"
        }
    }

    public static func duration(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }

    public static func sourceTitle(_ source: SourceKind) -> String {
        switch source {
        case .homebrew: "HOMEBREW"
        case .npm: "NPM"
        case .pnpm: "PNPM"
        case .bun: "BUN"
        case .app: "APPS"
        case .cli: "CLI TOOLS"
        case .mas: "APP STORE"
        case .custom: "CUSTOM"
        }
    }

    public static func table(items: [OutdatedItem], palette: Palette) -> String {
        guard !items.isEmpty else { return "" }
        let groups = Dictionary(grouping: items, by: \.source)
        var lines: [String] = []
        for source in SourceKind.allCases {
            guard let group = groups[source], !group.isEmpty else { continue }
            lines.append("")
            lines.append(palette.dim(sourceTitle(source)))
            let nameWidth = min(34, group.map { $0.displayName.count }.max() ?? 10)
            let currentWidth = min(18, group.map { $0.currentVersion.count }.max() ?? 8)
            for item in group {
                let current = item.currentVersion.padding(
                    toLength: max(currentWidth, item.currentVersion.count),
                    withPad: " ",
                    startingAt: 0
                )
                let action: String
                switch item.upgrade.kind {
                case .command: action = palette.green("auto")
                case .openURL: action = palette.cyan("open")
                case .manual: action = palette.dim("manual")
                }
                let pinned = item.pinned ? " " + palette.yellow("pinned") : ""
                lines.append(
                    "  \(palette.bold(item.displayName))\(String(repeating: " ", count: max(0, nameWidth - item.displayName.count)))"
                        + "  \(palette.dim(current))  →  \(item.latestVersion)  \(action)\(pinned)"
                )
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Query matching

public enum CLIQuery {
    public static func resolve(_ query: String, in items: [OutdatedItem]) throws -> OutdatedItem {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { throw CLIError("Give a package id, name or display name.") }

        if let exact = items.first(where: { $0.id.lowercased() == needle }) {
            return exact
        }
        let nameMatches = items.filter {
            $0.name.lowercased() == needle || $0.displayName.lowercased() == needle
        }
        if nameMatches.count == 1 { return nameMatches[0] }
        if nameMatches.count > 1 {
            let ids = nameMatches.map(\.id).joined(separator: ", ")
            throw CLIError("“\(query)” matches several packages: \(ids). Use an id.")
        }
        let contains = items.filter {
            $0.name.lowercased().contains(needle) || $0.displayName.lowercased().contains(needle)
        }
        if contains.count == 1 { return contains[0] }
        if contains.isEmpty { throw CLIError("No outdated package matches “\(query)”.") }
        let ids = contains.map(\.id).joined(separator: ", ")
        throw CLIError("“\(query)” is ambiguous: \(ids).")
    }
}
