import Foundation

// MARK: - Sources

public enum SourceKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case homebrew
    case npm
    case pnpm
    case bun
    case app
    case cli
    case mas
    case custom

    public var id: String { rawValue }

    /// The managers that own a package rather than an individual install.
    public var isPackageManager: Bool {
        switch self {
        case .homebrew, .npm, .pnpm, .bun, .mas: true
        case .app, .cli, .custom: false
        }
    }

    public var sortOrder: Int {
        switch self {
        case .homebrew: 0
        case .npm: 1
        case .pnpm: 2
        case .bun: 3
        case .app: 4
        case .cli: 5
        case .custom: 6
        case .mas: 7
        }
    }
}

public enum PackageKind: String, Codable, Sendable {
    case formula
    case cask
    case npmGlobal
    case pnpmGlobal
    case bunGlobal
    case application
    case binary
    case appStore
    case custom
}

// MARK: - Upgrade plans

public struct UpgradePlan: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Run a command in the user's environment.
        case command
        /// Open a URL (download page, App Store listing). Remige never installs these silently.
        case openURL
        /// Nothing safe to automate; the hint explains what to do.
        case manual
    }

    public var kind: Kind
    public var executable: String?
    public var arguments: [String]
    public var url: URL?
    public var hint: String?

    public init(
        kind: Kind,
        executable: String? = nil,
        arguments: [String] = [],
        url: URL? = nil,
        hint: String? = nil
    ) {
        self.kind = kind
        self.executable = executable
        self.arguments = arguments
        self.url = url
        self.hint = hint
    }

    public static func command(_ executable: String, _ arguments: [String]) -> UpgradePlan {
        UpgradePlan(kind: .command, executable: executable, arguments: arguments)
    }

    public static func open(_ url: URL) -> UpgradePlan {
        UpgradePlan(kind: .openURL, url: url)
    }

    public static func manual(_ hint: String) -> UpgradePlan {
        UpgradePlan(kind: .manual, hint: hint)
    }

    public var canRunAutomatically: Bool { kind == .command }

    /// Display form. Arguments are escaped for readability, never for execution.
    public var displayCommand: String? {
        guard kind == .command, let executable else { return nil }
        return ([executable] + arguments).map(ShellQuote.word).joined(separator: " ")
    }
}

// MARK: - Items

public struct OutdatedItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var displayName: String
    public var source: SourceKind
    public var kind: PackageKind
    public var currentVersion: String
    public var latestVersion: String
    public var summary: String?
    public var homepage: URL?
    public var repo: RepoRef?
    public var changelogURL: URL?
    public var changelogKind: ChangelogKind
    public var installedPath: String?
    public var bundleIdentifier: String?
    public var pinned: Bool
    public var upgrade: UpgradePlan

    public init(
        id: String,
        name: String,
        displayName: String? = nil,
        source: SourceKind,
        kind: PackageKind,
        currentVersion: String,
        latestVersion: String,
        summary: String? = nil,
        homepage: URL? = nil,
        repo: RepoRef? = nil,
        changelogURL: URL? = nil,
        changelogKind: ChangelogKind = .githubReleases,
        installedPath: String? = nil,
        bundleIdentifier: String? = nil,
        pinned: Bool = false,
        upgrade: UpgradePlan
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName ?? name
        self.source = source
        self.kind = kind
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.summary = summary
        self.homepage = homepage
        self.repo = repo
        self.changelogURL = changelogURL
        self.changelogKind = changelogKind
        self.installedPath = installedPath
        self.bundleIdentifier = bundleIdentifier
        self.pinned = pinned
        self.upgrade = upgrade
    }

    public var versionLine: String { "\(currentVersion) → \(latestVersion)" }
}

public enum ChangelogKind: String, Codable, Sendable {
    case githubReleases
    case appcast
    case web
    case none
}

// MARK: - Repositories

public struct RepoRef: Codable, Hashable, Sendable, Comparable {
    public var owner: String
    public var name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    public var slug: String { "\(owner)/\(name)" }
    public var webURL: URL { URL(string: "https://github.com/\(slug)")! }
    public var releasesURL: URL { URL(string: "https://github.com/\(slug)/releases")! }
    public var atomURL: URL { URL(string: "https://github.com/\(slug)/releases.atom")! }
    public var latestReleaseURL: URL { URL(string: "https://github.com/\(slug)/releases/latest")! }

    public static func < (lhs: RepoRef, rhs: RepoRef) -> Bool {
        lhs.slug.localizedCaseInsensitiveCompare(rhs.slug) == .orderedAscending
    }

