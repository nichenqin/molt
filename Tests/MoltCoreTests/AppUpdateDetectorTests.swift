import Foundation
import Testing

@testable import MoltCore

struct AppUpdateDetectorTests {
    private func makeApp(
        in root: URL,
        version: String,
        bundleID: String = "com.yetone.magpie",
        feed: String? = nil
    ) throws -> URL {
        // Discovery must use the bundle ID, not an assumed app filename or PATH executable.
        let app = root.appendingPathComponent("Renamed.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": "magpie",
            "CFBundleShortVersionString": version,
        ]
        info["SUFeedURL"] = feed
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        // Foundation preserves /var while directory enumeration returns /private/var on macOS.
        let canonical = try #require(realpath(app.path, nil))
        defer { free(canonical) }
        return URL(fileURLWithPath: String(cString: canonical))
    }

    private func context(root: URL, http: HTTPGetting, caskPath: String? = nil) -> ScanContext {
        let brew = caskPath.map { _ in
            BrewEnvironment(
                executable: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew",
                caskroom: root.appendingPathComponent("Caskroom")
            )
        }
        let entries =
            caskPath.map {
                [CaskIndex.Entry(token: "magpie", appNames: ["Renamed.app"], installedPaths: [$0])]
            } ?? []
        return ScanContext(
            runner: FakeRunner(output: ""), http: http,
            cache: DiskCache(directory: root.appendingPathComponent("cache")), config: .empty,
            environment: EnvironmentInfo(
                locator: ExecutableLocator(directories: []), brew: brew,
                caskIndex: CaskIndex(entries: entries), osVersion: Version("26.0")
            )
        )
    }

    private var releases: FakeHTTP {
        FakeHTTP { url, _, _, _ in
            guard url.absoluteString == "https://github.com/yetone/magpie-releases/releases/latest" else {
                return response("", status: 404, url: url)
            }
            return response(
                "", url: URL(string: "https://github.com/yetone/magpie-releases/releases/tag/v0.1.1290")!
            )
        }
    }

    @Test func discoversMagpieWithoutSparkleOrCLI() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(in: root, version: "0.1.1285")
        let result = try await AppUpdateDetector(directories: [root]).scan(context(root: root, http: releases))
        let item = try #require(result.items.first)
        #expect(result.items.count == 1)
        #expect(item.id == "app:com.yetone.magpie")
        #expect(item.source == .app)
        #expect(item.currentVersion == "0.1.1285")
        #expect(item.latestVersion == "0.1.1290")
        #expect(item.installedPath == app.path)
        #expect(item.repo?.slug == "yetone/magpie-releases")
        #expect(item.changelogKind == .githubReleases)
        #expect(item.upgrade.kind == .openURL)
        #expect(item.upgrade.url?.absoluteString == "https://github.com/yetone/magpie-releases/releases/tag/v0.1.1290")
    }

    @Test(arguments: ["0.1.1290", "0.1.1291", "development"])
    func ignoresCurrentNewerOrUnversionedApps(version: String) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(in: root, version: version)
        let result = try await AppUpdateDetector(directories: [root]).scan(context(root: root, http: releases))
        #expect(result.items.isEmpty)
    }

    @Test func doesNotGuessUpdateSourceFromDisplayName() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(in: root, version: "0.1.1285", bundleID: "org.unrelated.magpie")
        let result = try await AppUpdateDetector(directories: [root]).scan(context(root: root, http: releases))
        #expect(result.items.isEmpty)
    }

    @Test func keepsCaskOwnershipForCatalogApp() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(in: root, version: "0.1.1285")
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: releases, caskPath: app.path)
        )
        let item = try #require(result.items.first)
        #expect(item.upgrade == .command("/opt/homebrew/bin/brew", ["upgrade", "--cask", "magpie"]))
    }

    @Test func unavailableReleaseSourceDoesNotHideSparkleUpdates() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(in: root, version: "0.1.1285")
        let vendor = root.appendingPathComponent("Vendor")
        _ = try makeApp(
            in: vendor, version: "1.0", bundleID: "org.example.sparkle",
            feed: "https://example.com/appcast.xml"
        )
        let http = FakeHTTP { url, _, _, _ in
            guard url.host == "example.com" else { return response("", status: 503, url: url) }
            return response(
                """
                <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
                <sparkle:version>2.0</sparkle:version>
                <enclosure url="https://example.com/app.zip" />
                </item></channel></rss>
                """, url: url)
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(context(root: root, http: http))
        #expect(result.items.map(\.id) == ["app:org.example.sparkle"])
        #expect(result.items.first?.latestVersion == "2.0")
    }
}
