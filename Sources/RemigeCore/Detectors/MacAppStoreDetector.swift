import Foundation

/// Mac App Store updates when `mas` is installed. `mas outdated` reports app
/// IDs but not the store version, so Remige shows "App Store" as the target and
/// lets `mas` perform the upgrade.
public struct MacAppStoreDetector: OutdatedSourceDetector {
    public let source = SourceKind.mas

    public init() {}

    struct StoreApp {
        var id: String
        var name: String
        var version: String
    }

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        guard let mas = context.environment.mas else {
            return .skipped("mas not installed")
        }
        async let listed = context.runner.run(
            CommandSpec(executable: mas, arguments: ["list"]),
            timeout: 20
        )
        async let outdated = context.runner.run(
            CommandSpec(executable: mas, arguments: ["outdated"]),
            timeout: 20
        )
        let (listResult, outdatedResult) = await (listed, outdated)
        if let error = DetectorSupport.failure(listResult) { throw error }
        if let error = DetectorSupport.failure(outdatedResult) { throw error }

        let installed = Self.parse(listResult.stdoutText)
        let outdatedIDs = Set(Self.parse(outdatedResult.stdoutText).map(\.id))
        let apps = installed.filter { outdatedIDs.contains($0.id) }
        guard !apps.isEmpty else {
            return DetectorOutput(message: "No App Store updates")
        }

        let applications = AppScanner.scan()
        let items = apps.map { app -> OutdatedItem in
            let match = applications.first { $0.name.caseInsensitiveCompare(app.name) == .orderedSame }
            var item = OutdatedItem(
                id: "mas:\(app.id)",
                name: app.name,
                source: .mas,
                kind: .appStore,
                currentVersion: app.version,
                latestVersion: "App Store",
                summary: nil,
                homepage: URL(string: "macappstore://apps.apple.com/app/id\(app.id)"),
                repo: nil,
                changelogURL: URL(string: "https://apps.apple.com/app/id\(app.id)"),
                changelogKind: .web,
                installedPath: match?.path,
                bundleIdentifier: match?.bundleIdentifier,
                upgrade: .command(mas, ["upgrade", app.id])
            )
            item.applyUpdatePolicy(config: context.config)
            return item
        }
        return DetectorOutput(items: items, message: "\(items.count) App Store apps")
    }

    /// `mas list` and `mas outdated` both use: `123456789 App Name (1.2.3)`.
    static func parse(_ output: String) -> [StoreApp] {
        let pattern = #"^\s*(\d+)\s+(.+?)\s+\(([^)]+)\)\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = expression.firstMatch(in: text, range: range),
                let idRange = Range(match.range(at: 1), in: text),
                let nameRange = Range(match.range(at: 2), in: text),
                let versionRange = Range(match.range(at: 3), in: text)
            else { return nil }
            return StoreApp(
                id: String(text[idRange]),
                name: String(text[nameRange]),
                version: String(text[versionRange])
            )
        }
    }
}
