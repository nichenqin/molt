import Foundation
import Testing

@testable import RemigeCore

struct StorageTests {
    @Test func cacheRoundTripsAndExpires() async throws {
        let cache = makeCache()
        struct Value: Codable, Equatable {
            var name: String
        }
        await cache.write(Value(name: "remige"), key: "value")
        let fresh = await cache.read(Value.self, key: "value", maxAge: 60)
        #expect(fresh == Value(name: "remige"))

        try await Task.sleep(nanoseconds: 40_000_000)
        let expired = await cache.read(Value.self, key: "value", maxAge: 0.01)
        #expect(expired == nil)
        let ignoringAge = await cache.readIgnoringAge(Value.self, key: "value")
        #expect(ignoringAge == Value(name: "remige"))
    }

    @Test func httpCacheKeepsETag() async {
        let cache = makeCache()
        let url = URL(string: "https://example.com/appcast.xml")!
        let httpResponse = HTTPResponse(
            status: 200,
            data: Data("<rss/>".utf8),
            headers: ["Etag": "\"abc\""],
            finalURL: url
        )
        await cache.writeHTTP(httpResponse, for: url)
        let entry = await cache.readHTTP(url, maxAge: 60)
        #expect(entry?.etag == "\"abc\"")
        #expect(entry?.data == Data("<rss/>".utf8))
    }

    @Test func snapshotStoreRoundTrips() async throws {
        let store = SnapshotStore(cache: makeCache())
        let item = OutdatedItem(
            id: "brew:formula:sqlite",
            name: "sqlite",
            source: .homebrew,
            kind: .formula,
            currentVersion: "3.54.0",
            latestVersion: "3.54.1",
            upgrade: .command("/opt/homebrew/bin/brew", ["upgrade", "--formula", "sqlite"])
        )
        let snapshot = ScanSnapshot(
            duration: 1.2,
            items: [item],
            reports: [SourceReport(source: .homebrew, state: .ok, count: 1)],
            host: HostInfo(name: "test", osVersion: "26.0", architecture: "arm64")
        )
        await store.save(snapshot)
        let loaded = await store.load()
        #expect(loaded?.items == [item])
        #expect(loaded?.reports.first?.state == .ok)
    }

    @Test func configDefaultsSavesAndRejectsInvalidJSON() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("config.json")
        let store = ConfigStore(url: url)
        #expect(try store.load() == .empty)

