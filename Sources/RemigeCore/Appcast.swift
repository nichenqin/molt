import Foundation

public struct AppcastItem: Hashable, Sendable {
    public var title: String?
    public var shortVersion: String?
    public var buildVersion: String?
    public var channel: String?
    public var minimumSystemVersion: String?
    public var publishDate: Date?
    public var downloadURL: URL?
    public var releaseNotesURL: URL?
    public var notesHTML: String?

    public var displayVersion: String? { shortVersion ?? buildVersion }
    public var compareVersion: String? { shortVersion ?? buildVersion }
}

public enum AppcastError: LocalizedError {
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let message): "Could not parse appcast: \(message)"
        }
    }
}

/// Minimal Sparkle RSS parser. Namespace prefixes are kept by Foundation, so
/// both `sparkle:shortVersionString` and legacy `shortVersionString` work.
public final class AppcastParser: NSObject, XMLParserDelegate {
    private var items: [AppcastItem] = []
    private var current: AppcastItem?
    private var text = ""
    private var currentElement = ""
    private var descriptionDepth = 0
    private var parseError: Error?

    public static func parse(_ data: Data) throws -> [AppcastItem] {
        let delegate = AppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw AppcastError.unreadable(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return delegate.items
    }

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = Self.localName(elementName)
        currentElement = local
        text = ""
        if local == "item" {
            current = AppcastItem()
        } else if descriptionDepth > 0 {
            descriptionDepth += 1
        } else if local == "description" {
            descriptionDepth = 1
            text = ""
        } else if local == "enclosure", current != nil {
            if let raw = attributeDict["url"], let url = URL(string: raw) {
                let isDelta =
                    url.pathExtension.lowercased() == "delta"
                    || attributeDict.keys.contains {
                        $0.lowercased().hasSuffix("deltafrom")
                            || $0.lowercased().hasSuffix("deltatom")
                    }
                // Sparkle lists a full package and a much smaller delta for the
                // same version. A delta is useless outside Sparkle, so keep the
                // full enclosure for one-click download links.
                if !isDelta {
                    current?.downloadURL = url
                }
            }
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if descriptionDepth > 0 {
            if var item = current {
                item.notesHTML = (item.notesHTML ?? "") + string
                current = item
            }
        } else {
            text += string
        }
    }

    public func parser(_ parser: XMLParser, foundCDATA data: Data) {
        let string = String(decoding: data, as: UTF8.self)
        if descriptionDepth > 0 {
            if var item = current {
                item.notesHTML = (item.notesHTML ?? "") + string
                current = item
            }
        } else {
            text += string
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = Self.localName(elementName)
        if descriptionDepth > 0 {
            descriptionDepth -= 1
            if descriptionDepth == 0, var item = current {
                item.notesHTML = Self.limit(item.notesHTML)
                current = item
            }
            return
        }
        guard var item = current else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch local {
        case "title": item.title = value
        case "shortVersionString": item.shortVersion = value
        case "version": item.buildVersion = value
        case "channel": item.channel = value
        case "minimumSystemVersion": item.minimumSystemVersion = value
        case "releaseNotesLink":
            if !value.isEmpty { item.releaseNotesURL = URL(string: value) }
        case "pubDate": item.publishDate = Self.date(from: value)
        case "item":
            items.append(item)
            current = nil
            text = ""
            return
        default: break
        }
        current = item
        text = ""
    }

    private static func localName(_ name: String) -> String {
        if let colon = name.firstIndex(of: ":") {
            return String(name[name.index(after: colon)...])
        }
        return name
    }

    private static func limit(_ html: String?) -> String? {
        guard let html else { return nil }
        return html.count > 60_000 ? String(html.prefix(60_000)) : html
    }

    private static func date(from value: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

public struct AppcastSelection: Sendable {
    public var item: AppcastItem
    /// A newer feed item was skipped because it requires a newer macOS.
    public var osFiltered: Bool

    public init(item: AppcastItem, osFiltered: Bool) {
        self.item = item
        self.osFiltered = osFiltered
    }
}

public enum AppcastSelector {
    /// Picks the newest item the running app is allowed to see.
    public static func select(
        items: [AppcastItem],
        installedVersion: String,
        updateChannel: String?,
        currentOS: String?
    ) -> AppcastSelection? {
        guard let installed = Version(installedVersion) else { return nil }
        let currentOSVersion = currentOS.flatMap(Version.init)
        var best: (item: AppcastItem, version: Version, build: Version?)?
        var blockedByOS: Version?

        for item in items {
            if let channel = item.channel?.trimmingCharacters(in: .whitespaces), !channel.isEmpty {
                guard let updateChannel,
                    channel.caseInsensitiveCompare(updateChannel) == .orderedSame
                else { continue }
            }
            guard let raw = item.compareVersion, let version = Version(raw), version > installed else {
                continue
            }
            if let minimum = item.minimumSystemVersion, let minimumVersion = Version(minimum) {
                if let currentOSVersion, currentOSVersion < minimumVersion {
                    if let previous = blockedByOS {
                        if version > previous { blockedByOS = version }
                    } else {
                        blockedByOS = version
                    }
                    continue
                }
            }
            let build = item.buildVersion.flatMap(Version.init)
            if let currentBest = best {
                if version > currentBest.version {
                    best = (item, version, build)
                } else if version == currentBest.version,
                    let build,
                    let bestBuild = currentBest.build,
                    build > bestBuild
                {
                    best = (item, version, build)
                } else if version == currentBest.version,
                    currentBest.item.downloadURL == nil,
                    item.downloadURL != nil
                {
                    best = (item, version, build)
                }
            } else {
                best = (item, version, build)
            }
        }
        guard let best else { return nil }
        let osFiltered = blockedByOS.map { $0 > best.version } ?? false
        return AppcastSelection(item: best.item, osFiltered: osFiltered)
    }

    public static func latest(
        items: [AppcastItem],
        installedVersion: String,
        updateChannel: String?,
        currentOS: String?
    ) -> AppcastItem? {
        select(
            items: items,
            installedVersion: installedVersion,
            updateChannel: updateChannel,
            currentOS: currentOS
        )?.item
    }
}
