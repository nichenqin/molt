import Foundation

/// Where a newer version of an installed app can be discovered.
public enum AppUpdateSource: Hashable, Sendable {
    /// A Sparkle appcast declared by `SUFeedURL`.
    case sparkle(URL)
    /// Official GitHub releases, resolved through the shared latest-tag resolver.
    case github(RepoRef)
    /// An Electron Builder `generic` provider directory containing OS manifests.
    case electronGeneric(baseURL: URL)
    /// A small text document plus a regex, used by explicit configuration.
    case text(URL, regex: String)
}

/// Result of reading standard Electron Builder update metadata from an app bundle.
public enum AppUpdateMetadata: Hashable, Sendable {
    case supported(AppUpdateSource)
    /// Metadata exists but cannot be used safely; keep the reason for coverage output.
    case unsupported(String)
}

/// Explicit app release sources for apps that do not ship standard update metadata.
///
/// This is deliberately data, not detector logic. Match bundle identity, never the
/// display name or the app filename.
public enum AppUpdateCatalog {
    /// Only apps whose bundle identifier, official release page and version
    /// sequence have been verified. Popularity alone is not a reason to guess.
    public static let sources: [String: AppUpdateSource] = [
        "2dust.v2rayN": .github(RepoRef(owner: "2dust", name: "v2rayN")),
        "com.aone.keka": .github(RepoRef(owner: "aonez", name: "Keka")),
        "com.jgraph.drawio.desktop": .github(RepoRef(owner: "jgraph", name: "drawio-desktop")),
        "com.knollsoft.Rectangle": .github(RepoRef(owner: "rxhanson", name: "Rectangle")),
        "com.lwouis.alt-tab-macos": .github(RepoRef(owner: "lwouis", name: "alt-tab-macos")),
        "com.utmapp.UTM": .github(RepoRef(owner: "utmapp", name: "UTM")),
        "com.yetone.magpie": .github(RepoRef(owner: "yetone", name: "magpie-releases")),
        "dev.zed.Zed": .github(RepoRef(owner: "zed-industries", name: "zed")),
        "eu.exelban.Stats": .github(RepoRef(owner: "exelban", name: "stats")),
        "io.github.clash-verge-rev.clash-verge-rev": .github(
            RepoRef(owner: "clash-verge-rev", name: "clash-verge-rev")),
        "md.obsidian": .github(RepoRef(owner: "obsidianmd", name: "obsidian-releases")),
        "org.hammerspoon.Hammerspoon": .github(
            RepoRef(owner: "Hammerspoon", name: "hammerspoon")),
        "org.localsend.localsendApp": .github(RepoRef(owner: "localsend", name: "localsend")),
        "org.m0k.transmission": .github(RepoRef(owner: "transmission", name: "transmission")),
        "org.p0deje.Maccy": .github(RepoRef(owner: "p0deje", name: "Maccy")),
        "pro.betterdisplay.BetterDisplay": .github(
            RepoRef(owner: "waydabber", name: "BetterDisplay")),
    ]

    public static func source(for bundleIdentifier: String?) -> AppUpdateSource? {
        guard let bundleIdentifier else { return nil }
        return sources[bundleIdentifier]
    }
}

// MARK: - Electron Builder metadata

/// Minimal, security-conscious reader for Electron Builder's
/// `Contents/Resources/app-update.yml`.
public enum AppUpdateMetadataReader {
    public static let relativePath = "Contents/Resources/app-update.yml"
    private static let maximumBytes = 256 * 1024

    public static func read(
        fromAppAt appURL: URL,
        fileManager: FileManager = .default
    ) -> AppUpdateMetadata? {
        let metadataURL = appURL.appendingPathComponent(relativePath)
        guard let attributes = try? fileManager.attributesOfItem(atPath: metadataURL.path)
        else { return nil }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumBytes, let data = try? Data(contentsOf: metadataURL),
            data.count <= maximumBytes
        else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ text: String) -> AppUpdateMetadata {
        var provider: String?
        var owner: String?
        var repo: String?
        var githubHost: String?
        var baseURL: String?
        var channel: String?
        var manifestPath: String?
        var inFiles = false
        let contents = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text

        for rawLine in contents.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), trimmed != "---" else { continue }