        var config = RemigeConfig()
        config.disabledSources = ["mas"]
        config.customTools = [CustomToolConfig(name: "x", github: "a/b")]
        try store.save(config)
        #expect(try store.load() == config)
        try Data(#"{"customTools":[{"name":"x","github":"a/b"}]}"#.utf8).write(to: url)
        let partial = try store.load()
        #expect(partial.schema == 1)
        #expect(partial.disabledSources.isEmpty)
        #expect(partial.customTools.first?.name == "x")

        try Data("{nope".utf8).write(to: url)
        #expect(throws: ConfigError.self) {
            try store.load()
        }
    }

    @Test func configDecodesAppUpdateOverrides() throws {
        let json = """
            {"appUpdates":[{"bundleIdentifier":"com.example.app","github":"owner/repo"}]}
            """
        let config = try JSONDecoder.remige.decode(RemigeConfig.self, from: Data(json.utf8))
        #expect(config.appUpdates.first?.bundleIdentifier == "com.example.app")
        #expect(
            config.appUpdates.first?.source
                == AppUpdateSource.github(RepoRef(owner: "owner", name: "repo"))
        )
    }

    @Test func sourceReportDecodesWithoutDetails() throws {
        let old = Data(#"{"source":"app","state":"ok","count":2}"#.utf8)
        let report = try JSONDecoder.remige.decode(SourceReport.self, from: old)
        #expect(report.count == 2)
        #expect(report.details.isEmpty)

        let detail = SourceReportDetail(
            id: "app:com.example.app", name: "Example", state: .unsupported,
            message: "No standard update source")
        let encoded = try JSONEncoder.remige.encode(
            SourceReport(source: .app, state: .ok, count: 1, details: [detail]))
        let decoded = try JSONDecoder.remige.decode(SourceReport.self, from: encoded)
        #expect(decoded.details == [detail])
    }

    @Test func mergeDropsSparkleDuplicateOfBrewCask() {
        let cask = OutdatedItem(
            id: "brew:cask:cc-switch",
            name: "cc-switch",
            source: .homebrew,
            kind: .cask,
            currentVersion: "4.0.14",
            latestVersion: "4.0.15",
            installedPath: "/Applications/CC Switch.app",
            upgrade: .command("/opt/homebrew/bin/brew", ["upgrade", "--cask", "cc-switch"])
        )
        let app = OutdatedItem(
            id: "app:com.ccswitch",
            name: "CC Switch",
            source: .app,
            kind: .application,
            currentVersion: "4.0.14",
            latestVersion: "4.0.15",
            changelogKind: .appcast,
            installedPath: "/Applications/CC Switch.app",
            bundleIdentifier: "com.ccswitch",
            upgrade: .open(URL(string: "https://example.com/CC.dmg")!)
        )
        let merged = Scanner.merge([app, cask])
        #expect(merged.count == 1)
        #expect(merged[0].id == "brew:cask:cc-switch")
        #expect(merged[0].bundleIdentifier == "com.ccswitch")
    }

    @Test func mergePrefersCustomToolOverCatalogDuplicate() {
        let cli = OutdatedItem(
            id: "cli:tool",
            name: "tool",
            source: .cli,
            kind: .binary,
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            installedPath: "/usr/local/bin/tool",
            upgrade: .open(URL(string: "https://example.com")!)
        )
        let custom = OutdatedItem(
            id: "custom:tool",
            name: "tool",
            source: .custom,
            kind: .custom,
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            installedPath: "/usr/local/bin/tool",
            upgrade: .command("/usr/local/bin/tool", ["update"])
        )
        let merged = Scanner.merge([cli, custom])
        #expect(merged.map(\.id) == ["custom:tool"])
    }

    @Test func caskIndexMapsTokenToApp() {
        let entry = CaskIndex.Entry(
            token: "cc-switch",
            appNames: ["CC Switch.app"],
            installedPaths: ["/Applications/CC Switch.app"]
        )
        let index = CaskIndex(entries: [entry])
        #expect(index.token(for: "/Applications/CC Switch.app") == "cc-switch")
        #expect(index.installedPath(for: "cc-switch") == "/Applications/CC Switch.app")
    }
}

struct ProcessTests {
    @Test func runsCommandAndCapturesBothStreams() async {
        let runner = ProcessRunner()
        let result = await runner.run(
            CommandSpec(executable: "/bin/sh", arguments: ["-c", "printf out; printf err >&2; exit 3"]),
            timeout: 5
        )
        #expect(result.stdoutText == "out")
        #expect(result.stderrText == "err")
        #expect(result.exitCode == 3)
        #expect(!result.succeeded)
        #expect(result.failureMessage?.contains("err") == true)
    }

    @Test func timesOutWithoutHanging() async {
        let runner = ProcessRunner()
        let started = Date()
        let result = await runner.run(
            CommandSpec(executable: "/bin/sh", arguments: ["-c", "sleep 5"]),
            timeout: 0.2
        )
        #expect(result.timedOut)
        #expect(!result.succeeded)
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func streamingRunnerEmitsOutputAndFinish() async {
        let runner = StreamingProcessRunner()
        let stream = runner.stream(
            CommandSpec(executable: "/bin/sh", arguments: ["-c", "printf one; sleep 0.1; printf two"]),
            timeout: 5
        )
        var output = ""
        var result: CommandResult?
        for await event in stream {
            switch event {
            case .output(let text): output += text
            case .finished(let finished): result = finished
            }
        }
        #expect(output.contains("one"))
        #expect(output.contains("two"))
        #expect(result?.succeeded == true)
    }

    @Test func launchFailureIsReported() async {
        let runner = ProcessRunner()
        let result = await runner.run(
            CommandSpec(executable: "/definitely/not/a/binary", arguments: []),
            timeout: 2
        )
        #expect(result.launchError != nil)
        #expect(!result.succeeded)
    }
}
