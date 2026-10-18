import Foundation

public struct NpmPackageInfo: Codable, Hashable, Sendable {
    public var name: String
    public var version: String
    public var summary: String?
    public var homepage: URL?
    public var repo: RepoRef?

    public init(
        name: String,
        version: String,
        summary: String? = nil,
        homepage: URL? = nil,
        repo: RepoRef? = nil
    ) {
        self.name = name
        self.version = version
        self.summary = summary
        self.homepage = homepage
        self.repo = repo
    }
}

public struct NpmRegistry: Sendable {
    private let http: HTTPGetting
    private let cache: DiskCache
    private let force: Bool

    public init(http: HTTPGetting, cache: DiskCache, force: Bool = false) {
        self.http = http
        self.cache = cache
        self.force = force
    }

    public func latest(package: String) async -> NpmPackageInfo? {
        let key = "npm:latest:\(package)"
        if !force, let cached = await cache.read(NpmPackageInfo.self, key: key, maxAge: 6 * 3600) {
            return cached
        }
        guard let url = Self.latestURL(package: package),
            let response = try? await http.get(url, timeout: 12),
            response.isSuccess,
            let object = response.jsonObject() as? [String: Any],
            let version = object["version"] as? String,
            Version(version) != nil
        else {
            return nil
        }
        let repo =
            RepoRef(urlLike: Self.repositoryString(object["repository"]))
            ?? RepoRef(urlLike: object["homepage"] as? String)
        let info = NpmPackageInfo(
            name: object["name"] as? String ?? package,
            version: version,
            summary: object["description"] as? String,
            homepage: (object["homepage"] as? String).flatMap(URL.init(string:)),
            repo: repo
        )
        await cache.write(info, key: key)
        return info
    }

    public static func latestURL(package: String) -> URL? {
        let encoded = package.replacingOccurrences(of: "/", with: "%2F")
        return URL(string: "https://registry.npmjs.org/\(encoded)/latest")
    }

    private static func repositoryString(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let object = value as? [String: Any] {
            if let url = object["url"] as? String { return url }
        }
        return nil
    }
}