    /// Extracts a GitHub repository from the many URL shapes ecosystems emit.
    public init?(urlLike raw: String?) {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        value = value.replacingOccurrences(of: "git+", with: "")
        value = value.replacingOccurrences(of: "git://", with: "https://")
        if value.hasPrefix("github:") {
            value = "https://github.com/" + value.dropFirst("github:".count)
        } else if value.hasPrefix("git@github.com:") {
            value = "https://github.com/" + value.dropFirst("git@github.com:".count)
        } else if value.hasPrefix("ssh://git@github.com/") {
            value = "https://github.com/" + value.dropFirst("ssh://git@github.com/".count)
        } else if value.range(of: #"^[\w.-]+/[\w.-]+$"#, options: .regularExpression) != nil {
            value = "https://github.com/" + value
        }

        guard let components = URLComponents(string: value),
            let host = components.host?.lowercased(),
            host == "github.com" || host == "www.github.com"
        else {
            return nil
        }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        var owner = parts[0]
        var repo = parts[1]
        if owner.hasSuffix(".git") { owner.removeLast(4) }
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        self.init(owner: owner, name: repo)
    }
}

// MARK: - Scan reports

public enum SourceState: String, Codable, Sendable {
    case ok
    case skipped
    case failed
    case disabled
}

/// Per-app coverage for sources that inspect a collection rather than a manager.
/// Detail rows never become update items: unsupported apps stay out of the list.
public struct SourceReportDetail: Codable, Identifiable, Hashable, Sendable {
    public enum State: String, Codable, Sendable {
        /// Checked successfully and a newer version exists (shown as an update).
        case checked
        /// Checked successfully with nothing newer available.
        case current
        /// No supported update source was found or declared.
        case unsupported
        /// A source exists but could not be read or parsed.
        case unavailable
        /// Another package manager owns the installation and checks it instead.
        case managed
    }

    public var id: String
    public var name: String
    public var state: State
    public var message: String?

    public init(id: String, name: String, state: State, message: String? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.message = message
    }
}

public struct SourceReport: Codable, Identifiable, Hashable, Sendable {
    public var source: SourceKind
    public var state: SourceState
    public var message: String?
    public var duration: Double
    public var count: Int
    /// True when a failed source is showing items from the previous scan.
    public var stale: Bool
    /// Structured coverage for collection sources such as installed apps.
    public var details: [SourceReportDetail]

    public var id: SourceKind { source }

    public init(
        source: SourceKind,
        state: SourceState,
        message: String? = nil,
        duration: Double = 0,
        count: Int = 0,
        stale: Bool = false,
        details: [SourceReportDetail] = []
    ) {
        self.source = source
        self.state = state
        self.message = message
        self.duration = duration
        self.count = count
        self.stale = stale
        self.details = details
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case state
        case message
        case duration
        case count
        case stale
        case details
    }

    /// Older snapshots have no `details`; decoding them must keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(SourceKind.self, forKey: .source)
        state = try container.decode(SourceState.self, forKey: .state)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        details = try container.decodeIfPresent([SourceReportDetail].self, forKey: .details) ?? []
    }
}

public struct ScanSnapshot: Codable, Sendable {
    public var schema: Int
    public var generatedAt: Date
    public var duration: Double
    public var items: [OutdatedItem]
    public var reports: [SourceReport]
    public var host: HostInfo
    public var warnings: [String]?

    public init(
        schema: Int = 1,
        generatedAt: Date = Date(),
        duration: Double = 0,
        items: [OutdatedItem] = [],
        reports: [SourceReport] = [],
        host: HostInfo = .current(),
        warnings: [String]? = nil
    ) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.duration = duration
        self.items = items
        self.reports = reports
        self.host = host
        self.warnings = warnings
    }

    public var actionableCount: Int {
        items.filter { $0.upgrade.canRunAutomatically }.count
    }
}

public struct HostInfo: Codable, Hashable, Sendable {
    public var name: String
    public var osVersion: String
    public var architecture: String

    public init(name: String, osVersion: String, architecture: String) {
        self.name = name
        self.osVersion = osVersion
        self.architecture = architecture
    }

    public static func current() -> HostInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var uts = utsname()
        uname(&uts)
        let machine = withUnsafePointer(to: &uts.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return HostInfo(
            name: ProcessInfo.processInfo.hostName,
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: machine
        )
    }
}

// MARK: - Changelog

public struct ChangelogRelease: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var version: String
    public var title: String
    public var publishedAt: Date?
    public var url: URL?
    /// Sanitized HTML. The app renders it with the system HTML importer; the CLI strips it.
    public var bodyHTML: String

    public init(
        id: String,
        version: String,
        title: String,
        publishedAt: Date? = nil,
        url: URL? = nil,
        bodyHTML: String = ""
    ) {
        self.id = id
        self.version = version
        self.title = title
        self.publishedAt = publishedAt
        self.url = url
        self.bodyHTML = bodyHTML
    }
}

// MARK: - Shell quoting

public enum ShellQuote {
    /// Quotes a word for *display*. Commands themselves always use argv arrays.
    public static func word(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%_+=:,./-"))
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
