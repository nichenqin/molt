import Foundation

public struct LatestTag: Codable, Hashable, Sendable {
    public var version: String
    public var display: String
    public var url: URL?
    public var fetchedAt: Date

    public init(version: String, display: String, url: URL?, fetchedAt: Date = Date()) {
        self.version = version
        self.display = display
        self.url = url
        self.fetchedAt = fetchedAt
    }
}

public struct LatestTagResolver: Sendable {
    private let http: HTTPGetting
    private let cache: DiskCache
    private let force: Bool

    public init(http: HTTPGetting, cache: DiskCache, force: Bool = false) {
        self.http = http
        self.cache = cache
        self.force = force
    }

    public func resolve(_ source: LatestTagSource) async -> LatestTag? {
        let key = Self.cacheKey(source)
        if !force, let cached = await cache.read(LatestTag.self, key: key, maxAge: 6 * 3600) {
            return cached
        }
        let tag: LatestTag?
        switch source {
        case .github(let repo):
            tag = await resolveGitHub(repo)
        case .text(let url, let regex):
            tag = await resolveText(url, regex: regex)
        }
        if let tag {
            await cache.write(tag, key: key)
        }
        return tag
    }

    private func resolveGitHub(_ repo: RepoRef) async -> LatestTag? {
        for method in ["HEAD", "GET"] {
            guard
                let response = try? await http.get(
                    repo.latestReleaseURL,
                    headers: [:],
                    timeout: 12,
                    method: method
                )
            else { continue }
            guard response.isSuccess else { continue }
            let components = response.finalURL.pathComponents
            guard let index = components.firstIndex(of: "tag"), index + 1 < components.count else {
                continue
            }
            let rawTag = components[index + 1].removingPercentEncoding ?? components[index + 1]
            guard !rawTag.isEmpty else { continue }
            let display = Self.cleanTag(rawTag)
            guard Version(display) != nil else { continue }
            return LatestTag(
                version: display,
                display: display,
                url: URL(string: "https://github.com/\(repo.slug)/releases/tag/\(rawTag)")
            )
        }
        return nil
    }

    private func resolveText(_ url: URL, regex: String) async -> LatestTag? {
        guard let response = try? await http.get(url, timeout: 12), response.isSuccess else {
            return nil
        }
        let text = response.text
        guard let expression = try? NSRegularExpression(pattern: regex) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }
        let capture = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard capture.location != NSNotFound, let swiftRange = Range(capture, in: text) else {
            return nil
        }
        let raw = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let display = Self.cleanTag(raw)
        guard Version(display) != nil else { return nil }
        return LatestTag(version: display, display: display, url: url)
    }

    private static func cleanTag(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        return value
    }

    private static func cacheKey(_ source: LatestTagSource) -> String {
        switch source {
        case .github(let repo): "latest:github:\(repo.slug)"
        case .text(let url, let regex): "latest:text:\(url.absoluteString):\(regex)"
        }
    }
}
