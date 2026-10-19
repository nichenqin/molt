import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier ?? path }
    public var path: String
    public var bundleIdentifier: String?
    public var name: String
    public var shortVersion: String?
    public var buildVersion: String?
    public var feedURL: URL?
    /// Standard Electron Builder metadata; Sparkle feeds still take precedence.
    public var updateMetadata: AppUpdateMetadata?
    public var updateChannel: String?
    public var minimumSystemVersion: String?

    public var version: String? { shortVersion ?? buildVersion }

    public init(
        path: String,
        bundleIdentifier: String?,
        name: String,
        shortVersion: String?,
        buildVersion: String?,
        feedURL: URL?,
        updateChannel: String?,
        minimumSystemVersion: String?,
        updateMetadata: AppUpdateMetadata? = nil
    ) {
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.feedURL = feedURL
        self.updateChannel = updateChannel
        self.minimumSystemVersion = minimumSystemVersion
        self.updateMetadata = updateMetadata
    }
}

public enum AppScanner {
    public static func defaultDirectories(
        fileManager: FileManager = .default
    ) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ]
    }

    /// Finds app bundles two levels down (vendor folders are common) without
    /// descending into a bundle. System apps are not included.
    public static func scan(
        directories: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> [InstalledApp] {
        let roots = directories ?? defaultDirectories(fileManager: fileManager)
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for root in roots {
            walk(root, depth: 0, fileManager: fileManager, seen: &seen, apps: &apps)
        }
        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func walk(
        _ directory: URL,
        depth: Int,
        fileManager: FileManager,
        seen: inout Set<String>,
        apps: inout [InstalledApp]
    ) {
        guard depth <= 1 else { return }
        guard
            let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if child.pathExtension == "app" {
                guard seen.insert(child.path).inserted else { continue }
                if let app = readApp(at: child) {
                    apps.append(app)
                }
            } else if depth == 0 {
                walk(child, depth: depth + 1, fileManager: fileManager, seen: &seen, apps: &apps)
            }
        }
    }

    public static func readApp(at url: URL) -> InstalledApp? {
        guard !url.path.hasPrefix("/System/") else { return nil }
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
            let any = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let info = any as? [String: Any]
        else { return nil }

        let bundleID = info["CFBundleIdentifier"] as? String
        if let bundleID, bundleID.hasPrefix("com.apple.") { return nil }

        let name =
            (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        var feed: URL?
        if let raw = info["SUFeedURL"] as? String,
            let url = URL(string: raw),
            url.scheme?.lowercased() == "https"
        {
            feed = url
        }
        let metadata = feed == nil ? AppUpdateMetadataReader.read(fromAppAt: url) : nil
        return InstalledApp(
            path: url.path,
            bundleIdentifier: bundleID,
            name: name,
            shortVersion: info["CFBundleShortVersionString"] as? String,
            buildVersion: info["CFBundleVersion"].map { String(describing: $0) },
            feedURL: feed,
            updateChannel: info["SUUpdateChannel"] as? String,
            minimumSystemVersion: info["LSMinimumSystemVersion"] as? String,
            updateMetadata: metadata
        )
    }
}
