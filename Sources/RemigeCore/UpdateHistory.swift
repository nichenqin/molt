import Foundation

public enum UpdateHistoryStatus: String, Codable, Hashable, Sendable {
    case success
    case failed
    case cancelled
}

public struct UpdateHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let itemID: String
    public let name: String
    public let source: SourceKind
    public let fromVersion: String?
    public let toVersion: String?
    public let status: UpdateHistoryStatus
    public let date: Date
    public let message: String?

    public init(
        id: UUID = UUID(),
        itemID: String,
        name: String,
        source: SourceKind,
        fromVersion: String?,
        toVersion: String?,
        status: UpdateHistoryStatus,
        date: Date = Date(),
        message: String? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.name = name
        self.source = source
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.status = status
        self.date = date
        self.message = message
    }

    public var versionLine: String {
        "\(fromVersion ?? "?") → \(toVersion ?? "?")"
    }
}

/// Persists the updates Remige actually attempted, separately from the expiring scan cache.
public actor UpdateHistoryStore {
    private static let maximumEntries = 100
    private let url: URL
    private var entries: [UpdateHistoryEntry]?

    public init(url: URL? = nil) {
        self.url =
            url
            ?? ConfigStore.defaultURL
            .deletingLastPathComponent()
            .appendingPathComponent("update-history.json")
    }

    public func load() -> [UpdateHistoryEntry] {
        if let entries { return entries }
        guard let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder.remige.decode([UpdateHistoryEntry].self, from: data)
        else {
            entries = []
            return []
        }
        entries = sorted(decoded)
        return entries ?? []
    }

    @discardableResult
    public func append(_ entry: UpdateHistoryEntry) -> [UpdateHistoryEntry] {
        var updated = load()
        guard !updated.contains(where: { $0.id == entry.id }) else { return updated }
        updated.append(entry)
        updated = Array(sorted(updated).prefix(Self.maximumEntries))
        entries = updated
        guard let data = try? JSONEncoder.remige.encode(updated) else { return updated }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
        return updated
    }

    private func sorted(_ entries: [UpdateHistoryEntry]) -> [UpdateHistoryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }
}
