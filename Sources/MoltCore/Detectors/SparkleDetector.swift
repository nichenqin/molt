import Foundation

/// Detects updates for apps that ship Sparkle appcasts. Covers DMG installs
/// that Homebrew never touched, plus casks via the Caskroom map.
public struct SparkleDetector: OutdatedSourceDetector {
    public let source = SourceKind.app

    public init() {}

    private struct FeedResult {
        var items: [AppcastItem]?
        var error: String?
    }

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        var seenBundles = Set<String>()
        let apps = AppScanner.scan().filter { app in
            guard let feed = app.feedURL, feed.scheme == "https" else { return false }
            let key = app.bundleIdentifier ?? app.path
            return seenBundles.insert(key).inserted
        }
        guard !apps.isEmpty else {
            return DetectorOutput(message: "No Sparkle apps found")
        }

        let grouped = Dictionary(grouping: apps) { $0.feedURL! }
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
        for app in apps {
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

        var message = "\(apps.count) apps"
        if feedErrors > 0 { message += " · \(feedErrors) feeds unavailable" }
        return DetectorOutput(items: items, message: message)
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