            let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
            if indentation == 0 {
                inFiles = false
                guard let (key, value) = SimpleYAML.keyValue(trimmed) else { continue }
                switch key {
                case "provider": provider = value
                case "owner": owner = value
                case "repo": repo = value
                case "host": githubHost = value
                case "url": baseURL = value
                case "channel": channel = value
                case "path": manifestPath = value
                case "files": inFiles = value.isEmpty
                default: break
                }
            } else if inFiles {
                var entry = trimmed
                if entry.hasPrefix("- ") {
                    entry = String(entry.dropFirst(2))
                }
                guard manifestPath == nil, let (key, value) = SimpleYAML.keyValue(entry),
                    key == "url"
                else { continue }
                manifestPath = value
            }
        }

        guard let provider = provider?.lowercased() else {
            return .unsupported("app-update.yml does not declare a provider")
        }
        switch provider {
        case "github":
            guard
                githubHost == nil
                    || githubHost?.caseInsensitiveCompare("github.com") == .orderedSame
                    || githubHost?.caseInsensitiveCompare("www.github.com") == .orderedSame,
                let owner,
                let repo,
                Self.isSafeSlugPart(owner),
                Self.isSafeSlugPart(repo)
            else {
                return .unsupported(
                    "app-update.yml must use public GitHub with a valid owner or repository")
            }
            return .supported(.github(RepoRef(owner: owner, name: repo)))
        case "generic":
            guard
                channel == nil || channel?.isEmpty == true
                    || channel?.caseInsensitiveCompare("latest") == .orderedSame
            else {
                return .unsupported("Electron update channel is not the default channel")
            }
            guard let baseURL, let url = Self.secureURL(baseURL) else {
                return .unsupported("app-update.yml generic url must be HTTPS")
            }
            return .supported(.electronGeneric(baseURL: url))
        default:
            return .unsupported("Unsupported updater provider “\(provider)”")
        }
    }

    private static func isSafeSlugPart(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    static func secureURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https",
            let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}

public struct ElectronUpdateManifest: Hashable, Sendable {
    public var version: String
    /// Relative paths or absolute HTTPS URLs from `path` or `files` entries.
    public var downloads: [String]

    public init(version: String, downloads: [String]) {
        self.version = version
        self.downloads = downloads
    }
}

public enum ElectronUpdateManifestParser {
    public static func parse(_ text: String) -> ElectronUpdateManifest? {
        var version: String?
        var path: String?
        var fileURLs: [String] = []
        var inFiles = false
        let contents = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text

        for rawLine in contents.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), trimmed != "---" else { continue }

            let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
            if indentation == 0 {
                inFiles = false
                guard let (key, value) = SimpleYAML.keyValue(trimmed) else { continue }
                switch key {
                case "version": version = value
                case "path": path = value
                case "files": inFiles = value.isEmpty
                default: break
                }
            } else if inFiles {
                var entry = trimmed
                if entry.hasPrefix("- ") {
                    entry = String(entry.dropFirst(2))
                }
                guard let (key, value) = SimpleYAML.keyValue(entry), key == "url" else {
                    continue
                }
                if !fileURLs.contains(value) { fileURLs.append(value) }
            }
        }

        guard let version, Version(version) != nil else { return nil }
        let candidates = fileURLs + (path.map { [$0] } ?? [])
        return ElectronUpdateManifest(version: version, downloads: candidates.filter(Self.isUsableDownload))
    }

    /// Relative paths inherit the manifest's HTTPS base; absolute URLs must be HTTPS.
    private static func isUsableDownload(_ raw: String) -> Bool {
        guard let scheme = URL(string: raw)?.scheme else { return true }
        return scheme.lowercased() == "https"
    }
}

// MARK: - Small YAML scalars

enum SimpleYAML {
    /// Splits a flat `key: value` line and unquotes the scalar. Anything with an
    /// inline comment is truncated only when the value is not quoted.
    static func keyValue(_ line: String) -> (key: String, value: String)? {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        let key = line[..<separator].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") || value.hasPrefix("'") {
            value = unquote(value)
        } else if let comment = value.range(of: " #") {
            value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return (key, value)
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
