import Foundation
import Testing

@testable import RemigeCore

struct DetectorTests {
    private let brewJSON = """
        {
          "formulae": [
            {"name":"sqlite","installed_versions":["3.54.0"],"current_version":"3.54.1","pinned":false},
            {"name":"simdutf","installed_versions":["9.3.1"],"current_version":"9.3.2","pinned":true}
          ],
          "casks": [
            {"name":"cc-switch","installed_versions":["4.0.14"],"current_version":"4.0.15"}
          ]
        }
        """

    @Test func homebrewParsesFormulaeAndCasks() async throws {
        let cache = makeCache()
        let brew = BrewEnvironment(
            executable: "/opt/homebrew/bin/brew",
            prefix: "/opt/homebrew",
            caskroom: temporaryDirectory().appendingPathComponent("Caskroom")
        )
        let environment = EnvironmentInfo(
            locator: ExecutableLocator(directories: []),
            brew: brew,
            caskIndex: CaskIndex(),
            osVersion: Version("26.5.1")
        )
        let http = FakeHTTP { url, _, _, _ in
            if url.path.contains("/formula/sqlite") {
                return response(
                    #"{"desc":"SQL database","homepage":"https://sqlite.org"}"#,
                    url: url
                )
            }
            if url.path.contains("/formula/simdutf") {
                return response(
                    #"{"desc":"Unicode","homepage":"https://github.com/simdutf/simdutf","urls":{"stable":{"url":"https://github.com/simdutf/simdutf/archive/refs/tags/v9.3.2.tar.gz"}}}"#,
                    url: url
                )
            }
            if url.path.contains("/cask/cc-switch") {
                return response(
                    #"{"desc":"A manager","homepage":"https://github.com/farion1231/cc-switch"}"#,
                    url: url
                )
            }
            return response("{}", status: 404, url: url)
        }
        let runner = FakeRunner { command in
            #expect(command.executable == "/opt/homebrew/bin/brew")
            #expect(command.arguments.contains("--greedy"))
            #expect(command.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
            return CommandResult(stdout: Data(self.brewJSON.utf8), exitCode: 0)
        }
        let context = ScanContext(
            runner: runner,
            http: http,
            cache: cache,
            config: .empty,
            environment: environment
        )
        let output = try await HomebrewDetector().scan(context)
        #expect(output.items.count == 3)
        #expect(output.skipped == false)

        let brewItem = try #require(output.items.first { $0.name == "simdutf" })
        #expect(brewItem.currentVersion == "9.3.1")
        #expect(brewItem.latestVersion == "9.3.2")
        #expect(brewItem.pinned)
        #expect(brewItem.repo == RepoRef(owner: "simdutf", name: "simdutf"))
        #expect(brewItem.upgrade.arguments == ["upgrade", "--formula", "simdutf"])

        let cask = try #require(output.items.first { $0.name == "cc-switch" })
        #expect(cask.kind == .cask)
        #expect(cask.repo == RepoRef(owner: "farion1231", name: "cc-switch"))
        #expect(cask.upgrade.arguments == ["upgrade", "--cask", "cc-switch"])

        let sqlite = try #require(output.items.first { $0.name == "sqlite" })
        #expect(sqlite.repo == nil)
        #expect(sqlite.changelogKind == .web)
    }

    @Test func homebrewSkipsWhenNotInstalled() async throws {
        let environment = EnvironmentInfo(
            locator: ExecutableLocator(directories: []),
            brew: nil,
            caskIndex: CaskIndex(),
            osVersion: Version("26.0")
        )
        let context = ScanContext(
            runner: FakeRunner(output: ""),
            http: FakeHTTP { url, _, _, _ in response("{}", url: url) },
            cache: makeCache(),
            config: .empty,
            environment: environment
        )
        let output = try await HomebrewDetector().scan(context)
        #expect(output.skipped)
        #expect(output.items.isEmpty)
    }

    @Test func npmParsesGlobalOutdated() async throws {
        let npmJSON = """
            {
              "@teable/cli": {"current":"0.6.45","latest":"0.7.0","location":"/usr/local/lib/node_modules/@teable/cli"},
              "current-pkg": {"current":"1.0.0","latest":"1.0.0","location":"/tmp"}
            }
            """
        let http = FakeHTTP { url, _, _, _ in
            if url.absoluteString.contains("registry.npmjs.org") {
                return response(
                    #"{"name":"@teable/cli","version":"0.7.0","description":"CLI","repository":{"url":"git+https://github.com/teableio/teable.git"}}"#,
                    url: url
                )
            }
            return response("{}", status: 404, url: url)
        }
        let environment = EnvironmentInfo(
            locator: ExecutableLocator(directories: []),
            brew: nil,
            caskIndex: CaskIndex(),
            osVersion: Version("26.0"),
            managers: [.npm: "/opt/homebrew/bin/npm"]
        )
        let context = ScanContext(
            runner: FakeRunner(output: npmJSON, exitCode: 1),
            http: http,
            cache: makeCache(),
            config: .empty,
            environment: environment
        )
        let output = try await NpmGlobalDetector().scan(context)
        #expect(output.items.count == 1)
        let item = try #require(output.items.first)
        #expect(item.id == "npm:@teable/cli")
        #expect(item.source == .npm)
        #expect(item.currentVersion == "0.6.45")
        #expect(item.latestVersion == "0.7.0")
        #expect(item.repo == RepoRef(owner: "teableio", name: "teable"))
        #expect(item.targetVersion == "0.7.0")
        #expect(item.updateMagnitude == .major)
        #expect(item.majorVersionAvailable)
        #expect(!item.isBatchEligible)
        #expect(item.upgrade.arguments == ["install", "-g", "@teable/cli@0.7.0"])
    }

