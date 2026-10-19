import CryptoKit
import Foundation

// MARK: - Feed

public struct UpdateAsset: Codable, Hashable, Sendable {
    public var name: String
    public var url: URL
    public var sha256: String
    public var size: Int

    public init(name: String, url: URL, sha256: String, size: Int = 0) {
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.size = size
    }
}

public struct UpdateManifest: Codable, Sendable {
    public var schema: Int
    public var version: String
    public var published: Date?
    public var notes: String
    public var pageURL: URL?
    public var assets: [String: UpdateAsset]

    public init(
        schema: Int = 1,
        version: String,
        published: Date? = nil,
        notes: String = "",
        pageURL: URL? = nil,
        assets: [String: UpdateAsset] = [:]
    ) {
        self.schema = schema
        self.version = version
        self.published = published
        self.notes = notes
        self.pageURL = pageURL
        self.assets = assets
    }

    public var appZip: UpdateAsset? {
        assets["Molt-macos.zip"] ?? assets["Molt-macos-universal.zip"]
    }

    public var dmg: UpdateAsset? {
        assets["Molt-macos.dmg"] ?? assets["Molt-macos-universal.dmg"]
    }

    public var cli: UpdateAsset? {
        assets["molt-cli"]
    }
}

public struct AvailableUpdate: Sendable {
    public var manifest: UpdateManifest
    public var currentVersion: String
    public var latestVersion: String

    public init(manifest: UpdateManifest, currentVersion: String, latestVersion: String) {
        self.manifest = manifest
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
    }
}

// MARK: - Links

public enum MoltLinks {
    public static let repository = URL(string: "https://github.com/nichenqin/molt")!
    public static let releases = URL(string: "https://github.com/nichenqin/molt/releases")!
    public static let website = URL(string: "https://molt-site-five.vercel.app/")!
    public static let feed = URL(string: "https://molt-site-five.vercel.app/latest.json")!
    public static let installScript = URL(string: "https://molt-site-five.vercel.app/install.sh")!

    public static var configuredFeed: URL {
        if let raw = ProcessInfo.processInfo.environment["MOLT_UPDATE_FEED"],
            let url = URL(string: raw)
        {
            return url
        }
        return feed
    }
}

// MARK: - Errors

public enum UpdateError: LocalizedError {
    case feed(Int)
    case malformedFeed
    case newerVersionNotFound(String)
    case missingAsset(String)
    case checksumMismatch(expected: String, actual: String)
    case appNotWritable(String)
    case appTranslocated
    case extractionFailed(String)
    case invalidAppBundle(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .feed(let status): "Update server returned HTTP \(status)."
        case .malformedFeed: "The update feed is not valid JSON."
        case .newerVersionNotFound(let version): "Update \(version) is not newer than this build."
        case .missingAsset(let name): "Release \(name) is missing."
        case .checksumMismatch(let expected, let actual):
            "Checksum mismatch: expected \(expected), got \(actual)."
        case .appNotWritable(let path): "Molt cannot write to \(path). Move the app or use Homebrew."
        case .appTranslocated: "Molt is running from a translocated path. Move it to Applications first."
        case .extractionFailed(let message): "Could not extract the update: \(message)"
        case .invalidAppBundle(let message): "The downloaded app is invalid: \(message)"
        case .installFailed(let message): "Could not install the update: \(message)"
        }
    }
}

// MARK: - Service

public struct UpdateService: Sendable {
    private let http: HTTPGetting
    private let feedURL: URL
    private let currentVersion: String

    public init(
        http: HTTPGetting = URLSessionHTTPClient(),
        feedURL: URL = MoltLinks.configuredFeed,
        currentVersion: String = MoltVersion.current
    ) {
        self.http = http
        self.feedURL = feedURL
        self.currentVersion = currentVersion
    }

    public var runningVersion: String { currentVersion }

    /// Returns nil when this build is current. Throws only for transport or
    /// malformed-feed errors; a missing update is not an error.
    public func check() async throws -> AvailableUpdate? {
        let response = try await http.get(
            feedURL,
            headers: ["Accept": "application/json", "Cache-Control": "no-cache"],
            timeout: 15,
            method: "GET"
        )
        guard response.isSuccess else { throw UpdateError.feed(response.status) }
        let manifest: UpdateManifest
        do {
            manifest = try JSONDecoder.molt.decode(UpdateManifest.self, from: response.data)
        } catch {
            throw UpdateError.malformedFeed
        }
        guard let latest = Version(manifest.version), let current = Version(currentVersion) else {
            throw UpdateError.malformedFeed
        }
        guard latest > current else { return nil }
        return AvailableUpdate(
            manifest: manifest,
            currentVersion: currentVersion,
            latestVersion: manifest.version
        )
    }

