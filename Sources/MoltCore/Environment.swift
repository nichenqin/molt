import Foundation

// MARK: - Cask index

/// Local map from Homebrew Cask tokens to the .app bundles they installed.
/// Built from Caskroom, so it costs one directory walk and no subprocess.
public struct CaskIndex: Sendable {
    public struct Entry: Sendable, Hashable {
        public var token: String
        public var appNames: [String]
        public var installedPaths: [String]
    }

    public private(set) var entries: [Entry]
    private var byAppName: [String: Entry]
    private var byPath: [String: Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
        var names: [String: Entry] = [:]
        var paths: [String: Entry] = [:]
        for entry in entries {
            for name in entry.appNames {
                names[Self.normalize(name)] = entry
            }
            for path in entry.installedPaths {
                paths[Self.normalize(path)] = entry
            }
        }
        self.byAppName = names
        self.byPath = paths
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func token(for appPath: String) -> String? {
        byPath[Self.normalize(appPath)]?.token
    }

    public func installedPath(for token: String) -> String? {
        entries.first { $0.token == token }?.installedPaths.first
    }

    public func entry(for token: String) -> Entry? {
        entries.first { $0.token == token }
    }

    public static func scan(caskroom: URL, fileManager: FileManager = .default) -> CaskIndex {
        guard
            let tokens = try? fileManager.contentsOfDirectory(
                at: caskroom,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return CaskIndex() }

        let applications = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        var entries: [Entry] = []
        for tokenURL in tokens {
            let isDirectory = (try? tokenURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            let token = tokenURL.lastPathComponent
            guard
                let versions = try? fileManager.contentsOfDirectory(
                    at: tokenURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            else { continue }

            var appNames: [String] = []
            var paths: [String] = []
            for versionURL in versions {
                let isVersionDirectory =
                    (try? versionURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isVersionDirectory else { continue }
                guard
                    let staged = try? fileManager.contentsOfDirectory(
                        at: versionURL,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )
                else { continue }
                for item in staged where item.pathExtension == "app" {
                    let name = item.lastPathComponent
                    appNames.append(name)
                    let installed = applications.map { $0.appendingPathComponent(name) }
                        .first { fileManager.fileExists(atPath: $0.path) }
                    paths.append(installed?.path ?? item.path)
                }
            }
            if !appNames.isEmpty {
                entries.append(Entry(token: token, appNames: appNames, installedPaths: paths))
            }
        }
        return CaskIndex(entries: entries)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Environment

public struct BrewEnvironment: Sendable, Hashable {
    public var executable: String
    public var prefix: String
    public var caskroom: URL

    public init(executable: String, prefix: String, caskroom: URL) {
        self.executable = executable
        self.prefix = prefix
        self.caskroom = caskroom
    }
}

public struct EnvironmentInfo: Sendable {
    public var locator: ExecutableLocator
    public var brew: BrewEnvironment?
    public var caskIndex: CaskIndex
    public var npm: String?
    public var pnpm: String?
    public var bun: String?
    public var mas: String?
    public var osVersion: Version?

    public init(
        locator: ExecutableLocator? = nil,
        brew: BrewEnvironment? = nil,
        caskIndex: CaskIndex? = nil,
        osVersion: Version? = nil,
        managers: [SourceKind: String] = [:]
    ) {
        let locator = locator ?? ExecutableLocator()
        self.locator = locator
        self.brew = brew ?? Self.locateBrew(locator)
        self.caskIndex = caskIndex ?? self.brew.map { CaskIndex.scan(caskroom: $0.caskroom) } ?? CaskIndex()
        self.npm = managers[.npm] ?? locator.find("npm")
        self.pnpm = managers[.pnpm] ?? locator.find("pnpm")
        self.bun = managers[.bun] ?? locator.find("bun")
        self.mas = managers[.mas] ?? locator.find("mas")
        let version = ProcessInfo.processInfo.operatingSystemVersion
        self.osVersion = osVersion ?? Version("\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
    }

    public static func locateBrew(_ locator: ExecutableLocator) -> BrewEnvironment? {
        guard let executable = locator.find("brew") else { return nil }
        let prefix = URL(fileURLWithPath: executable).deletingLastPathComponent()
            .deletingLastPathComponent().path
        return BrewEnvironment(
            executable: executable,
            prefix: prefix,
            caskroom: URL(fileURLWithPath: prefix).appendingPathComponent("Caskroom")
        )
    }

    /// Binaries owned by a package manager must not also appear as standalone
    /// curl installs. This is path-based on purpose: no extra subprocesses.
    public func isManagedBinary(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let markers = [
            "/Cellar/",
            "/Caskroom/",
            "/node_modules/",
            "/.volta/",
            "/.bun/install/",
            "/Library/pnpm/",
            "/.local/share/pnpm/",
            ".app/Contents/",
            "/.local/share/mise/",
            "/.asdf/",
        ]
        if markers.contains(where: { resolved.contains($0) }) { return true }
        if let brew, resolved.hasPrefix(brew.prefix + "/") { return true }
        return false
    }
}

// MARK: - Paths

public enum MoltPaths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var config: URL { ConfigStore.defaultURL }
    public static var cache: URL { DiskCache.defaultDirectory }
    public static var bunGlobal: URL {
        if let install = ProcessInfo.processInfo.environment["BUN_INSTALL"], !install.isEmpty {
            return URL(fileURLWithPath: install).appendingPathComponent("install/global")
        }
        return home.appendingPathComponent(".bun/install/global")
    }
}
