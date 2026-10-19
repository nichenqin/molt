import Foundation

/// Detects installed app updates from standard metadata and explicit catalogs:
/// Sparkle appcasts, Electron Builder manifests, and GitHub releases.
/// Homebrew retains ownership of cask-managed apps.
public struct AppUpdateDetector: OutdatedSourceDetector {
    public let source = SourceKind.app

    private let directories: [URL]?

    public init(directories: [URL]? = nil) {
        self.directories = directories
    }

    private struct CheckResult {
        var item: OutdatedItem?
        var detail: SourceReportDetail
    }

    private struct DocumentResult {
        var data: Data?
        var error: String?
    }

    private enum Resolution {
        case source(AppUpdateSource)
        case unsupported(String)
    }

    public func scan(_ context: ScanContext) async throws -> DetectorOutput {
        let apps = Self.discoveredApps(directories: directories)
        guard !apps.isEmpty else {
            return DetectorOutput(message: "No third-party apps found")
        }

        let resolver = LatestTagResolver(
            http: context.http,
            cache: context.cache,
            force: context.forceRefresh
        )
        let results: [CheckResult?] = await Concurrency.map(apps, limit: 6) { app -> CheckResult? in
            await self.check(app, resolver: resolver, context: context)
        }

        var items: [OutdatedItem] = []
        var details: [SourceReportDetail] = []
        for case let result? in results {
            if let item = result.item { items.append(item) }
            details.append(result.detail)
        }

        var message = "\(apps.count) apps"
        let unsupported = details.filter { $0.state == .unsupported }.count
        if unsupported > 0 { message += " · \(unsupported) without update source" }
        let unavailable = details.filter { $0.state == .unavailable }.count
        if unavailable > 0 { message += " · \(unavailable) sources unavailable" }
        return DetectorOutput(items: items, message: message, details: details)
    }

    // MARK: - Coverage

