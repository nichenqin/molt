import CryptoKit
import Foundation
import Testing

@testable import MoltCore

struct UpdateTests {
    private func manifestJSON(version: String, sha: String, size: Int) -> String {
        """
        {
          "schema": 1,
          "version": "\(version)",
          "published": "2026-10-19T00:00:00Z",
          "notes": "### Changes\\n- Faster",
          "pageURL": "https://example.com/releases",
          "assets": {
            "Molt-macos.zip": {
              "name": "Molt-macos.zip",
              "url": "https://example.com/Molt-macos.zip",
              "sha256": "\(sha)",
              "size": \(size)
            },
            "molt-cli": {
              "name": "molt-cli",
              "url": "https://example.com/molt-cli",
              "sha256": "\(sha)",
              "size": \(size)
            }
          }
        }
        """
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func findsNewerVersion() async throws {
        let payload = Data("new".utf8)
        let feed = manifestJSON(version: "0.3.0", sha: sha(payload), size: payload.count)
        let http = FakeHTTP { url, _, _, _ in
            response(feed, url: url)
        }
        let service = UpdateService(
            http: http,
            feedURL: URL(string: "https://example.com/latest.json")!,
            currentVersion: "0.2.0"
        )
        let update = try #require(await service.check())
        #expect(update.currentVersion == "0.2.0")
        #expect(update.latestVersion == "0.3.0")
        #expect(update.manifest.appZip?.url.absoluteString == "https://example.com/Molt-macos.zip")
        #expect(update.manifest.notes.contains("Faster"))
    }

    @Test func returnsNilForCurrentOrOlderVersion() async throws {
        let payload = Data("same".utf8)
        for version in ["0.2.0", "0.1.9"] {
            let feed = manifestJSON(version: version, sha: sha(payload), size: payload.count)
            let http = FakeHTTP { url, _, _, _ in response(feed, url: url) }
            let service = UpdateService(
                http: http,
                feedURL: URL(string: "https://example.com/latest.json")!,
                currentVersion: "0.2.0"
            )
            #expect(try await service.check() == nil)
        }
    }

    @Test func malformedFeedIsAnError() async throws {
        let http = FakeHTTP { url, _, _, _ in response("not json", url: url) }
        let service = UpdateService(
            http: http,
            feedURL: URL(string: "https://example.com/latest.json")!,
            currentVersion: "0.2.0"
        )
        await #expect(throws: UpdateError.self) {
            try await service.check()
        }
    }

    @Test func verifiesDownloadedChecksum() async throws {
        let payload = Data("binary-update".utf8)
        let asset = UpdateAsset(
            name: "molt-cli",
            url: URL(string: "https://example.com/molt-cli")!,
            sha256: sha(payload),
            size: payload.count
        )
        let good = FakeHTTP { url, _, _, _ in
            HTTPResponse(status: 200, data: payload, finalURL: url)
        }
        let service = UpdateService(
            http: good,
            feedURL: URL(string: "https://example.com/latest.json")!,
            currentVersion: "0.2.0"
        )
        #expect(try await service.download(asset) == payload)

        let bad = FakeHTTP { url, _, _, _ in
            HTTPResponse(status: 200, data: Data("tampered".utf8), finalURL: url)
        }
        let badService = UpdateService(
            http: bad,
            feedURL: URL(string: "https://example.com/latest.json")!,
            currentVersion: "0.2.0"
        )
        await #expect(throws: UpdateError.self) {
            try await badService.download(asset)
        }
    }

    @Test func installsCliAtomically() throws {
        let directory = temporaryDirectory()
        let target = directory.appendingPathComponent("molt")
        try Data("old".utf8).write(to: target)
        let payload = Data("new-cli".utf8)
        try CLIUpdater.install(data: payload, at: target)
        #expect(try Data(contentsOf: target) == payload)
        let mode = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
    }

    @Test func appUpdaterReplacesBundleAndCanSkipRelaunch() async throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("Molt.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleShortVersionString": "9.9.9",
            "CFBundleIdentifier": "com.example.molt.test",
            "CFBundleExecutable": "Molt",
            "CFBundlePackageType": "APPL",
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: source.appendingPathComponent("Info.plist"))

        let zip = root.appendingPathComponent("update.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", root.appendingPathComponent("Molt.app").path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        #expect(ditto.terminationStatus == 0)

        let target = root.appendingPathComponent("Applications/Molt.app", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("old.txt"))

        try AppUpdater.install(
            zipData: try Data(contentsOf: zip),
            expectedVersion: "9.9.9",
            targetApp: target,
            processID: 999_999,
            relaunch: false
        )

        var installed = false
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")),
                let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                let dictionary = object as? [String: Any],
                dictionary["CFBundleShortVersionString"] as? String == "9.9.9"
            {
                installed = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(installed)
    }
}
