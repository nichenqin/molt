import Foundation
import MoltCore
import Testing

@testable import MoltCLIKit

struct ArgumentTests {
    @Test func parsesCommandPositionalsOptionsAndFlags() {
        let parsed = ArgumentParser.parse([
            "upgrade", "cc-switch", "brew:formula:sqlite",
            "--yes", "--dry-run", "--source", "homebrew", "--limit=3",
        ])
        #expect(parsed.command == "upgrade")
        #expect(parsed.positionals == ["cc-switch", "brew:formula:sqlite"])
        #expect(parsed.flag("yes"))
        #expect(parsed.flag("dry-run"))
        #expect(parsed.value("source") == "homebrew")
        #expect(parsed.value("limit") == "3")
        #expect(parsed.errors.isEmpty)
    }

    @Test func parsesShortFlags() {
        let parsed = ArgumentParser.parse(["list", "-j", "-q", "--no-color"])
        #expect(parsed.command == "list")
        #expect(parsed.flag("json"))
        #expect(parsed.flag("quiet"))
        #expect(parsed.flag("no-color"))
    }

    @Test func rejectsUnknownOptions() {
        #expect(!ArgumentParser.parse(["list", "--wat"]).errors.isEmpty)
        #expect(!ArgumentParser.parse(["list", "--source"]).errors.isEmpty)
        #expect(!ArgumentParser.parse(["list", "-z"]).errors.isEmpty)
    }

    @Test func doubleDashStopsOptionParsing() {
        let parsed = ArgumentParser.parse(["upgrade", "--", "--dry-run"])
        #expect(parsed.positionals == ["--dry-run"])
        #expect(!parsed.flag("dry-run"))
    }
}

struct QueryAndFormatTests {
    private func item(
        id: String,
        name: String,
        display: String? = nil,
        source: SourceKind = .homebrew
    ) -> OutdatedItem {
        OutdatedItem(
            id: id,
            name: name,
            displayName: display,
            source: source,
            kind: source == .homebrew ? .formula : .binary,
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            upgrade: .command("/bin/true", [])
        )
    }

    @Test func resolvesExactIDNameAndUniqueSubstring() throws {
        let items = [
            item(id: "brew:formula:sqlite", name: "sqlite"),
            item(id: "npm:vercel", name: "vercel", source: .npm),
        ]
        #expect(try CLIQuery.resolve("brew:formula:sqlite", in: items).name == "sqlite")
        #expect(try CLIQuery.resolve("vercel", in: items).name == "vercel")
        #expect(try CLIQuery.resolve("sql", in: items).name == "sqlite")
    }

    @Test func rejectsAmbiguousAndMissingQueries() {
        let items = [
            item(id: "a", name: "foo-one"),
            item(id: "b", name: "foo-two"),
        ]
        #expect(throws: CLIError.self) { try CLIQuery.resolve("foo", in: items) }
        #expect(throws: CLIError.self) { try CLIQuery.resolve("missing", in: items) }
    }

    @Test func tableGroupsBySourceAndShowsVersions() {
        let items = [
            item(id: "brew:formula:sqlite", name: "sqlite"),
            item(id: "npm:vercel", name: "vercel", source: .npm),
        ]
        let text = CLIFormat.table(
            items: items,
            palette: .init(enabled: false)
        )
        #expect(text.contains("HOMEBREW"))
        #expect(text.contains("NPM"))
        #expect(text.contains("1.0.0"))
        #expect(text.contains("1.1.0"))
        #expect(text.contains("auto"))
    }
}
