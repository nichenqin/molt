import Foundation

/// Finds updates for standalone binaries installed by curl scripts, tarballs or
/// installers. Homebrew/npm-owned binaries are skipped by path, so there are no
/// duplicate rows. Custom tools from the config use the same machinery.
public struct CLIToolDetector: OutdatedSourceDetector {
    public let source = SourceKind.cli

    public init() {}

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        let resolver = LatestTagResolver(
            http: context.http,
            cache: context.cache,
            force: context.forceRefresh
        )
        let debug = ProcessInfo.processInfo.environment["REMIGE_DEBUG"] != nil
        var installed: [(tool: CLITool, path: String, version: String)] = []
        for tool in ToolCatalog.tools {
            guard let path = firstExecutable(for: tool, locator: context.environment.locator) else {
                if debug {
                    FileHandle.standardError.write(Data("remige[cli]: \(tool.name) not on PATH\n".utf8))
                }
                continue
            }
            if context.environment.isManagedBinary(path) {
                if debug {
                    FileHandle.standardError.write(Data("remige[cli]: \(tool.name) managed at \(path)\n".utf8))
                }
                continue
            }
            guard
                let version = await version(
                    tool: tool,
                    executable: path,
                    runner: context.runner
                )
            else {
                if debug {
                    FileHandle.standardError.write(Data("remige[cli]: \(tool.name) version unknown\n".utf8))
                }
                continue
            }
            installed.append((tool, path, version))
        }

        let results = await Concurrency.map(installed, limit: 8) { entry -> OutdatedItem? in
            let latest = await resolver.resolve(entry.tool.latest)
            if debug {
                FileHandle.standardError.write(
                    Data(
                        "remige[cli]: \(entry.tool.name) at \(entry.version), latest=\(latest?.display ?? "nil")\n".utf8
                    )
                )
            }
            guard let latest,
                let currentVersion = Version(entry.version),
                let latestVersion = Version(latest.version),
                latestVersion > currentVersion
            else { return nil }
            let repo: RepoRef?
            if case .github(let value) = entry.tool.latest { repo = value } else { repo = nil }
            let plan: UpgradePlan
            if let args = entry.tool.upgradeArguments, let first = args.first {
                plan = .command(entry.path, Array(args.dropFirst()))
                _ = first
            } else if let url = latest.url ?? repo?.releasesURL ?? entry.tool.homepage {
                plan = .open(url)
            } else {
                plan = .manual("Install the newest release manually.")
            }
            return OutdatedItem(
                id: "cli:\(entry.tool.name)",
                name: entry.tool.name,
                displayName: entry.tool.displayName,
                source: .cli,
                kind: .binary,
                currentVersion: DetectorSupport.cleanVersion(entry.version),
                latestVersion: latest.display,
                summary: entry.tool.summary,
                homepage: entry.tool.homepage,
                repo: repo,
                changelogURL: repo?.releasesURL ?? latest.url ?? entry.tool.homepage,
                changelogKind: repo != nil
                    ? .githubReleases : ((latest.url ?? entry.tool.homepage) != nil ? .web : .none),
                installedPath: entry.path,
                upgrade: plan
            )
        }.compactMap { $0 }

        var message = "\(installed.count) standalone tools checked"
        if installed.isEmpty { message = "No standalone tools found" }
        return DetectorOutput(items: results, message: message)
    }

    private func firstExecutable(for tool: CLITool, locator: ExecutableLocator) -> String? {
        for name in tool.binaryNames {
            if let path = locator.find(name) { return path }
        }
        return nil
    }

    private func version(
        tool: CLITool,
        executable: String,
        runner: CommandRunning
    ) async -> String? {
        let result = await runner.run(
            CommandSpec(executable: executable, arguments: tool.versionArguments),
            timeout: 3
        )
        let output = result.stdoutText + "\n" + result.stderrText
        guard let parsed = Version.extract(from: output, regex: tool.versionRegex) else {
            return nil
        }
        return parsed.raw
    }
}

// MARK: - Custom tools

public struct CustomToolDetector: OutdatedSourceDetector {
    public let source = SourceKind.custom

    public init() {}

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        guard !context.config.customTools.isEmpty else {
            return .skipped("No custom tools configured")
        }
        let resolver = LatestTagResolver(
            http: context.http,
            cache: context.cache,
            force: context.forceRefresh
        )
        var drafts: [(config: CustomToolConfig, path: String, version: String, latest: LatestTag)] = []

        for config in context.config.customTools {
            let path: String?
            if let explicit = config.path, !explicit.isEmpty {
                path = FileManager.default.isExecutableFile(atPath: explicit) ? explicit : nil
            } else {
                path = context.environment.locator.find(config.name)
            }
            guard let path else { continue }
            if config.path == nil, context.environment.isManagedBinary(path) { continue }

            let args = config.versionArgs ?? ["--version"]
            let result = await context.runner.run(
                CommandSpec(executable: path, arguments: args),
                timeout: 4
            )
            let output = result.stdoutText + "\n" + result.stderrText
            guard let installed = Version.extract(from: output, regex: config.versionRegex) else {
                continue
            }

            let source: LatestTagSource?
            if let github = config.github, let repo = RepoRef(urlLike: github) {
                source = .github(repo)
            } else if let raw = config.latestURL, let url = URL(string: raw) {
                source = .text(url, regex: config.latestRegex ?? #"v?(\d+(?:[._]\d+)+)"#)
            } else {
                source = nil
            }
            guard let source, let latest = await resolver.resolve(source) else { continue }
            guard let latestVersion = Version(latest.version), latestVersion > installed else { continue }
            drafts.append((config, path, installed.raw, latest))
        }

        let items = drafts.map { draft -> OutdatedItem in
            let repo: RepoRef?
            if let github = draft.config.github { repo = RepoRef(urlLike: github) } else { repo = nil }
            let homepage = draft.config.homepage.flatMap(URL.init(string:))
            let plan: UpgradePlan
            if let args = draft.config.upgradeArgs, !args.isEmpty {
                plan = .command(draft.path, Array(args.dropFirst()))
            } else if let url = draft.latest.url ?? repo?.releasesURL ?? homepage {
                plan = .open(url)
            } else {
                plan = .manual("Update this tool with its own installer.")
            }
            return OutdatedItem(
                id: "custom:\(draft.config.name)",
                name: draft.config.name,
                displayName: draft.config.name,
                source: .custom,
                kind: .custom,
                currentVersion: DetectorSupport.cleanVersion(draft.version),
                latestVersion: draft.latest.display,
                summary: draft.config.summary,
                homepage: homepage,
                repo: repo,
                changelogURL: repo?.releasesURL ?? draft.latest.url ?? homepage,
                changelogKind: repo != nil ? .githubReleases : ((draft.latest.url ?? homepage) != nil ? .web : .none),
                installedPath: draft.path,
                upgrade: plan
            )
        }
        return DetectorOutput(
            items: items,
            message: "\(context.config.customTools.count) custom tools configured"
        )
    }
}
