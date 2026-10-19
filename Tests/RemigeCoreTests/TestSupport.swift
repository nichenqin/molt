import Foundation

@testable import RemigeCore

struct FakeHTTP: HTTPGetting {
    let handler: @Sendable (URL, [String: String], TimeInterval, String) async throws -> HTTPResponse

    init(
        handler: @escaping @Sendable (URL, [String: String], TimeInterval, String) async throws -> HTTPResponse
    ) {
        self.handler = handler
    }

    init(response: @escaping @Sendable (URL) -> HTTPResponse?) {
        self.handler = { url, _, _, _ in
            guard let response = response(url) else {
                throw HTTPError.invalidResponse(url)
            }
            return response
        }
    }

    func get(
        _ url: URL,
        headers: [String: String],
        timeout: TimeInterval,
        method: String
    ) async throws -> HTTPResponse {
        try await handler(url, headers, timeout, method)
    }
}

struct FakeRunner: CommandRunning {
    let handler: @Sendable (CommandSpec) async -> CommandResult

    init(handler: @escaping @Sendable (CommandSpec) async -> CommandResult) {
        self.handler = handler
    }

    init(output: String, exitCode: Int32 = 0, stderr: String = "") {
        self.handler = { _ in
            CommandResult(
                stdout: Data(output.utf8),
                stderr: Data(stderr.utf8),
                exitCode: exitCode,
                duration: 0
            )
        }
    }

    func run(_ command: CommandSpec, timeout: TimeInterval) async -> CommandResult {
        await handler(command)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("remige-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeCache() -> DiskCache {
    DiskCache(directory: temporaryDirectory())
}

func response(
    _ body: String,
    status: Int = 200,
    url: URL = URL(string: "https://example.com")!,
    headers: [String: String] = [:]
) -> HTTPResponse {
    HTTPResponse(status: status, data: Data(body.utf8), headers: headers, finalURL: url)
}
