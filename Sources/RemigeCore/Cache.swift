import CryptoKit
import Foundation

/// Small JSON/data cache with TTLs and atomic writes.
///
/// Files live in `~/Library/Caches/app.remige` by default. Every write
/// is atomic, so a crash never leaves a half-written snapshot for the next
/// launch to parse.
public actor DiskCache {
    private struct Envelope<T: Codable>: Codable {
        var savedAt: Date
        var value: T
    }

    public struct HTTPEntry: Codable, Sendable {
        public var savedAt: Date
        public var etag: String?
        public var finalURL: String
        public var data: Data
    }

    /// Bundle identifier of the shipping app; it also names the cache directory
    /// and the macOS preferences domain. Keep in sync with `Resources/Info.plist`.
    public static let bundleIdentifier = "app.remige"

    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        if let directory {
            self.directory = directory
        } else if let override = ProcessInfo.processInfo.environment["REMIGE_CACHE_DIR"], !override.isEmpty {
            self.directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let base =
                fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches")
            self.directory = base.appendingPathComponent(Self.bundleIdentifier, isDirectory: true)
        }
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["REMIGE_CACHE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches")
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    public func read<T: Codable>(_ type: T.Type, key: String, maxAge: TimeInterval) -> T? {
        guard let envelope: Envelope<T> = decode(key: key),
            Date().timeIntervalSince(envelope.savedAt) <= maxAge
        else { return nil }
        return envelope.value
    }

    public func readIgnoringAge<T: Codable>(_ type: T.Type, key: String) -> T? {
        let envelope: Envelope<T>? = decode(key: key)
        return envelope?.value
    }

    public func write<T: Codable>(_ value: T, key: String) {
        let envelope = Envelope(savedAt: Date(), value: value)
        guard let data = try? JSONEncoder.remige.encode(envelope) else { return }
        writeAtomically(data, to: fileURL(key: key))
    }

    public func readHTTP(_ url: URL, maxAge: TimeInterval) -> HTTPEntry? {
        guard let envelope: Envelope<HTTPEntry> = decode(key: "http:" + url.absoluteString),
            Date().timeIntervalSince(envelope.savedAt) <= maxAge
        else { return nil }
        return envelope.value
    }

    public func readHTTPIgnoringAge(_ url: URL) -> HTTPEntry? {
        let envelope: Envelope<HTTPEntry>? = decode(key: "http:" + url.absoluteString)
        return envelope?.value
    }

    public func writeHTTP(_ response: HTTPResponse, for url: URL) {
        let entry = HTTPEntry(
            savedAt: Date(),
            etag: response.etag,
            finalURL: response.finalURL.absoluteString,
            data: response.data
        )
        let envelope = Envelope(savedAt: Date(), value: entry)
        guard let data = try? JSONEncoder.remige.encode(envelope) else { return }
        writeAtomically(data, to: fileURL(key: "http:" + url.absoluteString))
    }

    public func remove(key: String) {
        try? fileManager.removeItem(at: fileURL(key: key))
    }

    public func clear() {
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return }
        for entry in entries where entry.pathExtension == "json" || entry.pathExtension == "data" {
            try? fileManager.removeItem(at: entry)
        }
    }

    public func sizeOnDisk() -> Int64 {
        guard
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: Private

    private func decode<T: Decodable>(key: String) -> Envelope<T>? {
        guard let data = try? Data(contentsOf: fileURL(key: key)) else { return nil }
        return try? JSONDecoder.remige.decode(Envelope<T>.self, from: data)
    }

    private func fileURL(key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hex + ".json")
    }

    private func writeAtomically(_ data: Data, to url: URL) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }
}

// MARK: - Snapshot store

public struct SnapshotStore: Sendable {
    private let cache: DiskCache
    private let key = "scan:snapshot"

    public init(cache: DiskCache = DiskCache()) {
        self.cache = cache
    }

    public func load(maxAge: TimeInterval = .infinity) async -> ScanSnapshot? {
        if maxAge == .infinity {
            return await cache.readIgnoringAge(ScanSnapshot.self, key: key)
        }
        return await cache.read(ScanSnapshot.self, key: key, maxAge: maxAge)
    }

    public func save(_ snapshot: ScanSnapshot) async {
        await cache.write(snapshot, key: key)
    }
}

// MARK: - JSON

extension JSONEncoder {
    public static var remige: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    public static var remige: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