    public func download(_ asset: UpdateAsset) async throws -> Data {
        guard asset.url.scheme?.lowercased() == "https" else {
            throw UpdateError.installFailed("Refusing a non-HTTPS update URL.")
        }
        let response = try await http.get(asset.url, timeout: 120)
        guard response.isSuccess else { throw UpdateError.feed(response.status) }
        let digest = SHA256.hash(data: response.data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest.caseInsensitiveCompare(asset.sha256) == .orderedSame else {
            throw UpdateError.checksumMismatch(expected: asset.sha256, actual: digest)
        }
        if asset.size > 0, response.data.count != asset.size {
            throw UpdateError.checksumMismatch(expected: "\(asset.size) bytes", actual: "\(response.data.count) bytes")
        }
        return response.data
    }
}

// MARK: - CLI installation

public enum CLIUpdater {
    /// Atomically replaces a CLI executable. Running binaries can be replaced
    /// on macOS; the new file takes effect on the next invocation.
    public static func install(data: Data, at target: URL) throws {
        let manager = FileManager.default
        let directory = target.deletingLastPathComponent()
        guard manager.isWritableFile(atPath: directory.path) else {
            throw UpdateError.appNotWritable(directory.path)
        }
        let temporary = directory.appendingPathComponent(".\(target.lastPathComponent).new-\(UUID().uuidString)")
        do {
            try data.write(to: temporary, options: [.atomic])
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
            _ = try manager.replaceItemAt(target, withItemAt: temporary)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        } catch {
            try? manager.removeItem(at: temporary)
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }
}

// MARK: - App installation

public enum AppUpdater {
    /// Prepares a downloaded app and starts a detached helper that waits for
    /// this process to exit, swaps the bundle, and relaunches it.
    @discardableResult
    public static func install(
        zipData: Data,
        expectedVersion: String,
        targetApp: URL = Bundle.main.bundleURL,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        relaunch: Bool = true
    ) throws -> URL {
        let manager = FileManager.default
        if targetApp.path.contains("/AppTranslocation/") {
            throw UpdateError.appTranslocated
        }
        let parent = targetApp.deletingLastPathComponent()
        guard manager.isWritableFile(atPath: parent.path) else {
            throw UpdateError.appNotWritable(parent.path)
        }

        let work = manager.temporaryDirectory
            .appendingPathComponent("molt-update-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: work, withIntermediateDirectories: true)
        var handedOff = false
        defer { if !handedOff { try? manager.removeItem(at: work) } }

        let zip = work.appendingPathComponent("update.zip")
        try zipData.write(to: zip, options: [.atomic])
        let extract = work.appendingPathComponent("extract", isDirectory: true)
        try manager.createDirectory(at: extract, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, extract.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            throw UpdateError.extractionFailed(error.localizedDescription)
        }
        guard ditto.terminationStatus == 0 else {
            throw UpdateError.extractionFailed("ditto exited \(ditto.terminationStatus)")
        }

        let candidates =
            (try? manager.contentsOfDirectory(
                at: extract,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        guard let newApp = candidates.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.invalidAppBundle("No .app bundle in the archive")
        }
        let plistURL = newApp.appendingPathComponent("Contents/Info.plist")
        guard let plist = try? Data(contentsOf: plistURL),
            let object = try? PropertyListSerialization.propertyList(from: plist, format: nil),
            let info = object as? [String: Any],
            let version = info["CFBundleShortVersionString"] as? String,
            Version(version) == Version(expectedVersion)
        else {
            throw UpdateError.invalidAppBundle("Version does not match \(expectedVersion)")
        }

        let staged = parent.appendingPathComponent(".Molt.app.update-\(UUID().uuidString)")
        let copy = Process()
        copy.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        copy.arguments = [newApp.path, staged.path]
        copy.standardOutput = FileHandle.nullDevice
        copy.standardError = FileHandle.nullDevice
        do {
            try copy.run()
            copy.waitUntilExit()
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
        guard copy.terminationStatus == 0 else {
            throw UpdateError.installFailed("ditto exited \(copy.terminationStatus)")
        }

        let backup = parent.appendingPathComponent(".Molt.app.old-\(UUID().uuidString)")
        let helper = work.appendingPathComponent("swap.sh")
        let relaunchLine = relaunch ? "open \(ShellQuote.word(targetApp.path))" : ""
        let script = """
            #!/bin/sh
            while kill -0 \(processID) 2>/dev/null; do sleep 0.2; done
            rm -rf \(ShellQuote.word(backup.path))
            if mv \(ShellQuote.word(targetApp.path)) \(ShellQuote.word(backup.path)); then
                if mv \(ShellQuote.word(staged.path)) \(ShellQuote.word(targetApp.path)); then
                    rm -rf \(ShellQuote.word(backup.path))
                    \(relaunchLine)
                else
                    mv \(ShellQuote.word(backup.path)) \(ShellQuote.word(targetApp.path))
                fi
            fi
            rm -rf \(ShellQuote.word(work.path))
            """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helper.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            handedOff = true
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
        return helper
    }
}