    private static func discoveredApps(directories: [URL]?) -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for app in AppScanner.scan(directories: directories) {
            // Bundle identity wins; an app copied elsewhere must not be checked twice.
            let key =
                app.bundleIdentifier.map { "id:\($0.lowercased())" }
                ?? "path:\(app.path.lowercased())"
            guard seen.insert(key).inserted else { continue }
            apps.append(app)
        }
        return apps
    }

    /// Priority: Sparkle metadata, explicit configuration, bundled catalog, then
    /// standard Electron Builder metadata. Display names are never consulted.
    private func resolution(for app: InstalledApp, config: MoltConfig) -> Resolution {
        if let feed = app.feedURL { return .source(.sparkle(feed)) }

        if let bundleID = app.bundleIdentifier,
            let entry = config.appUpdates.first(where: {
                $0.bundleIdentifier.caseInsensitiveCompare(bundleID) == .orderedSame
            })
        {
            guard let source = entry.source else {
                return .unsupported("Configured app update source is invalid")
            }
            return .source(source)
        }

        if let source = AppUpdateCatalog.source(for: app.bundleIdentifier) {
            return .source(source)
        }

        switch app.updateMetadata {
        case .supported(let source): return .source(source)
        case .unsupported(let reason): return .unsupported(reason)
        case nil: return .unsupported("No standard update source")
        }
    }

    private func check(
        _ app: InstalledApp,
        resolver: LatestTagResolver,
        context: ScanContext
    ) async -> CheckResult {
        if let token = context.environment.caskIndex.token(for: app.path) {
            return result(app, .managed, "Homebrew cask \(token)")
        }

        switch resolution(for: app, config: context.config) {
        case .unsupported(let reason):
            return result(app, .unsupported, reason)
        case .source(let source):
            guard let rawVersion = app.version, let installed = Version(rawVersion) else {
                return result(app, .unsupported, "Installed version is missing or not comparable")
            }
            switch source {
            case .sparkle(let feed):
                return await checkSparkle(
                    app, feed: feed, rawVersion: rawVersion, context: context)
            case .github(let repo):
                return await checkGitHub(
                    app, repo: repo, rawVersion: rawVersion, installed: installed,
                    resolver: resolver)
            case .electronGeneric(let baseURL):
                return await checkElectron(
                    app, baseURL: baseURL, rawVersion: rawVersion, installed: installed,
                    context: context)
            case .text(let url, let regex):
                return await checkText(
                    app, url: url, regex: regex, rawVersion: rawVersion, installed: installed,
                    resolver: resolver)
            }
        }
    }

    private func result(
        _ app: InstalledApp,
        _ state: SourceReportDetail.State,
        _ message: String? = nil,
        item: OutdatedItem? = nil
    ) -> CheckResult {
        CheckResult(
            item: item,
            detail: SourceReportDetail(
                id: "app:\(app.bundleIdentifier ?? app.path)",
                name: app.name,
                state: state,
                message: message
            )
        )
    }

    // MARK: - Sources

    private func checkSparkle(
        _ app: InstalledApp,
        feed: URL,
        rawVersion: String,
        context: ScanContext
    ) async -> CheckResult {
        let document = await loadDocument(feed, context: context) {
            (try? AppcastParser.parse($0)) != nil
        }
        guard let data = document.data else {
            return result(app, .unavailable, document.error ?? "Could not load appcast")
        }
        guard let feedItems = try? AppcastParser.parse(data) else {
            return result(app, .unavailable, "Could not parse appcast")
        }
        guard
            let latest = AppcastSelector.latest(
                items: feedItems,
                installedVersion: rawVersion,
                updateChannel: app.updateChannel,
                currentOS: context.environment.osVersion?.raw
            ),
            let latestVersion = latest.displayVersion
        else {
            return result(
                app, .current, "Up to date at \(DetectorSupport.cleanVersion(rawVersion))")
        }

        let plan: UpgradePlan
        if let download = latest.downloadURL, download.scheme?.lowercased() == "https" {
            plan = .open(download)
        } else if let notes = latest.releaseNotesURL, notes.scheme?.lowercased() == "https" {
            plan = .open(notes)
        } else {
            plan = .manual("Download the update and replace the app in Applications.")
        }

        let item = OutdatedItem(
            id: "app:\(app.bundleIdentifier ?? app.path)",
            name: app.name,
            source: .app,
            kind: .application,
            currentVersion: DetectorSupport.cleanVersion(rawVersion),
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
        return result(app, .checked, "\(item.currentVersion) → \(item.latestVersion)", item: item)
    }

    private func checkGitHub(
        _ app: InstalledApp,
        repo: RepoRef,
        rawVersion: String,
        installed: Version,
        resolver: LatestTagResolver
    ) async -> CheckResult {
        guard let latest = await resolver.resolve(.github(repo)),
            let latestVersion = Version(latest.version)
        else {
            return result(app, .unavailable, "Could not resolve the latest GitHub release")
        }
        guard latestVersion > installed else {
            return result(
                app, .current, "Up to date at \(DetectorSupport.cleanVersion(rawVersion))")
        }

        let item = OutdatedItem(
            id: "app:\(app.bundleIdentifier ?? app.path)",
            name: app.name,
            source: .app,
            kind: .application,
            currentVersion: DetectorSupport.cleanVersion(rawVersion),
            latestVersion: DetectorSupport.cleanVersion(latest.display),
            summary: nil,
            homepage: repo.webURL,
            repo: repo,
            changelogURL: repo.releasesURL,
            changelogKind: .githubReleases,
            installedPath: app.path,
            bundleIdentifier: app.bundleIdentifier,
            upgrade: .open(latest.url ?? repo.releasesURL)
        )
        return result(app, .checked, "\(item.currentVersion) → \(item.latestVersion)", item: item)
    }

    private func checkText(
        _ app: InstalledApp,
        url: URL,
        regex: String,
        rawVersion: String,
        installed: Version,
        resolver: LatestTagResolver
    ) async -> CheckResult {
        guard let latest = await resolver.resolve(.text(url, regex: regex)),
            let latestVersion = Version(latest.version)
        else {
            return result(app, .unavailable, "Could not read the configured latest version")
        }
        guard latestVersion > installed else {
            return result(
                app, .current, "Up to date at \(DetectorSupport.cleanVersion(rawVersion))")
        }

        let item = OutdatedItem(
            id: "app:\(app.bundleIdentifier ?? app.path)",
            name: app.name,
            source: .app,
            kind: .application,
            currentVersion: DetectorSupport.cleanVersion(rawVersion),
            latestVersion: DetectorSupport.cleanVersion(latest.display),
            summary: nil,
            homepage: nil,
            repo: nil,
            changelogURL: url,
            changelogKind: .web,
            installedPath: app.path,
            bundleIdentifier: app.bundleIdentifier,
            upgrade: .open(latest.url ?? url)
        )
        return result(app, .checked, "\(item.currentVersion) → \(item.latestVersion)", item: item)
    }

    private func checkElectron(
        _ app: InstalledApp,
        baseURL: URL,
        rawVersion: String,
        installed: Version,
        context: ScanContext
    ) async -> CheckResult {
        let manifestNames =
            context.architecture.lowercased() == "arm64"
            ? ["latest-mac-arm64.yml", "latest-mac.yml"]
            : ["latest-mac.yml"]
        var lastError = "Could not load the Electron update manifest"

        for name in manifestNames {
            let manifestURL = baseURL.appendingPathComponent(name)
            let document = await loadDocument(manifestURL, context: context) {
                ElectronUpdateManifestParser.parse(String(decoding: $0, as: UTF8.self)) != nil
            }
            guard let data = document.data else {
                lastError = document.error ?? "Could not load \(name)"
                continue
            }
            guard
                let manifest = ElectronUpdateManifestParser.parse(
                    String(decoding: data, as: UTF8.self)),
                let latestVersion = Version(manifest.version)
            else {
                lastError = "Could not parse \(name)"
                continue
            }
            guard latestVersion > installed else {
                return result(
                    app, .current, "Up to date at \(DetectorSupport.cleanVersion(rawVersion))")
            }
            guard
                let download = Self.downloadURL(
                    Self.selectDownload(manifest.downloads, architecture: context.architecture),
                    baseURL: baseURL
                )
            else {
                return result(
                    app, .unavailable, "Update manifest declares no compatible HTTPS download")
            }

            let item = OutdatedItem(
                id: "app:\(app.bundleIdentifier ?? app.path)",
                name: app.name,
                source: .app,
                kind: .application,
                currentVersion: DetectorSupport.cleanVersion(rawVersion),
                latestVersion: DetectorSupport.cleanVersion(manifest.version),
                summary: nil,
                homepage: nil,
                repo: nil,
                changelogURL: nil,
                changelogKind: .none,
                installedPath: app.path,
                bundleIdentifier: app.bundleIdentifier,
                upgrade: .open(download)
            )
            return result(
                app, .checked, "\(item.currentVersion) → \(item.latestVersion)", item: item)
        }
        return result(app, .unavailable, lastError)
    }

    // MARK: - Documents

    private func loadDocument(
        _ url: URL,
        context: ScanContext,
        isValid: (Data) -> Bool
    ) async -> DocumentResult {
        if !context.forceRefresh,
            let cached = await context.cache.readHTTP(url, maxAge: 900),
            isValid(cached.data)
        {
            return DocumentResult(data: cached.data)
        }

        var headers: [String: String] = [:]
        let old = await context.cache.readHTTPIgnoringAge(url)
        if let etag = old?.etag, !etag.isEmpty {
            headers["If-None-Match"] = etag
        }
        do {
            let response = try await context.http.get(
                url, headers: headers, timeout: 12, method: "GET")
            if response.status == 304, let old, isValid(old.data) {
                return DocumentResult(data: old.data)
            }
            guard response.isSuccess else {
                if let old, isValid(old.data) { return DocumentResult(data: old.data) }
                return DocumentResult(error: "HTTP \(response.status)")
            }
            await context.cache.writeHTTP(response, for: url)
            return DocumentResult(data: response.data)
        } catch {
            if let old, isValid(old.data) { return DocumentResult(data: old.data) }
            return DocumentResult(error: error.localizedDescription)
        }
    }

    private static func downloadURL(_ raw: String?, baseURL: URL) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let absolute = URL(string: raw), absolute.scheme != nil {
            guard absolute.scheme?.lowercased() == "https", let host = absolute.host,
                !host.isEmpty
            else { return nil }
            return absolute
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else { return nil }
        if !components.path.hasSuffix("/") { components.path += "/" }
        guard let directory = components.url,
            let resolved = URL(string: raw, relativeTo: directory)?.absoluteURL,
            resolved.scheme?.lowercased() == "https",
            let host = resolved.host,
            !host.isEmpty
        else { return nil }
        return resolved
    }

    private static func selectDownload(_ candidates: [String], architecture: String) -> String? {
        let normalizedArchitecture = architecture.lowercased()
        let arm64 = normalizedArchitecture.contains("arm64")
            || normalizedArchitecture.contains("aarch64")
        let preferred = arm64 ? ["arm64", "aarch64"] : ["x64", "amd64", "x86_64", "x86-64"]
        let incompatible = arm64 ? ["x64", "amd64", "x86_64", "x86-64"] : ["arm64", "aarch64"]
        func hasToken(_ value: String, _ tokens: [String]) -> Bool {
            let lowercased = value.lowercased()
            return tokens.contains { lowercased.contains($0) }
        }
        if let matching = candidates.first(where: { hasToken($0, preferred) }) {
            return matching
        }
        return candidates.first { !hasToken($0, incompatible) }
    }
}
