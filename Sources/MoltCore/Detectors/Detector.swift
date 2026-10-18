import Foundation

public struct ScanContext: Sendable {
    public var runner: CommandRunning
    public var http: HTTPGetting
    public var cache: DiskCache
    public var config: MoltConfig
    public var environment: EnvironmentInfo
    public var forceRefresh: Bool

    public init(
        runner: CommandRunning,
        http: HTTPGetting,
        cache: DiskCache,
        config: MoltConfig,
        environment: EnvironmentInfo,
        forceRefresh: Bool = false
    ) {
        self.runner = runner
        self.http = http
        self.cache = cache
        self.config = config
        self.environment = environment
        self.forceRefresh = forceRefresh
    }
}

public struct DetectorOutput: Sendable {
    public var items: [OutdatedItem]
    public var message: String?
    public var skipped: Bool

    public init(items: [OutdatedItem] = [], message: String? = nil, skipped: Bool = false) {
        self.items = items
        self.message = message
        self.skipped = skipped
    }

    public static func skipped(_ message: String) -> DetectorOutput {
        DetectorOutput(message: message, skipped: true)
    }
}

public protocol OutdatedSourceDetector: Sendable {
    var source: SourceKind { get }
    func scan(_ context: ScanContext) async throws -> DetectorOutput
}

enum DetectorSupport {
    static func failure(_ result: CommandResult) -> Error? {
        guard !result.succeeded else { return nil }
        return DetectorError.command(result.failureMessage ?? "Command failed")
    }

    static func cleanVersion(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("v") || result.hasPrefix("V") { result.removeFirst() }
        return result
    }
}

public enum DetectorError: LocalizedError {
    case command(String)
    case parse(String)

    public var errorDescription: String? {
        switch self {
        case .command(let message): message
        case .parse(let message): "Could not parse output: \(message)"
        }
    }
}
