import Foundation
import Testing

@testable import RemigeCore

struct AppUpdateDetectorTests {
    private func makeApp(
        in root: URL,
        fileName: String = "Renamed.app",
        version: String,
        bundleID: String = "com.yetone.magpie",
        name: String = "magpie",
        feed: String? = nil,
        updateYAML: String? = nil
    ) throws -> URL {
        // Discovery must use the bundle ID, not an assumed app filename or PATH executable.
        let app = root.appendingPathComponent(fileName)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": version,
        ]
        info["SUFeedURL"] = feed
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        if let updateYAML {
            let resources = contents.appendingPathComponent("Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try updateYAML.write(
                to: resources.appendingPathComponent("app-update.yml"),
                atomically: true,
                encoding: .utf8
            )
        }
        // Foundation preserves /var while directory enumeration returns /private/var on macOS.
        let canonical = try #require(realpath(app.path, nil))
        defer { free(canonical) }
        return URL(fileURLWithPath: String(cString: canonical))
    }

    private func context(
        root: URL,
        http: HTTPGetting,
        caskPath: String? = nil,
        config: RemigeConfig = .empty,
        architecture: String = "arm64"
    ) -> ScanContext {
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
            cache: DiskCache(directory: root.appendingPathComponent("cache")), config: config,
            environment: EnvironmentInfo(
                locator: ExecutableLocator(directories: []), brew: brew,
                caskIndex: CaskIndex(entries: entries), osVersion: Version("26.0")
            ),
            architecture: architecture
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

    private func githubRelease(owner: String, repo: String, tag: String) -> FakeHTTP {
        FakeHTTP { url, _, _, _ in
            guard url.absoluteString == "https://github.com/\(owner)/\(repo)/releases/latest" else {
                return response("", status: 404, url: url)
            }
            return response(
                "",
                url: URL(string: "https://github.com/\(owner)/\(repo)/releases/tag/\(tag)")!
            )
        }
    }

    // MARK: - Catalog

    @Test func catalogMapsOnlyVerifiedPopularApps() {
        let expected = [
            ("2dust.v2rayN", "2dust/v2rayN"),
            ("com.aone.keka", "aonez/Keka"),
            ("com.jgraph.drawio.desktop", "jgraph/drawio-desktop"),
            ("com.knollsoft.Rectangle", "rxhanson/Rectangle"),
            ("com.lwouis.alt-tab-macos", "lwouis/alt-tab-macos"),
            ("com.utmapp.UTM", "utmapp/UTM"),
            ("com.yetone.magpie", "yetone/magpie-releases"),
            ("dev.zed.Zed", "zed-industries/zed"),
            ("eu.exelban.Stats", "exelban/stats"),
            ("io.github.clash-verge-rev.clash-verge-rev", "clash-verge-rev/clash-verge-rev"),
            ("md.obsidian", "obsidianmd/obsidian-releases"),
            ("org.hammerspoon.Hammerspoon", "Hammerspoon/hammerspoon"),
            ("org.localsend.localsendApp", "localsend/localsend"),
            ("org.m0k.transmission", "transmission/transmission"),
            ("org.p0deje.Maccy", "p0deje/Maccy"),
            ("pro.betterdisplay.BetterDisplay", "waydabber/BetterDisplay"),
        ]
        for (bundleID, slug) in expected {
            guard case .github(let repo)? = AppUpdateCatalog.source(for: bundleID) else {
                Issue.record("Missing catalog source for \(bundleID)")
                continue
            }
            #expect(repo.slug == slug)
        }
    }

    @Test func electronMetadataTakesPrecedenceOverCatalog() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(
            in: root, version: "1.0.0", bundleID: "dev.zed.Zed", name: "Zed",
            updateYAML: """
                provider: generic
                url: https://electron.example/zed/
                """
        )
        let http = FakeHTTP { url, _, _, _ in
            if url.host == "electron.example" {
                return response("version: 9.9.9\npath: Zed-9.9.9.zip\n", url: url)
            }
            return response("", status: 404, url: url)
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: http)
        )
        let item = try #require(result.items.first)
        #expect(item.latestVersion == "9.9.9")
        #expect(item.upgrade.url?.host == "electron.example")
        #expect(result.details.first?.state == .checked)
    }

    @Test func discoversMagpieFromCatalogWithoutSparkleOrCLI() async throws {
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

        let detail = try #require(result.details.first)
        #expect(detail.id == "app:com.yetone.magpie")
        #expect(detail.state == .checked)
    }

    @Test(arguments: ["0.1.1290", "0.1.1291", "development"])
    func ignoresCurrentNewerOrUnversionedApps(version: String) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(in: root, version: version)
        let result = try await AppUpdateDetector(directories: [root]).scan(context(root: root, http: releases))
        #expect(result.items.isEmpty)
        let detail = try #require(result.details.first)
        let expected: SourceReportDetail.State =
            version == "development" ? .unsupported : .current
        #expect(detail.state == expected)
    }

    @Test func doesNotGuessUpdateSourceFromDisplayName() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(in: root, version: "0.1.1285", bundleID: "org.unrelated.magpie")
        let counter = Counter()
        let http = FakeHTTP { url, _, _, _ in
            _ = counter.increment()
            return response("", status: 404, url: url)
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(context(root: root, http: http))
        #expect(result.items.isEmpty)
        #expect(counter.count == 0)
        let detail = try #require(result.details.first)
        #expect(detail.state == .unsupported)
    }

    @Test func marksCaskManagedAppsWithoutChecking() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(in: root, version: "0.1.1285")
        let counter = Counter()
        let http = FakeHTTP { url, _, _, _ in
            _ = counter.increment()
            return response("", status: 404, url: url)
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: http, caskPath: app.path)
        )
        #expect(result.items.isEmpty)
        #expect(counter.count == 0)
        let detail = try #require(result.details.first)
        #expect(detail.state == .managed)
        #expect(detail.message?.contains("magpie") == true)
    }

    // MARK: - Standard metadata

    @Test func discoversElectronGitHubMetadata() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(
            in: root, version: "1.0.0", bundleID: "com.example.openchamber", name: "OpenChamber",
            updateYAML: """
                provider: github
                owner: openchamber
                repo: openchamber
                updaterCacheDirName: openchamber-updater
                """
        )
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: githubRelease(owner: "openchamber", repo: "openchamber", tag: "v1.1.0"))
        )
        let item = try #require(result.items.first)
        #expect(item.latestVersion == "1.1.0")
        #expect(item.repo == RepoRef(owner: "openchamber", name: "openchamber"))
        #expect(item.changelogKind == .githubReleases)
        #expect(item.upgrade.url?.absoluteString == "https://github.com/openchamber/openchamber/releases/tag/v1.1.0")
        #expect(result.details.first?.state == .checked)
    }

    @Test func discoversElectronGenericManifestOnArm64() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(
            in: root, version: "2.2.0", bundleID: "com.example.kimi", name: "Kimi",
            updateYAML: """
                provider: generic
                url: https://updates.example.com/kimi/
                updaterCacheDirName: kimi-updater
                """
        )
        let manifest = """
            version: 2.3.0
            files:
              - url: Kimi-2.3.0-arm64-mac.zip
                sha512: abc
                size: 1
            path: Kimi-2.3.0-arm64-mac.zip
            sha512: abc
            releaseDate: '2026-10-01T00:00:00.000Z'
            """
        let http = FakeHTTP { url, _, _, _ in
            guard url.lastPathComponent == "latest-mac-arm64.yml" else {
                return response("", status: 404, url: url)
            }
            return response(manifest, url: url)
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: http, architecture: "arm64")
        )
        let item = try #require(result.items.first)
        #expect(item.latestVersion == "2.3.0")
        #expect(item.changelogKind == .none)
        #expect(
            item.upgrade.url?.absoluteString
                == "https://updates.example.com/kimi/Kimi-2.3.0-arm64-mac.zip"
        )
        #expect(result.details.first?.state == .checked)
    }

    @Test func selectsCompatibleElectronArtifactFromUniversalManifest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(
            in: root, version: "2.2.0", bundleID: "com.example.kimi", name: "Kimi",
            updateYAML: """
                provider: generic
                url: https://updates.example.com/kimi/
                """
        )
        let http = FakeHTTP { url, _, _, _ in
            guard url.lastPathComponent == "latest-mac.yml" else {
                return response("", status: 404, url: url)
            }
            return response(
                """
                version: 2.3.0
                files:
                  - url: Kimi-2.3.0-x64-mac.zip
                  - url: Kimi-2.3.0-arm64-mac.zip
                """, url: url)
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: http, architecture: "arm64")
        )
        #expect(
            result.items.first?.upgrade.url?.absoluteString
                == "https://updates.example.com/kimi/Kimi-2.3.0-arm64-mac.zip"
        )
    }

    @Test func fallsBackToUniversalElectronManifest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(
            in: root, version: "2.2.0", bundleID: "com.example.kimi", name: "Kimi",
            updateYAML: """
                provider: generic
                url: https://updates.example.com/kimi/
                """
        )
        let http = FakeHTTP { url, _, _, _ in
            guard url.lastPathComponent == "latest-mac.yml" else {
                return response("", status: 404, url: url)
            }
            return response(
                """
                version: 2.4.0
                files:
                  - url: Kimi-2.4.0-mac.zip
                path: Kimi-2.4.0-mac.zip
                """,
                url: url
            )
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: http, architecture: "arm64")
        )
        let item = try #require(result.items.first)
        #expect(item.latestVersion == "2.4.0")
        #expect(item.upgrade.url?.absoluteString == "https://updates.example.com/kimi/Kimi-2.4.0-mac.zip")
    }

    @Test func rejectsInsecureElectronDownload() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(
            in: root, version: "2.2.0", bundleID: "com.example.kimi", name: "Kimi",
            updateYAML: """
                provider: generic
                url: https://updates.example.com/kimi/
                """
        )
        let http = FakeHTTP { url, _, _, _ in
            response(
                """
                version: 2.3.0
                files:
                  - url: http://updates.example.com/kimi/Kimi.zip
                path: http://updates.example.com/kimi/Kimi.zip
                """,
                url: url
            )
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: http, architecture: "x86_64")
        )
        #expect(result.items.isEmpty)
        #expect(result.details.first?.state == .unavailable)
    }

    @Test func rejectsNonPublicGithubAndNonDefaultElectronChannel() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = [
            """
            provider: github
            host: github.enterprise.example
            owner: openchamber
            repo: openchamber
            """,
            """
            provider: generic
            url: https://updates.example.com/app/
            channel: beta
            """,
        ]
        for (index, yaml) in metadata.enumerated() {
            let appRoot = root.appendingPathComponent("App\(index)")
            _ = try makeApp(
                in: appRoot, version: "1.0", bundleID: "com.example.custom\(index)",
                name: "Custom\(index)", updateYAML: yaml
            )
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(
                root: root,
                http: FakeHTTP { _, _, _, _ in response("", status: 404) }
            )
        )
        #expect(result.items.isEmpty)
        #expect(result.details.allSatisfy { $0.state == .unsupported })
    }

    @Test func malformedMetadataYieldsUnsupportedDetail() async throws {
        let metadata = [
            """
            provider: generic
            url: http://updates.example.com/app/
            """,
            """
            provider: github
            owner: openchamber
            """,
            """
            provider: s3
            bucket: example
            """,
        ]
        for yaml in metadata {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            _ = try makeApp(
                in: root, version: "1.0", bundleID: "com.example.custom", name: "Custom",
                updateYAML: yaml
            )
            let counter = Counter()
            let http = FakeHTTP { url, _, _, _ in
                _ = counter.increment()
                return response("", status: 404, url: url)
            }
            let result = try await AppUpdateDetector(directories: [root]).scan(
                context(root: root, http: http)
            )
            #expect(result.items.isEmpty)
            #expect(counter.count == 0)
            let detail = try #require(result.details.first)
            #expect(detail.state == .unsupported)
        }
    }

    @Test func sparkleFeedTakesPrecedenceOverElectronMetadata() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(
            in: root, version: "1.0", bundleID: "com.example.sparkle", name: "Sparkle",
            feed: "https://example.com/appcast.xml",
            updateYAML: """
                provider: generic
                url: https://updates.example.com/app/
                """
        )
        let counter = Counter()
        let http = FakeHTTP { url, _, _, _ in
            _ = counter.increment()
            guard url.host == "example.com" else { return response("", status: 404, url: url) }
            return response(
                """
                <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
                <sparkle:version>2.0</sparkle:version>
                <enclosure url="https://example.com/app.zip" />
                </item></channel></rss>
                """, url: url)
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(context(root: root, http: http))
        #expect(result.items.map(\.id) == ["app:com.example.sparkle"])
        #expect(result.items.first?.latestVersion == "2.0")
        #expect(counter.count == 1)
    }

    @Test func deduplicatesAppsByBundleIdentifier() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(in: root.appendingPathComponent("One"), version: "0.1.1285")
        _ = try makeApp(in: root.appendingPathComponent("Two"), version: "0.1.1285")
        let result = try await AppUpdateDetector(directories: [root]).scan(context(root: root, http: releases))
        #expect(result.items.count == 1)
        #expect(result.details.count == 1)
    }

    // MARK: - Configuration

    @Test func explicitConfigOverridesCatalog() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(in: root, version: "1.0")
        let config = RemigeConfig(
            appUpdates: [
                AppUpdateConfig(
                    bundleIdentifier: "com.yetone.magpie", github: "example/magpie-nightly")
            ]
        )
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(
                root: root,
                http: githubRelease(owner: "example", repo: "magpie-nightly", tag: "v1.5.0"),
                config: config
            )
        )
        let item = try #require(result.items.first)
        #expect(item.latestVersion == "1.5.0")
        #expect(item.repo == RepoRef(owner: "example", name: "magpie-nightly"))
    }

    @Test func explicitConfigUsesLatestURLAndRegex() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(
            in: root, version: "1.0", bundleID: "com.example.custom", name: "Custom")
        let config = RemigeConfig(
            appUpdates: [
                AppUpdateConfig(
                    bundleIdentifier: "com.example.custom",
                    latestURL: "https://example.com/download",
                    latestRegex: #"Version\s+([0-9.]+)"#
                )
            ]
        )
        let http = FakeHTTP { url, _, _, _ in
            guard url.absoluteString == "https://example.com/download" else {
                return response("", status: 404, url: url)
            }
            return response("Latest Version 1.4.2", url: url)
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: http, config: config)
        )
        let item = try #require(result.items.first)
        #expect(item.latestVersion == "1.4.2")
        #expect(item.changelogKind == .web)
        #expect(item.upgrade.url?.absoluteString == "https://example.com/download")
    }

    @Test func rejectsInsecureConfiguredLatestURL() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(
            in: root, version: "1.0", bundleID: "com.example.custom", name: "Custom")
        let config = RemigeConfig(
            appUpdates: [
                AppUpdateConfig(
                    bundleIdentifier: "com.example.custom",
                    latestURL: "http://example.com/download",
                    latestRegex: #"Version\s+([0-9.]+)"#
                )
            ]
        )
        let counter = Counter()
        let http = FakeHTTP { url, _, _, _ in
            _ = counter.increment()
            return response("", status: 404, url: url)
        }
        let result = try await AppUpdateDetector(directories: [root]).scan(
            context(root: root, http: http, config: config)
        )
        #expect(result.items.isEmpty)
        #expect(counter.count == 0)
        #expect(result.details.first?.state == .unsupported)
    }

    // MARK: - Mixed availability

    @Test func unavailableReleaseSourceDoesNotHideSparkleUpdates() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(in: root, version: "0.1.1285")
        let vendor = root.appendingPathComponent("Vendor")
        _ = try makeApp(
            in: vendor, version: "1.0", bundleID: "org.example.sparkle", name: "Sparkle",
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
        let details = Dictionary(uniqueKeysWithValues: result.details.map { ($0.id, $0.state) })
        #expect(details["app:com.yetone.magpie"] == .unavailable)
        #expect(details["app:org.example.sparkle"] == .checked)
    }
}
