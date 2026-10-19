import Foundation
import Testing

@testable import RemigeCore

struct AppcastTests {
    private let feed = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <title>Example</title>
            <item>
              <title>2.0.0 beta</title>
              <sparkle:channel>beta</sparkle:channel>
              <sparkle:version>900</sparkle:version>
              <sparkle:shortVersionString>2.0.0</sparkle:shortVersionString>
              <enclosure url="https://example.com/Example-2.0.0.dmg" />
            </item>
            <item>
              <title>1.4.0</title>
              <pubDate>Tue, 13 Oct 2026 21:21:34 +0000</pubDate>
              <sparkle:version>140</sparkle:version>
              <sparkle:shortVersionString>1.4.0</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
              <sparkle:releaseNotesLink>https://example.com/notes/1.4.0.html</sparkle:releaseNotesLink>
              <description><![CDATA[<h3>What's new</h3><ul><li>Faster</li></ul>]]></description>
              <enclosure url="https://example.com/Example-1.4.0.delta" sparkle:deltaFrom="1.3.9" />
              <enclosure url="https://example.com/Example-1.4.0.dmg" length="1000" />
            </item>
            <item>
              <title>9.0.0</title>
              <sparkle:version>9000</sparkle:version>
              <sparkle:shortVersionString>9.0.0</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
              <enclosure url="https://example.com/Example-9.0.0.dmg" />
            </item>
          </channel>
        </rss>
        """

    @Test func parsesNamespacedFieldsAndFullEnclosure() throws {
        let items = try AppcastParser.parse(Data(feed.utf8))
        #expect(items.count == 3)
        let stable = items[1]
        #expect(stable.shortVersion == "1.4.0")
        #expect(stable.buildVersion == "140")
        #expect(stable.minimumSystemVersion == "11.0")
        #expect(stable.releaseNotesURL?.absoluteString == "https://example.com/notes/1.4.0.html")
        #expect(stable.notesHTML?.contains("Faster") == true)
        #expect(stable.downloadURL?.lastPathComponent == "Example-1.4.0.dmg")
        #expect(stable.publishDate != nil)
    }

    @Test func selectorSkipsChannelsAndIncompatibleSystems() throws {
        let items = try AppcastParser.parse(Data(feed.utf8))
        let latest = AppcastSelector.latest(
            items: items,
            installedVersion: "1.3.9",
            updateChannel: nil,
            currentOS: "26.5.1"
        )
        #expect(latest?.shortVersion == "1.4.0")
    }

    @Test func selectionReportsOSFilteredVersions() throws {
        let items = try AppcastParser.parse(Data(feed.utf8))
        let selection = AppcastSelector.select(
            items: items,
            installedVersion: "1.3.9",
            updateChannel: nil,
            currentOS: "26.5.1"
        )
        #expect(selection?.item.shortVersion == "1.4.0")
        #expect(selection?.osFiltered == true)
    }

    @Test func selectorHonorsMatchingChannel() throws {
        let items = try AppcastParser.parse(Data(feed.utf8))
        let latest = AppcastSelector.latest(
            items: items,
            installedVersion: "1.3.9",
            updateChannel: "beta",
            currentOS: "26.5.1"
        )
        #expect(latest?.shortVersion == "2.0.0")
    }

    @Test func selectorReturnsNilWhenCurrent() throws {
        let items = try AppcastParser.parse(Data(feed.utf8))
        #expect(
            AppcastSelector.latest(
                items: items,
                installedVersion: "1.4.0",
                updateChannel: nil,
                currentOS: "26.5.1"
            ) == nil
        )
    }

    @Test func selectorPrefersFullDownloadForDuplicateVersion() {
        var delta = AppcastItem()
        delta.shortVersion = "2.0.0"
        delta.buildVersion = "200"
        var full = delta
        full.downloadURL = URL(string: "https://example.com/full.zip")

        let selected = AppcastSelector.latest(
            items: [delta, full],
            installedVersion: "1.0.0",
            updateChannel: nil,
            currentOS: "26.0"
        )
        #expect(selected?.downloadURL?.absoluteString == "https://example.com/full.zip")
    }

    @Test func parsesNilOnBrokenXML() {
        #expect(throws: AppcastError.self) {
            try AppcastParser.parse(Data("<rss><item>".utf8))
        }
    }
}
