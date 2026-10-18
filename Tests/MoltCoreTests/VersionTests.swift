import Foundation
import Testing

@testable import MoltCore

struct VersionTests {
    @Test func ordersNumericComponents() {
        #expect(Version("1.10.0")! > Version("1.9.9")!)
        #expect(Version("0.13.1")! > Version("0.9.26")!)
        #expect(Version("2026.10")! > Version("2026.9")!)
    }

    @Test func toleratesPrefixesAndBuildMetadata() {
        #expect(Version("v1.2.3")! == Version("1.2.3")!)
        #expect(Version("1.2.3+abc")! == Version("1.2.3")!)
        #expect(Version("1.2.3,456")! == Version("1.2.3")!)
    }

    @Test func prereleaseSortsBeforeRelease() {
        #expect(Version("1.0.0-beta.2")! < Version("1.0.0")!)
        #expect(Version("1.0.0-beta.2")! > Version("1.0.0-beta.1")!)
        #expect(Version("1.0.0-alpha")! < Version("1.0.0-beta")!)
    }

    @Test func homebrewRevisionIsNewer() {
        #expect(Version("1.2.3_1")! > Version("1.2.3")!)
        #expect(Version("1.2.3_2")! > Version("1.2.3_1")!)
    }

    @Test func trailingZerosAreEqual() {
        #expect(Version("1.0")! == Version("1.0.0")!)
        #expect(Version("2.0.0.0")! == Version("2")!)
    }

    @Test func extractsFromToolOutput() {
        #expect(Version.extract(from: "ripgrep 15.2.0")?.description == "15.2.0")
        #expect(Version.extract(from: "uv 0.9.26 (ee4f00362 2026-01-15)")?.description == "0.9.26")
        #expect(Version.extract(from: "go version go1.27.2 darwin/arm64")?.description == "1.27.2")
        #expect(Version.extract(from: "eza - A modern ls\nv0.23.5 [+git]")?.description == "0.23.5")
        #expect(
            Version.extract(
                from: "Client Version: v1.33.9",
                regex: #"Client Version:\s*v?([0-9]+(?:\.[0-9]+)+)"#
            )?.description == "1.33.9"
        )
    }

    @Test func rejectsNonVersions() {
        #expect(Version("") == nil)
        #expect(Version("latest") == nil)
    }
}