    @Test func npmHonorsAPinnedTarget() async throws {
        let npmJSON = """
            {"@teable/cli":{"current":"0.6.45","latest":"0.7.0","location":"/tmp/cli"}}
            """
        let http = FakeHTTP { url, _, _, _ in
            response(
                #"{"name":"@teable/cli","version":"0.7.0"}"#,
                url: url
            )
        }
        let environment = EnvironmentInfo(
            locator: ExecutableLocator(directories: []),
            brew: nil,
            caskIndex: CaskIndex(),
            osVersion: Version("26.0"),
            managers: [.npm: "/opt/homebrew/bin/npm"]
        )
        let context = ScanContext(
            runner: FakeRunner(output: npmJSON, exitCode: 1),
            http: http,
            cache: makeCache(),
            config: RemigeConfig(versionTargets: ["npm:@teable/cli": "0.6.50"]),
            environment: environment
        )

        let output = try await NpmGlobalDetector().scan(context)
        let item = try #require(output.items.first)
        #expect(item.targetVersion == "0.6.50")
        #expect(item.targetOrigin == .pinned)
        #expect(item.updateMagnitude == .patch)
        #expect(item.isBatchEligible)
        #expect(item.upgrade.arguments == ["install", "-g", "@teable/cli@0.6.50"])
    }

    @Test func npmHoldPicksTheNewestSameMajorVersion() async throws {
        let npmJSON = """
            {"@teable/cli":{"current":"0.6.45","latest":"0.7.0","location":"/tmp/cli"}}
            """
        let http = FakeHTTP { url, _, _, _ in
            if url.absoluteString.hasSuffix("/latest") {
                return response(#"{"name":"@teable/cli","version":"0.7.0"}"#, url: url)
            }
            return response(
                #"{"versions":{"0.6.45":{},"0.6.50":{},"0.6.60":{},"0.7.0":{}}}"#,
                url: url
            )
        }
        let environment = EnvironmentInfo(
            locator: ExecutableLocator(directories: []),
            brew: nil,
            caskIndex: CaskIndex(),
            osVersion: Version("26.0"),
            managers: [.npm: "/opt/homebrew/bin/npm"]
        )
        let context = ScanContext(
            runner: FakeRunner(output: npmJSON, exitCode: 1),
            http: http,
            cache: makeCache(),
            config: RemigeConfig(updatePolicy: UpdatePolicyConfig(major: .hold)),
            environment: environment
        )

        let output = try await NpmGlobalDetector().scan(context)
        let item = try #require(output.items.first)
        #expect(item.targetVersion == "0.6.60")
        #expect(item.targetOrigin == .heldMajor)
        #expect(item.majorVersionAvailable)
        #expect(item.updateMagnitude == .patch)
        #expect(item.isBatchEligible)
        #expect(item.upgrade.arguments == ["install", "-g", "@teable/cli@0.6.60"])
    }

    @Test func pnpmOutputIsTolerated() {
        let modern = """
            [{"path":"/x","dependencies":{"vercel":"44.2.7","scoped":{"version":"1.0.0"}}}]
            """
        let deps = PnpmGlobalDetector.dependencies(from: Data(modern.utf8))
        #expect(deps["vercel"] == "44.2.7")
        #expect(deps["scoped"] == "1.0.0")
        let legacy = #"{"dependencies":{"a":"1.2.3"}}"#
        #expect(PnpmGlobalDetector.dependencies(from: Data(legacy.utf8))["a"] == "1.2.3")
        #expect(PnpmGlobalDetector.dependencies(from: Data("{}".utf8)).isEmpty)
    }

    @Test func masOutputParsing() {
        let output = """
            497799835 Xcode (16.0)
            123456789 App With Spaces (2.1.0)
            nonsense
            """
        let apps = MacAppStoreDetector.parse(output)
        #expect(apps.count == 2)
        #expect(apps[0].id == "497799835")
        #expect(apps[0].name == "Xcode")
        #expect(apps[1].name == "App With Spaces")
        #expect(apps[1].version == "2.1.0")
    }

    @Test func customToolUsesItsOwnLatestAndUpgrade() async throws {
        let toolURL = temporaryDirectory().appendingPathComponent("mytool")
        FileManager.default.createFile(atPath: toolURL.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)
        let tool = CustomToolConfig(
            name: "mytool",
            path: toolURL.path,
            versionArgs: ["--version"],
            github: "acme/mytool",
            upgradeArgs: ["mytool", "self-update"],
            homepage: "https://acme.dev"
        )
        let http = FakeHTTP { url, _, _, method in
            if method == "HEAD" || method == "GET" {
                return HTTPResponse(
                    status: 200,
                    data: Data(),
                    finalURL: URL(string: "https://github.com/acme/mytool/releases/tag/v2.0.0")!
                )
            }
            return response("", status: 500, url: url)
        }
        let runner = FakeRunner { command in
            if command.executable == toolURL.path {
                return CommandResult(stdout: Data("mytool 1.0.0".utf8), exitCode: 0)
            }
            return CommandResult(exitCode: 1)
        }
        let environment = EnvironmentInfo(
            locator: ExecutableLocator(directories: []),
            brew: nil,
            caskIndex: CaskIndex(),
            osVersion: Version("26.0")
        )
        let context = ScanContext(
            runner: runner,
            http: http,
            cache: makeCache(),
            config: RemigeConfig(customTools: [tool]),
            environment: environment
        )
        let output = try await CustomToolDetector().scan(context)
        let item = try #require(output.items.first)
        #expect(item.latestVersion == "2.0.0")
        #expect(item.upgrade.arguments == ["self-update"])
        #expect(item.repo == RepoRef(owner: "acme", name: "mytool"))
    }
}
