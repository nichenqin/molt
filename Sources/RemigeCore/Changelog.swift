import Foundation

public struct ChangelogResult: Sendable {
    public var releases: [ChangelogRelease]
    public var webURL: URL?

    public init(releases: [ChangelogRelease], webURL: URL? = nil) {
        self.releases = releases
        self.webURL = webURL
    }
}

public struct ChangelogService: Sendable {
    private let http: HTTPGetting
    private let cache: DiskCache
    private let force: Bool

    public init(http: HTTPGetting, cache: DiskCache, force: Bool = false) {
        self.http = http
        self.cache = cache
        self.force = force
    }

    public func changelog(for item: OutdatedItem, limit: Int = 6) async -> ChangelogResult {
        switch item.changelogKind {
        case .githubReleases:
            guard let repo = item.repo else {
                return ChangelogResult(releases: [], webURL: item.changelogURL ?? item.homepage)
            }
            return await githubChangelog(repo: repo, limit: limit, fallback: item.changelogURL)
        case .appcast:
            guard let url = item.changelogURL else { return ChangelogResult(releases: []) }
            return await appcastChangelog(url: url, limit: limit)
        case .web:
            return ChangelogResult(releases: [], webURL: item.changelogURL ?? item.homepage)
        case .none:
            return ChangelogResult(releases: [], webURL: item.homepage)
        }
    }

    // MARK: GitHub

    private func githubChangelog(
        repo: RepoRef,
        limit: Int,
        fallback: URL?
    ) async -> ChangelogResult {
        let key = "changelog:github:\(repo.slug)"
        if !force, let cached = await cache.read([ChangelogRelease].self, key: key, maxAge: 6 * 3600) {
            return ChangelogResult(releases: Array(cached.prefix(limit)), webURL: repo.releasesURL)
        }
        guard let response = try? await http.get(repo.atomURL, timeout: 15), response.isSuccess else {
            return ChangelogResult(releases: [], webURL: fallback ?? repo.releasesURL)
        }
        let releases = AtomFeedParser.parse(response.data)
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        await cache.write(releases, key: key)
        return ChangelogResult(releases: Array(releases.prefix(limit)), webURL: repo.releasesURL)
    }

    // MARK: Sparkle

    private func appcastChangelog(url: URL, limit: Int) async -> ChangelogResult {
        let key = "changelog:appcast:\(url.absoluteString)"
        if !force, let cached = await cache.read([ChangelogRelease].self, key: key, maxAge: 6 * 3600) {
            return ChangelogResult(releases: Array(cached.prefix(limit)), webURL: url)
        }
        guard let response = try? await http.get(url, timeout: 15), response.isSuccess,
            let items = try? AppcastParser.parse(response.data), !items.isEmpty
        else {
            return ChangelogResult(releases: [], webURL: url)
        }

        var byVersion: [String: ChangelogRelease] = [:]
        for item in items {
            guard let version = item.displayVersion else { continue }
            let release = ChangelogRelease(
                id: "\(url.absoluteString)#\(version)",
                version: version,
                title: item.title ?? version,
                publishedAt: item.publishDate,
                url: item.releaseNotesURL ?? item.downloadURL,
                bodyHTML: item.notesHTML ?? ""
            )
            // Delta entries repeat a version; keep the richest one.
            if let existing = byVersion[version],
                existing.bodyHTML.count >= release.bodyHTML.count
            {
                continue
            }
            byVersion[version] = release
        }
        var releases = Array(byVersion.values)
        releases.sort {
            if let left = $0.publishedAt, let right = $1.publishedAt { return left > right }
            if let left = Version($0.version), let right = Version($1.version) { return left > right }
            return $0.version > $1.version
        }

        // Some feeds keep notes at releaseNotesLink instead of inline. Fetch the
        // newest few so the pane is useful without a click.
        let missing = releases.prefix(3).filter { $0.bodyHTML.trimmingCharacters(in: .whitespaces).isEmpty }
        let fetched = await Concurrency.map(Array(missing), limit: 3) { release -> ChangelogRelease? in
            guard let link = release.url,
                let response = try? await self.http.get(link, timeout: 12),
                response.isSuccess
            else { return nil }
            var updated = release
            updated.bodyHTML = String(response.text.prefix(60_000))
            return updated
        }
        for release in fetched.compactMap({ $0 }) {
            byVersion[release.version] = release
        }
        releases = Array(byVersion.values)
        releases.sort {
            if let left = $0.publishedAt, let right = $1.publishedAt { return left > right }
            if let left = Version($0.version), let right = Version($1.version) { return left > right }
            return $0.version > $1.version
        }

        await cache.write(releases, key: key)
        return ChangelogResult(releases: Array(releases.prefix(limit)), webURL: url)
    }
}

// MARK: - Atom

/// Parser for GitHub's releases Atom feed. GitHub embeds release-note HTML in
/// `<content type="html">`, so no API token or rate-limit budget is needed.
public final class AtomFeedParser: NSObject, XMLParserDelegate {
    private var entries: [ChangelogRelease] = []
    private var inEntry = false
    private var inContent = false
    private var content = ""
    private var currentID: String?
    private var title = ""
    private var updated: Date?
    private var link: URL?
    private var element = ""

    public static func parse(_ data: Data) -> [ChangelogRelease] {
        let delegate = AtomFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        element = elementName
        if elementName == "entry" {
            inEntry = true
            content = ""
            currentID = nil
            title = ""
            updated = nil
            link = nil
        } else if inEntry && elementName == "content" {
            inContent = true
            content = ""
        } else if inEntry && elementName == "link" {
            let rel = attributeDict["rel"] ?? "alternate"
            if rel == "alternate", let raw = attributeDict["href"], let url = URL(string: raw) {
                link = url
            }
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        if inContent {
            content += string
            return
        }
        switch element {
        case "title": title += string
        case "id": currentID = (currentID ?? "") + string
        case "updated", "published":
            updated = updated ?? Self.date(from: string)
        default: break
        }
    }

    public func parser(_ parser: XMLParser, foundCDATA data: Data) {
        guard inEntry, inContent else { return }
        content += String(decoding: data, as: UTF8.self)
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "content" { inContent = false }
        guard elementName == "entry", inEntry else { return }
        inEntry = false
        let cleanTitle = Self.clean(title)
        guard !cleanTitle.isEmpty || !content.isEmpty else { return }
        let version = Self.version(from: cleanTitle)
        entries.append(
            ChangelogRelease(
                id: currentID?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? link?.absoluteString
                    ?? UUID().uuidString,
                version: version,
                title: cleanTitle.isEmpty ? version : cleanTitle,
                publishedAt: updated,
                url: link,
                bodyHTML: String(content.prefix(60_000))
            )
        )
        content = ""
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func version(from title: String) -> String {
        var value = title
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        return value.split(whereSeparator: { $0 == " " || $0 == "(" }).first.map(String.init) ?? value
    }

    private static func date(from value: String) -> Date? {
        ISO8601DateFormatter().date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
