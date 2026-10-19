import Foundation
import Testing

@testable import RemigeCore

struct UpdateHistoryTests {
    @Test func historyRoundTripsAndSortsNewestFirst() async throws {
        let url = temporaryDirectory().appendingPathComponent("history.json")
        let store = UpdateHistoryStore(url: url)
        let older = UpdateHistoryEntry(
            itemID: "brew:old",
            name: "Old App",
            source: .homebrew,
            fromVersion: "1.0",
            toVersion: "1.1",
            status: .success,
            date: Date(timeIntervalSince1970: 10)
        )
        let newer = UpdateHistoryEntry(
            itemID: "npm:new",
            name: "New App",
            source: .npm,
            fromVersion: "2.0",
            toVersion: "2.1",
            status: .success,
            date: Date(timeIntervalSince1970: 20)
        )

        _ = await store.append(older)
        _ = await store.append(newer)

        let entries = await store.load()
        #expect(entries.map(\.id) == [newer.id, older.id])
        #expect(entries[0].versionLine == "2.0 → 2.1")

        let reloaded = UpdateHistoryStore(url: url)
        #expect(await reloaded.load() == entries)
    }

    @Test func historyPreservesFailureAndCancellationDetails() async throws {
        let url = temporaryDirectory().appendingPathComponent("history.json")
        let store = UpdateHistoryStore(url: url)
        let failed = UpdateHistoryEntry(
            itemID: "brew:failed",
            name: "Failed App",
            source: .homebrew,
            fromVersion: nil,
            toVersion: "?",
            status: .failed,
            message: "exit 1"
        )
        let cancelled = UpdateHistoryEntry(
            itemID: "brew:cancelled",
            name: "Cancelled App",
            source: .homebrew,
            fromVersion: "3.0",
            toVersion: "3.1",
            status: .cancelled,
            message: "cancelled"
        )

        _ = await store.append(failed)
        _ = await store.append(cancelled)

        let entries = await store.load()
        #expect(entries.contains { $0.status == .failed && $0.message == "exit 1" })
        #expect(entries.contains { $0.status == .cancelled && $0.versionLine == "3.0 → 3.1" })
    }
}
