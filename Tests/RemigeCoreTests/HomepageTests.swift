import Foundation
import Testing

@testable import RemigeCore

struct HomepageTests {
    private func item(homepage: URL? = nil, repo: RepoRef? = nil) -> OutdatedItem {
        OutdatedItem(
            id: "brew:formula:pkg",
            name: "pkg",
            source: .homebrew,
            kind: .formula,
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            homepage: homepage,
            repo: repo,
            upgrade: .command("/opt/homebrew/bin/brew", ["upgrade", "pkg"])
        )
    }

    @Test func prefersDeclaredHomepage() {
        let homepage = URL(string: "https://example.com/pkg")!
        let resolved = item(
            homepage: homepage,
            repo: RepoRef(owner: "acme", name: "pkg")
        ).homepageURL

        #expect(resolved == homepage)
    }

    @Test func fallsBackToRepositoryPage() {
        let resolved = item(homepage: nil, repo: RepoRef(owner: "acme", name: "pkg")).homepageURL

        #expect(resolved?.absoluteString == "https://github.com/acme/pkg")
    }

    @Test func hasNoHomepageWithoutHomepageOrRepository() {
        #expect(item().homepageURL == nil)
    }
}
