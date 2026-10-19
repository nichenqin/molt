import Foundation
import Testing

@testable import RemigeCore

struct VersionPolicyTests {
    private func install(
        executable: String = "/usr/local/bin/npm",
        prefix: [String] = ["install", "-g"],
        package: String = "pkg"
    ) -> VersionedInstall {
        VersionedInstall(executable: executable, argumentsPrefix: prefix, package: package)
    }

    private func item(
        current: String,
        latest: String,
        source: SourceKind = .npm,
        kind: PackageKind = .npmGlobal,
        pinned: Bool = false,
        versioned: Bool = true
    ) -> OutdatedItem {
        let template = versioned ? install() : nil
        return OutdatedItem(
            id: "\(source.rawValue):pkg",
            name: "pkg",
            source: source,
            kind: kind,
            currentVersion: current,
            latestVersion: latest,
            pinned: pinned,
            upgrade: template?.plan(for: "latest") ?? .manual("manual"),
            versionedInstall: template
        )
    }

    @Test func classifiesUpdateMagnitude() {
        #expect(Version("3.2.4")!.updateMagnitude(from: Version("2.6.4")!) == .major)
        #expect(Version("26.2.3")!.updateMagnitude(from: Version("25.1.1")!) == .major)
        #expect(
            Version("4.95.0,242831")!.updateMagnitude(from: Version("4.42.0,195023")!)
                == .minor)
        #expect(Version("1.5")!.updateMagnitude(from: Version("1.4.2")!) == .minor)
        #expect(Version("1.8.14")!.updateMagnitude(from: Version("1.8.13")!) == .patch)
        #expect(Version("0.13.1")!.updateMagnitude(from: Version("0.9.26")!) == .major)
        #expect(Version("beta1.0")!.updateMagnitude(from: Version("1.0")!) == .unknown)
    }

    @Test func zeroXMinorDefinesTheMajorLine() {
        #expect(!Version("0.13.1")!.isSameMajorLine(as: Version("0.9.26")!))
        #expect(Version("0.9.27")!.isSameMajorLine(as: Version("0.9.26")!))
        #expect(Version("3.5.0")!.isSameMajorLine(as: Version("3.0.0")!))
        #expect(!Version("4.0.0")!.isSameMajorLine(as: Version("3.9.0")!))
    }

    @Test func promptIsTheDefaultAndExcludesMajorsFromBatch() {
        var candidate = item(current: "2.6.4", latest: "3.2.4")
        candidate.applyUpdatePolicy(config: RemigeConfig())

        #expect(RemigeConfig().updatePolicy.major == .prompt)
        #expect(candidate.targetVersion == "3.2.4")
        #expect(candidate.updateMagnitude == .major)
        #expect(candidate.majorVersionAvailable)
        #expect(!candidate.isBatchEligible)
        #expect(candidate.targetOrigin == .latest)
    }

    @Test func allowIncludesMajorsInBatch() {
        var candidate = item(current: "2.6.4", latest: "3.2.4")
        candidate.applyUpdatePolicy(
            config: RemigeConfig(updatePolicy: UpdatePolicyConfig(major: .allow)))

        #expect(candidate.targetVersion == "3.2.4")
        #expect(candidate.isBatchEligible)
        #expect(candidate.isBatchable)
    }

    @Test func promptKeepsNonMajorsInBatch() {
        var candidate = item(current: "3.38.9", latest: "3.47.7")
        candidate.applyUpdatePolicy(config: RemigeConfig())

        #expect(candidate.updateMagnitude == .minor)
        #expect(candidate.isBatchEligible)
    }

    @Test func holdPicksTheNewestSameMajorVersion() {
        var candidate = item(current: "1.0.0", latest: "2.0.0")
        candidate.applyUpdatePolicy(
            config: RemigeConfig(updatePolicy: UpdatePolicyConfig(major: .hold)),
            candidates: ["1.1.0", "1.5.0", "2.0.0"]
        )

        #expect(candidate.targetVersion == "1.5.0")
        #expect(candidate.targetOrigin == .heldMajor)
        #expect(candidate.updateMagnitude == .minor)
        #expect(candidate.majorVersionAvailable)
        #expect(candidate.isBatchEligible)
        #expect(candidate.upgrade.arguments == ["install", "-g", "pkg@1.5.0"])
    }

    @Test func holdFallsBackToPromptWithoutCandidates() {
        var candidate = item(current: "1.0.0", latest: "2.0.0")
        candidate.applyUpdatePolicy(
            config: RemigeConfig(updatePolicy: UpdatePolicyConfig(major: .hold)))

        #expect(candidate.targetVersion == "2.0.0")
        #expect(candidate.targetOrigin == .latest)
        #expect(candidate.updateMagnitude == .major)
        #expect(!candidate.isBatchEligible)
    }

    @Test func holdFallsBackForSourcesWithoutVersionedInstall() {
        var candidate = item(
            current: "1.0.0", latest: "2.0.0", source: .homebrew, kind: .formula, versioned: false)
        candidate.applyUpdatePolicy(
            config: RemigeConfig(updatePolicy: UpdatePolicyConfig(major: .hold)),
            candidates: ["1.5.0"]
        )

        #expect(candidate.targetVersion == "2.0.0")
        #expect(candidate.targetOrigin == .latest)
        #expect(!candidate.isBatchEligible)
    }

    @Test func pinnedTargetRebuildsTheInstallCommand() {
        let config = RemigeConfig(
            versionTargets: ["npm:pkg": "1.5.0"]
        )
        var candidate = item(current: "1.0.0", latest: "2.0.0")
        candidate.applyUpdatePolicy(config: config)

        #expect(candidate.targetVersion == "1.5.0")
        #expect(candidate.targetOrigin == .pinned)
        #expect(candidate.updateMagnitude == .minor)
        #expect(candidate.isBatchEligible)
        #expect(candidate.upgrade.arguments == ["install", "-g", "pkg@1.5.0"])
    }

    @Test func invalidPinnedTargetFallsBackToPolicy() {
        let tooNew = RemigeConfig(versionTargets: ["npm:pkg": "3.0.0"])
        var candidate = item(current: "1.0.0", latest: "2.0.0")
        candidate.applyUpdatePolicy(config: tooNew)
        #expect(candidate.targetVersion == "2.0.0")
        #expect(candidate.targetOrigin == .latest)

        let tooOld = RemigeConfig(versionTargets: ["npm:pkg": "0.9.0"])
        candidate.applyUpdatePolicy(config: tooOld)
        #expect(candidate.targetVersion == "2.0.0")
        #expect(candidate.targetOrigin == .latest)
    }

    @Test func pinnedHomebrewItemStaysOutOfBatch() {
        var candidate = item(
            current: "1.0.0", latest: "2.0.0", source: .homebrew, kind: .formula, pinned: true,
            versioned: false)
        candidate.applyUpdatePolicy(
            config: RemigeConfig(updatePolicy: UpdatePolicyConfig(major: .allow)))

        #expect(!candidate.isBatchEligible)
    }

    @Test func unknownVersionsRemainBatchable() {
        var candidate = item(
            current: "1.0.0", latest: "App Store", source: .mas, kind: .appStore, versioned: false)
        candidate.applyUpdatePolicy(config: RemigeConfig())

        #expect(candidate.targetVersion == "App Store")
        #expect(candidate.updateMagnitude == .unknown)
        #expect(!candidate.majorVersionAvailable)
        #expect(candidate.isBatchEligible)
    }

    @Test func selectTargetValidatesTheRange() {
        var candidate = item(current: "1.0.0", latest: "2.0.0")
        let accepted = candidate.selectTarget("1.5.0")
        #expect(accepted)
        #expect(candidate.targetVersion == "1.5.0")
        #expect(candidate.targetOrigin == .pinned)

        let rejectedOld = candidate.selectTarget("0.9.0")
        let rejectedNew = candidate.selectTarget("2.1.0")
        #expect(!rejectedOld)
        #expect(!rejectedNew)
        #expect(candidate.targetVersion == "1.5.0")

        var fixed = item(current: "1.0.0", latest: "2.0.0", versioned: false)
        let rejectedFixed = fixed.selectTarget("1.5.0")
        #expect(!rejectedFixed)

    }

    @Test func oldSnapshotsDecodeWithConservativeDefaults() throws {
        let json = """
            {"id":"npm:pkg","name":"pkg","displayName":"pkg","source":"npm","kind":"npmGlobal",
             "currentVersion":"1.0.0","latestVersion":"2.0.0","changelogKind":"none",
             "pinned":false,"upgrade":{"kind":"manual","arguments":[]}}
            """
        let decoded = try JSONDecoder.remige.decode(OutdatedItem.self, from: Data(json.utf8))

        #expect(decoded.targetVersion == "2.0.0")
        #expect(decoded.updateMagnitude == .major)
        #expect(decoded.majorVersionAvailable)
        #expect(decoded.latestBasis == .source)
        #expect(decoded.targetOrigin == .latest)
        #expect(decoded.isBatchEligible)
        #expect(decoded.versionedInstall == nil)
    }

    @Test func configDecodesPolicyAndTargets() throws {
        let json = """
            {"updatePolicy":{"major":"hold"},"versionTargets":{"npm:pkg":"1.2.3"}}
            """
        let config = try JSONDecoder.remige.decode(RemigeConfig.self, from: Data(json.utf8))

        #expect(config.updatePolicy.major == .hold)
        #expect(config.versionTargets["npm:pkg"] == "1.2.3")

        let partial = try JSONDecoder.remige.decode(RemigeConfig.self, from: Data("{}".utf8))
        #expect(partial.updatePolicy.major == .prompt)
        #expect(partial.versionTargets.isEmpty)
    }

    @Test func policyFieldsRoundTripThroughJSON() throws {
        var original = item(current: "1.0.0", latest: "2.0.0")
        original.applyUpdatePolicy(config: RemigeConfig(versionTargets: ["npm:pkg": "1.5.0"]))

        let data = try JSONEncoder.remige.encode(original)
        let decoded = try JSONDecoder.remige.decode(OutdatedItem.self, from: data)
        #expect(decoded == original)
    }

    @Test func npmVersionCatalogFiltersPrereleasesAndCaches() async {
        let counter = Counter()
        let http = FakeHTTP { url, headers, _, _ in
            _ = counter.increment()
            #expect(headers["Accept"] == "application/vnd.npm.install-v1+json")
            return response(
                #"{"versions":{"2.0.0":{},"1.5.0":{},"1.6.0-beta":{},"1.4.0":{}}}"#,
                url: url
            )
        }
        let cache = makeCache()
        let registry = NpmRegistry(http: http, cache: cache)

        let versions = await registry.versions(package: "@scope/pkg")
        #expect(versions == ["2.0.0", "1.5.0", "1.4.0"])
        _ = await registry.versions(package: "@scope/pkg")
        #expect(counter.count == 1)
        #expect(
            NpmRegistry.versionsURL(package: "@scope/pkg")?.absoluteString
                == "https://registry.npmjs.org/@scope%2Fpkg")
    }
}
