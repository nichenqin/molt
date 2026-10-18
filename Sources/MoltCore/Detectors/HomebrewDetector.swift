import Foundation

public struct HomebrewDetector: OutdatedSourceDetector {
    public let source = SourceKind.homebrew

    public init() {}

    private struct BrewMeta: Codable, Sendable {
        var summary: String?
        var homepage: String?
        var repo: RepoRef?
    }

    private struct Package {
        var name: String
        var current: String
        var installed: [String]
        var pinned: Bool
    }

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        guard let brew = context.environment.brew else {
            return .skipped("Homebrew not installed")
        }
        let command = CommandSpec(
            executable: brew.executable,
            arguments: ["outdated", "--json=v2", "--greedy"],
            environment: [
                "HOMEBREW_NO_AUTO_UPDATE": "1",
                "HOMEBREW_NO_INSTALL_CLEANUP": "1",
                "HOMEBREW_NO_ANALYTICS": "1",
                "HOMEBREW_NO_ENV_HINTS": "1",
                "HOMEBREW_NO_COLOR": "1",
            ]
        )
        let result = await context.runner.run(command, timeout: 45)
        if let error = DetectorSupport.failure(result) { throw error }
        guard let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            if result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return DetectorOutput(message: "No outdated packages")
            }
            throw DetectorError.parse("brew outdated did not return JSON")
        }

        let formulae = Self.packages(from: object["formulae"])
        let casks = Self.packages(from: object["casks"])
        if formulae.isEmpty && casks.isEmpty {
            return DetectorOutput(message: "Everything is current")
        }

        let formulaItems = await buildItems(
            packages: formulae,
            isCask: false,
            context: context,
            brew: brew
        )
        let caskItems = await buildItems(
            packages: casks,
            isCask: true,
            context: context,
            brew: brew
        )
        let items = formulaItems + caskItems
        var parts: [String] = []
        if !formulae.isEmpty { parts.append("\(formulae.count) formulae") }
        if !casks.isEmpty { parts.append("\(casks.count) casks") }
        return DetectorOutput(items: items, message: parts.joined(separator: " · "))
    }

    private func buildItems(
        packages: [Package],
        isCask: Bool,
        context: ScanContext,
        brew: BrewEnvironment
    ) async -> [OutdatedItem] {
        let metadata = await Concurrency.map(packages, limit: 8) { package in
            await self.metadata(for: package.name, isCask: isCask, context: context)
        }
        return packages.enumerated().map { index, package in
            let meta = metadata[index]
            let repo = meta?.repo
            let homepage = meta?.homepage.flatMap(URL.init(string:))
            let appPath = isCask ? context.environment.caskIndex.installedPath(for: package.name) : nil
            let changelogKind: ChangelogKind = repo != nil ? .githubReleases : (homepage != nil ? .web : .none)
            return OutdatedItem(
                id: "brew:\(isCask ? "cask" : "formula"):\(package.name)",
                name: package.name,
                source: .homebrew,
                kind: isCask ? .cask : .formula,
                currentVersion: package.installed.first ?? "?",
                latestVersion: package.current,
                summary: meta?.summary,
                homepage: homepage,
                repo: repo,
                changelogURL: repo?.releasesURL ?? homepage,
                changelogKind: changelogKind,
                installedPath: appPath,
                pinned: package.pinned,
                upgrade: .command(
                    brew.executable,
                    isCask
                        ? ["upgrade", "--cask", package.name]
                        : ["upgrade", "--formula", package.name]
                )
            )
        }
    }

    private func metadata(
        for name: String,
        isCask: Bool,
        context: ScanContext
    ) async -> BrewMeta? {
        let key = "brewmeta:\(isCask ? "cask" : "formula"):\(name)"
        if !context.forceRefresh,
            let cached = await context.cache.read(BrewMeta.self, key: key, maxAge: 7 * 24 * 3600)
        {
            return cached
        }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let urlString = "https://formulae.brew.sh/api/\(isCask ? "cask" : "formula")/\(encoded).json"
        guard let url = URL(string: urlString),
            let response = try? await context.http.get(url, timeout: 12),
            response.isSuccess,
            let object = response.jsonObject() as? [String: Any]
        else {
            return nil
        }

        var homepage = object["homepage"] as? String
        var repo = RepoRef(urlLike: homepage)
        if repo == nil {
            if isCask {
                repo = RepoRef(urlLike: object["url"] as? String)
            } else if let urls = object["urls"] as? [String: Any],
                let stable = urls["stable"] as? [String: Any],
                let raw = stable["url"] as? String
            {
                repo = RepoRef(urlLike: raw)
            }
        }
        if homepage == nil, let repo { homepage = repo.webURL.absoluteString }
        let meta = BrewMeta(summary: object["desc"] as? String, homepage: homepage, repo: repo)
        await context.cache.write(meta, key: key)
        return meta
    }

    private static func packages(from value: Any?) -> [Package] {
        guard let list = value as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let current =
                (entry["current_version"] as? String)
                ?? entry["current_version"].map { String(describing: $0) }
                ?? "?"
            let installed: [String]
            if let values = entry["installed_versions"] as? [String] {
                installed = values
            } else if let value = entry["installed_versions"] as? String {
                installed = [value]
            } else {
                installed = []
            }
            return Package(
                name: name,
                current: current,
                installed: installed,
                pinned: entry["pinned"] as? Bool ?? false
            )
        }
    }
}
