import Foundation

/// Detects installed apps through Sparkle feeds or explicitly cataloged release repositories.
/// Homebrew retains ownership of cask-managed apps.
public struct AppUpdateDetector: OutdatedSourceDetector {
    public let source = SourceKind.app

    private let directories: [URL]?

    // Apps without a standard update feed need an explicit, verified release source.
    // Match bundle identity, never the display name or app filename.
    private static let releaseRepos: [String: RepoRef] = [
        "com.yetone.magpie": RepoRef(owner: "yetone", name: "magpie-releases")
    ]

    public init(directories: [URL]? = nil) {
        self.directories = directories
    }

    private struct FeedResult {
        var items: [AppcastItem]?
        var error: String?
    }

    private struct ReleaseResult {
        var item: OutdatedItem?
        var unavailable = false
    }

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        var seenBundles = Set<String>()
        let apps = AppScanner.scan(directories: directories).filter { app in
            guard app.feedURL != nil || Self.releaseRepos[app.bundleIdentifier ?? ""] != nil else {
                return false
            }
            let key = app.bundleIdentifier ?? app.path
            return seenBundles.insert(key).inserted
        }
        guard !apps.isEmpty else {
            return DetectorOutput(message: "No supported apps found")
        }

        let sparkleApps = apps.filter { $0.feedURL != nil }
        let releaseApps = apps.filter { $0.feedURL == nil }
        let resolver = LatestTagResolver(http: context.http, cache: context.cache, force: context.forceRefresh)
        async let releaseResults = Concurrency.map(releaseApps, limit: 6) { app in
            await self.checkRelease(app, resolver: resolver, context: context)
        }
        let grouped = Dictionary(grouping: sparkleApps) { $0.feedURL! }
        let feeds = grouped.keys.sorted { $0.absoluteString < $1.absoluteString }
        let results = await Concurrency.map(feeds, limit: 6) { url in
            await self.loadFeed(url, context: context)
        }
        var byFeed: [URL: [AppcastItem]] = [:]
        var feedErrors = 0
        for (index, url) in feeds.enumerated() {
            if let items = results[index]?.items {
                byFeed[url] = items
            } else {
                feedErrors += 1
            }
        }

        var items: [OutdatedItem] = []
        for app in sparkleApps {
            guard let feed = app.feedURL, let feedItems = byFeed[feed],
                let installedVersion = app.version,
                let latest = AppcastSelector.latest(
                    items: feedItems,
                    installedVersion: installedVersion,
                    updateChannel: app.updateChannel,
                    currentOS: context.environment.osVersion?.raw
                ),
                let latestVersion = latest.displayVersion
            else { continue }

            let token = context.environment.caskIndex.token(for: app.path)
            let plan: UpgradePlan
            if let brew = context.environment.brew, let token {
                plan = .command(brew.executable, ["upgrade", "--cask", token])
            } else if let download = latest.downloadURL, download.scheme == "https" {
                plan = .open(download)
            } else if let notes = latest.releaseNotesURL, notes.scheme == "https" {
                plan = .open(notes)
            } else {
                plan = .manual("Download the update and replace the app in Applications.")
            }

            items.append(
                OutdatedItem(
                    id: "app:\(app.bundleIdentifier ?? app.path)",
                    name: app.name,
                    source: .app,
                    kind: .application,
                    currentVersion: DetectorSupport.cleanVersion(installedVersion),
                    latestVersion: DetectorSupport.cleanVersion(latestVersion),
                    summary: nil,
                    homepage: nil,
                    repo: nil,
                    changelogURL: feed,
                    changelogKind: .appcast,
                    installedPath: app.path,
                    bundleIdentifier: app.bundleIdentifier,
                    upgrade: plan
                )
            )
        }

        for result in await releaseResults {
            if let item = result?.item { items.append(item) }
            if result?.unavailable == true { feedErrors += 1 }
        }

        var message = "\(apps.count) apps"
        if feedErrors > 0 { message += " · \(feedErrors) update sources unavailable" }
        return DetectorOutput(items: items, message: message)
    }

    private func checkRelease(
        _ app: InstalledApp, resolver: LatestTagResolver, context: ScanContext
    ) async -> ReleaseResult {
        guard let bundleID = app.bundleIdentifier, let repo = Self.releaseRepos[bundleID],
            let installedVersion = app.version, let current = Version(installedVersion)
        else { return ReleaseResult() }
        guard let latest = await resolver.resolve(.github(repo)) else {
            return ReleaseResult(unavailable: true)
        }
        guard let version = Version(latest.version), version > current else { return ReleaseResult() }

        let plan: UpgradePlan
        if let brew = context.environment.brew,
            let token = context.environment.caskIndex.token(for: app.path)
        {
            plan = .command(brew.executable, ["upgrade", "--cask", token])
        } else {
            plan = .open(latest.url ?? repo.releasesURL)
        }
        return ReleaseResult(
            item: OutdatedItem(
                id: "app:\(bundleID)",
                name: app.name,
                source: .app,
                kind: .application,
                currentVersion: DetectorSupport.cleanVersion(installedVersion),
                latestVersion: latest.display,
                homepage: repo.webURL,
                repo: repo,
                changelogURL: repo.releasesURL,
                changelogKind: .githubReleases,
                installedPath: app.path,
                bundleIdentifier: bundleID,
                upgrade: plan
            ))
    }

    private func loadFeed(_ url: URL, context: ScanContext) async -> FeedResult {
        if !context.forceRefresh,
            let cached = await context.cache.readHTTP(url, maxAge: 900)
        {
            if let items = try? AppcastParser.parse(cached.data) {
                return FeedResult(items: items)
            }
        }

        var headers: [String: String] = [:]
        let old = await context.cache.readHTTPIgnoringAge(url)
        if let etag = old?.etag, !etag.isEmpty {
            headers["If-None-Match"] = etag
        }
        do {
            let response = try await context.http.get(url, headers: headers, timeout: 12, method: "GET")
            if response.status == 304, let old {
                return FeedResult(items: try? AppcastParser.parse(old.data))
            }
            guard response.isSuccess else {
                return FeedResult(error: "HTTP \(response.status)")
            }
            await context.cache.writeHTTP(response, for: url)
            let items = try AppcastParser.parse(response.data)
            return FeedResult(items: items)
        } catch {
            if let old, let items = try? AppcastParser.parse(old.data) {
                return FeedResult(items: items, error: error.localizedDescription)
            }
            return FeedResult(error: error.localizedDescription)
        }
    }
}
