import Foundation

public enum Concurrency {
    /// Runs at most `limit` transforms at once, preserving input order.
    /// Failures become nil so one bad package never sinks a whole source.
    public static func map<T: Sendable, R: Sendable>(
        _ items: [T],
        limit: Int = 8,
        _ transform: @Sendable @escaping (T) async -> R?
    ) async -> [R?] {
        guard !items.isEmpty, limit > 0 else { return Array(repeating: nil, count: items.count) }
        var results = [R?](repeating: nil, count: items.count)
        var start = 0
        while start < items.count {
            let end = min(start + limit, items.count)
            let slice = Array(items[start..<end])
            await withTaskGroup(of: (Int, R?).self) { group in
                for (offset, item) in slice.enumerated() {
                    group.addTask {
                        (start + offset, await transform(item))
                    }
                }
                for await (index, value) in group {
                    results[index] = value
                }
            }
            start = end
        }
        return results
    }
}

public enum TimeoutError: LocalizedError {
    case expired(String)

    public var errorDescription: String? {
        switch self {
        case .expired(let label): "\(label) timed out"
        }
    }
}

/// Races an operation against a deadline and cancels it on timeout.
public func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    label: String,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0.01, seconds) * 1_000_000_000))
            throw TimeoutError.expired(label)
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else {
            throw TimeoutError.expired(label)
        }
        return value
    }
}
