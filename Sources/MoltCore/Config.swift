import Foundation

public struct CustomToolConfig: Codable, Hashable, Sendable {
    public var name: String
    public var path: String?
    public var versionArgs: [String]?
    public var versionRegex: String?
    public var github: String?
    public var latestURL: String?
    public var latestRegex: String?
    public var upgradeArgs: [String]?
    public var homepage: String?
    public var summary: String?

    public init(
        name: String,
        path: String? = nil,
        versionArgs: [String]? = nil,
        versionRegex: String? = nil,
        github: String? = nil,
        latestURL: String? = nil,
        latestRegex: String? = nil,
        upgradeArgs: [String]? = nil,
        homepage: String? = nil,
        summary: String? = nil
    ) {
        self.name = name
        self.path = path
        self.versionArgs = versionArgs
        self.versionRegex = versionRegex
        self.github = github
        self.latestURL = latestURL
        self.latestRegex = latestRegex
        self.upgradeArgs = upgradeArgs
        self.homepage = homepage
        self.summary = summary
    }
}

public struct MoltConfig: Codable, Hashable, Sendable {
    public var schema: Int
    public var disabledSources: [String]
    public var customTools: [CustomToolConfig]

    public init(
        schema: Int = 1,
        disabledSources: [String] = [],
        customTools: [CustomToolConfig] = []
    ) {
        self.schema = schema
        self.disabledSources = disabledSources
        self.customTools = customTools
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case disabledSources
        case customTools
    }

    /// A hand-written file may contain only the keys the user cares about.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        disabledSources = try container.decodeIfPresent([String].self, forKey: .disabledSources) ?? []
        customTools = try container.decodeIfPresent([CustomToolConfig].self, forKey: .customTools) ?? []
    }

    public static let empty = MoltConfig()

    public func isEnabled(_ source: SourceKind) -> Bool {
        !disabledSources.contains(source.rawValue)
    }
}

public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else if let override = ProcessInfo.processInfo.environment["MOLT_CONFIG"], !override.isEmpty {
            self.url = URL(fileURLWithPath: override)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.url =
                home
                .appendingPathComponent(".config/molt", isDirectory: true)
                .appendingPathComponent("config.json")
        }
    }

    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["MOLT_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/molt", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public var directory: URL { url.deletingLastPathComponent() }

    /// Missing file means defaults. A malformed file is surfaced rather than
    /// silently ignored so the user can fix it.
    public func load() throws -> MoltConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder.molt.decode(MoltConfig.self, from: data)
        } catch {
            throw ConfigError.invalid(url: url, underlying: error.localizedDescription)
        }
    }

    public func save(_ config: MoltConfig) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.molt.encode(config)
        try data.write(to: url, options: [.atomic])
    }

    /// Creates a commented starter file without overwriting an existing one.
    @discardableResult
    public func ensureExists() throws -> Bool {
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        try save(.empty)
        return true
    }
}

public enum ConfigError: LocalizedError {
    case invalid(url: URL, underlying: String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let url, let underlying):
            "Invalid config at \(url.path): \(underlying)"
        }
    }
}
