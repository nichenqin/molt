import Foundation

// MARK: - npm

public struct NpmGlobalDetector: OutdatedSourceDetector {
    public let source = SourceKind.npm

    public init() {}

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        guard let npm = context.environment.npm else {
            return .skipped("npm not installed")
        }
        let result = await context.runner.run(
            CommandSpec(
                executable: npm,
                arguments: ["outdated", "-g", "--json"],
                environment: ["npm_config_color": "false", "NO_COLOR": "1"]
            ),
            timeout: 30
        )
        let trimmed = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            if let failure = result.failureMessage, !trimmed.isEmpty {
                throw DetectorError.command(failure)
            }
            return DetectorOutput(message: "No global packages")
        }

        let entries = object.compactMap { name, value -> (String, [String: Any])? in
            guard let dictionary = value as? [String: Any] else { return nil }
            return (name, dictionary)
        }.sorted { $0.0 < $1.0 }

        guard !entries.isEmpty else {
            return DetectorOutput(message: "No outdated global packages")
        }
        let registry = NpmRegistry(http: context.http, cache: context.cache, force: context.forceRefresh)
        let infos = await Concurrency.map(entries, limit: 8) { entry in
            await registry.latest(package: entry.0)
        }

        var items: [OutdatedItem] = []
        for (index, entry) in entries.enumerated() {
            let (name, dictionary) = entry
            guard let latest = dictionary["latest"] as? String,
                let current = dictionary["current"] as? String,
                Version(latest) != nil
            else { continue }
            if let installed = Version(current), let candidate = Version(latest), !(candidate > installed) {
                continue
            }
            let info = infos[index]
            let repo = info?.repo
            items.append(
                OutdatedItem(
                    id: "npm:\(name)",
                    name: name,
                    source: .npm,
                    kind: .npmGlobal,
                    currentVersion: DetectorSupport.cleanVersion(current),
                    latestVersion: DetectorSupport.cleanVersion(latest),
                    summary: info?.summary,
                    homepage: info?.homepage ?? repo?.webURL,
                    repo: repo,
                    changelogURL: repo?.releasesURL ?? info?.homepage,
                    changelogKind: repo != nil ? .githubReleases : (info?.homepage != nil ? .web : .none),
                    installedPath: dictionary["location"] as? String,
                    upgrade: .command(npm, ["install", "-g", "\(name)@latest"])
                )
            )
        }
        return DetectorOutput(items: items, message: "\(items.count) global packages")
    }
}

// MARK: - pnpm

public struct PnpmGlobalDetector: OutdatedSourceDetector {
    public let source = SourceKind.pnpm

    public init() {}

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        guard let pnpm = context.environment.pnpm else {
            return .skipped("pnpm not installed")
        }
        let result = await context.runner.run(
            CommandSpec(executable: pnpm, arguments: ["list", "-g", "--depth=0", "--json"]),
            timeout: 25
        )
        if let error = DetectorSupport.failure(result) { throw error }
        let installed = Self.dependencies(from: result.stdout)
        guard !installed.isEmpty else {
            return DetectorOutput(message: "No global packages")
        }
        let registry = NpmRegistry(http: context.http, cache: context.cache, force: context.forceRefresh)
        let names = installed.keys.sorted()
        let infos = await Concurrency.map(names, limit: 8) { await registry.latest(package: $0) }

        var items: [OutdatedItem] = []
        for (index, name) in names.enumerated() {
            let current = installed[name] ?? "?"
            guard let info = infos[index], let installedVersion = Version(current),
                let latestVersion = Version(info.version),
                latestVersion > installedVersion
            else { continue }
            items.append(
                OutdatedItem(
                    id: "pnpm:\(name)",
                    name: name,
                    source: .pnpm,
                    kind: .pnpmGlobal,
                    currentVersion: DetectorSupport.cleanVersion(current),
                    latestVersion: DetectorSupport.cleanVersion(info.version),
                    summary: info.summary,
                    homepage: info.homepage ?? info.repo?.webURL,
                    repo: info.repo,
                    changelogURL: info.repo?.releasesURL ?? info.homepage,
                    changelogKind: info.repo != nil ? .githubReleases : (info.homepage != nil ? .web : .none),
                    upgrade: .command(pnpm, ["add", "-g", "\(name)@latest"])
                )
            )
        }
        return DetectorOutput(items: items, message: "\(items.count) global packages")
    }

    /// pnpm's modern output nests dependencies in a project object; older
    /// versions return the object directly. Accept both.
    static func dependencies(from data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        var roots: [[String: Any]] = []
        if let array = object as? [[String: Any]] {
            roots = array
        } else if let dictionary = object as? [String: Any] {
            roots = [dictionary]
        }
        for root in roots {
            if let dependencies = root["dependencies"] as? [String: Any] {
                var result: [String: String] = [:]
                for (name, value) in dependencies {
                    if let string = value as? String {
                        result[name] = string
                    } else if let dictionary = value as? [String: Any],
                        let version = dictionary["version"] as? String
                    {
                        result[name] = version
                    }
                }
                if !result.isEmpty { return result }
            }
        }
        return [:]
    }
}

// MARK: - bun

public struct BunGlobalDetector: OutdatedSourceDetector {
    public let source = SourceKind.bun

    public init() {}

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        guard let bun = context.environment.bun else {
            return .skipped("bun not installed")
        }
        let global = RemigePaths.bunGlobal
        let manifest = global.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifest),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dependencies = object["dependencies"] as? [String: String],
            !dependencies.isEmpty
        else {
            return DetectorOutput(message: "No global packages")
        }

        let names = dependencies.keys.sorted()
        let registry = NpmRegistry(http: context.http, cache: context.cache, force: context.forceRefresh)
        let infos = await Concurrency.map(names, limit: 8) { await registry.latest(package: $0) }
        let nodeModules = global.appendingPathComponent("node_modules")

        var items: [OutdatedItem] = []
        for (index, name) in names.enumerated() {
            guard let info = infos[index] else { continue }
            let packageJSON = nodeModules.appendingPathComponent(name).appendingPathComponent("package.json")
            guard let packageData = try? Data(contentsOf: packageJSON),
                let packageObject = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any],
                let current = packageObject["version"] as? String,
                let installedVersion = Version(current),
                let latestVersion = Version(info.version),
                latestVersion > installedVersion
            else { continue }
            items.append(
                OutdatedItem(
                    id: "bun:\(name)",
                    name: name,
                    source: .bun,
                    kind: .bunGlobal,
                    currentVersion: DetectorSupport.cleanVersion(current),
                    latestVersion: DetectorSupport.cleanVersion(info.version),
                    summary: info.summary,
                    homepage: info.homepage ?? info.repo?.webURL,
                    repo: info.repo,
                    changelogURL: info.repo?.releasesURL ?? info.homepage,
                    changelogKind: info.repo != nil ? .githubReleases : (info.homepage != nil ? .web : .none),
                    installedPath: nodeModules.appendingPathComponent(name).path,
                    upgrade: .command(bun, ["add", "-g", "\(name)@latest"])
                )
            )
        }
        return DetectorOutput(items: items, message: "\(items.count) global packages")
    }
}
