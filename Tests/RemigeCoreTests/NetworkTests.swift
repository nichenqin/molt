import Foundation
import Testing

@testable import RemigeCore

struct NetworkTests {
    @Test func latestGitHubTagFollowsRedirect() async {
        let counter = Counter()
        let http = FakeHTTP { url, _, _, method in
            _ = counter.increment()
            return HTTPResponse(
                status: 200,
                data: Data(),
                finalURL: URL(string: "https://github.com/astral-sh/uv/releases/tag/0.13.1")!
            )
        }
        let resolver = LatestTagResolver(http: http, cache: makeCache())
        let tag = await resolver.resolve(.github(RepoRef(owner: "astral-sh", name: "uv")))
        #expect(tag?.version == "0.13.1")
        #expect(tag?.display == "0.13.1")
        #expect(counter.count == 1)

        // Cached result avoids a second request.
        _ = await resolver.resolve(.github(RepoRef(owner: "astral-sh", name: "uv")))
        #expect(counter.count == 1)
    }

    @Test func latestTextRegex() async {
        let http = FakeHTTP { url, _, _, _ in
            response("go1.27.2\ntime 2026-10-02T20:28:03Z", url: url)
        }
        let resolver = LatestTagResolver(http: http, cache: makeCache())
        let tag = await resolver.resolve(
            .text(URL(string: "https://go.dev/VERSION?m=text")!, regex: #"go(\d+(?:\.\d+)+)"#)
        )
        #expect(tag?.version == "1.27.2")
    }

    @Test func latestReturnsNilWithoutTag() async {
        let http = FakeHTTP { url, _, _, _ in
            HTTPResponse(status: 404, data: Data(), finalURL: url)
        }
        let resolver = LatestTagResolver(http: http, cache: makeCache())
        let tag = await resolver.resolve(.github(RepoRef(owner: "nope", name: "nope")))
        #expect(tag == nil)
    }

    @Test func npmRegistryBuildsScopedURLAndParsesRepo() async {
        let http = FakeHTTP { url, _, _, _ in
            #expect(url.absoluteString == "https://registry.npmjs.org/@teable%2Fcli/latest")
            return response(
                #"{"name":"@teable/cli","version":"0.6.45","description":"CLI","homepage":"https://teable.io","repository":{"type":"git","url":"git+https://github.com/teableio/teable-enterprise.git"}}"#,
                url: url
            )
        }
        let registry = NpmRegistry(http: http, cache: makeCache())
        let info = await registry.latest(package: "@teable/cli")
        #expect(info?.version == "0.6.45")
        #expect(info?.repo == RepoRef(owner: "teableio", name: "teable-enterprise"))
        #expect(info?.summary == "CLI")
    }

    @Test func repoParsingHandlesEcosystemShapes() {
        #expect(RepoRef(urlLike: "git+https://github.com/a/b.git") == RepoRef(owner: "a", name: "b"))
        #expect(RepoRef(urlLike: "git@github.com:a/b.git") == RepoRef(owner: "a", name: "b"))
        #expect(RepoRef(urlLike: "github:a/b") == RepoRef(owner: "a", name: "b"))
        #expect(RepoRef(urlLike: "https://github.com/a/b/tree/main/pkg") == RepoRef(owner: "a", name: "b"))
        #expect(RepoRef(urlLike: "https://gitlab.com/a/b") == nil)
        #expect(RepoRef(urlLike: "a/b") == RepoRef(owner: "a", name: "b"))
    }

    private let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Release notes from example</title>
          <entry>
            <id>tag:github.com,2008:Repository/1/v2.0.0</id>
            <updated>2026-10-17T12:00:00Z</updated>
            <link rel="alternate" type="text/html" href="https://github.com/acme/example/releases/tag/v2.0.0"/>
            <title>v2.0.0</title>
            <content type="html">&lt;h2&gt;Big release&lt;/h2&gt;&lt;ul&gt;&lt;li&gt;Faster&lt;/li&gt;&lt;/ul&gt;</content>
          </entry>
          <entry>
            <id>tag:github.com,2008:Repository/1/v1.0.0</id>
            <updated>2026-09-01T12:00:00Z</updated>
            <link rel="alternate" href="https://github.com/acme/example/releases/tag/v1.0.0"/>
            <title>v1.0.0</title>
            <content type="html">&lt;p&gt;First&lt;/p&gt;</content>
          </entry>
        </feed>
        """

    @Test func atomChangelogParsesAndCaches() async {
        let counter = Counter()
        let http = FakeHTTP { url, _, _, _ in
            _ = counter.increment()
            return response(self.atom, url: url)
        }
        let cache = makeCache()
        let service = ChangelogService(http: http, cache: cache)
        let item = OutdatedItem(
            id: "brew:formula:example",
            name: "example",
            source: .homebrew,
            kind: .formula,
            currentVersion: "1.0.0",
            latestVersion: "2.0.0",
            repo: RepoRef(owner: "acme", name: "example"),
            changelogKind: .githubReleases,
            upgrade: .command("/usr/bin/true", [])
        )
        let result = await service.changelog(for: item)
        #expect(result.releases.count == 2)
        #expect(result.releases[0].version == "2.0.0")
        #expect(result.releases[0].bodyHTML.contains("<h2>Big release</h2>"))
        #expect(result.releases[0].publishedAt != nil)
        #expect(counter.count == 1)

        let cached = await service.changelog(for: item)
        #expect(cached.releases.count == 2)
        #expect(counter.count == 1)
    }

    @Test func htmlToPlainText() {
        let html = """
            <h2>Changes</h2><p>A &amp; B</p><ul><li>One</li><li>Two</li></ul>
            <script>alert(1)</script><p>Tail&nbsp;text</p>
            """
        let text = HTMLText.plain(from: html)
        #expect(text.contains("A & B"))
        #expect(text.contains("• One"))
        #expect(text.contains("Two"))
        #expect(!text.contains("alert"))
        #expect(text.contains("Tail text"))
    }
}
