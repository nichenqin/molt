import Foundation

// MARK: - Commands

public struct CommandSpec: Hashable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var currentDirectory: String?

    public init(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        currentDirectory: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
    }

    public var display: String {
        ([executable] + arguments).map(ShellQuote.word).joined(separator: " ")
    }
}

public struct CommandResult: Sendable {
    public var stdout: Data
    public var stderr: Data
    public var exitCode: Int32
    public var timedOut: Bool
    public var duration: TimeInterval
    public var launchError: String?

    public init(
        stdout: Data = Data(),
        stderr: Data = Data(),
        exitCode: Int32 = -1,
        timedOut: Bool = false,
        duration: TimeInterval = 0,
        launchError: String? = nil
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.duration = duration
        self.launchError = launchError
    }

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
    public var succeeded: Bool { exitCode == 0 && !timedOut && launchError == nil }

    /// Human-readable failure for UI and CLI. Keeps the useful tail of stderr.
    public var failureMessage: String? {
        if let launchError { return launchError }
        if timedOut { return "Timed out" }
        guard exitCode != 0 else { return nil }
        let err = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty {
            return String(err.suffix(800))
        }
        let out = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "Exited with status \(exitCode)" : String(out.suffix(800))
    }
}

public protocol CommandRunning: Sendable {
    func run(_ command: CommandSpec, timeout: TimeInterval) async -> CommandResult
}

public enum CommandError: LocalizedError {
    case launch(String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .launch(let message): message
        case .timeout(let message): "Timed out: \(message)"
        }
    }
}

// MARK: - Process runner

public final class ProcessRunner: CommandRunning, @unchecked Sendable {
    private let baseEnvironment: [String: String]

    public init(environment: [String: String]? = nil) {
        self.baseEnvironment = environment ?? EnvironmentSnapshot.current()
    }

    public func run(_ command: CommandSpec, timeout: TimeInterval) async -> CommandResult {
        let start = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        var environment = baseEnvironment
        for (key, value) in command.environment { environment[key] = value }
        process.environment = environment
        if let directory = command.currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return CommandResult(
                exitCode: -1,
                duration: Date().timeIntervalSince(start),
                launchError: "Could not launch \(command.executable): \(error.localizedDescription)"
            )
        }

        async let stdout = Self.readAll(stdoutPipe.fileHandleForReading)
        async let stderr = Self.readAll(stderrPipe.fileHandleForReading)

        let timedOut = await Self.wait(process: process, timeout: timeout)
        let out = await stdout
        let err = await stderr
        return CommandResult(
            stdout: out,
            stderr: err,
            exitCode: process.terminationStatus,
            timedOut: timedOut,
            duration: Date().timeIntervalSince(start)
        )
    }

    private static func wait(process: Process, timeout: TimeInterval) async -> Bool {
        guard timeout > 0 else {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in continuation.resume() }
            }
            return false
        }
        let timeoutTask = Task.detached { () -> Bool in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return !Task.isCancelled
        }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    DispatchQueue.global(qos: .utility).async {
                        process.waitUntilExit()
                        continuation.resume(returning: false)
                    }
                }
            }
            group.addTask { await timeoutTask.value }
            let first = await group.next() ?? false
            timeoutTask.cancel()
            if first {
                process.terminate()
                // Give it a moment, then make sure a stuck child does not block us.
                try? await Task.sleep(nanoseconds: 800_000_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                group.cancelAll()
                return true
            }
            group.cancelAll()
            return false
        }
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = (try? handle.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }
}

// MARK: - Environment

public enum EnvironmentSnapshot {
    /// GUI apps get launchd's minimal PATH. Compose the paths a login shell would
    /// normally provide without sourcing shell startup files (which can be slow or
    /// interactive).
    public static func current(extraPaths: [String] = []) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path(extra: extraPaths)
        environment["HOMEBREW_NO_AUTO_UPDATE"] = environment["HOMEBREW_NO_AUTO_UPDATE"] ?? "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_COLOR"] = "1"
        environment["NO_COLOR"] = environment["NO_COLOR"] ?? "1"
        return environment
    }

    public static func path(extra: [String] = []) -> String {
        let home = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.volta/bin",
            "\(home)/.bun/bin",
            "\(home)/.deno/bin",
            "\(home)/Library/pnpm",
            "\(home)/.local/share/pnpm",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        // /etc/paths and /etc/paths.d are the system's canonical extra paths.
        candidates.append(contentsOf: systemPaths())
        candidates.append(contentsOf: extra)

        // Preserve a user's existing PATH entries too, then de-duplicate.
        if let existing = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: existing.split(separator: ":").map(String.init))
        }
        var seen = Set<String>()
        return
            candidates
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
    }

    private static func systemPaths() -> [String] {
        var result: [String] = []
        if let content = try? String(contentsOfFile: "/etc/paths", encoding: .utf8) {
            result.append(contentsOf: content.split(separator: "\n").map(String.init))
        }
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: "/etc/paths.d") {
            for entry in entries.sorted() {
                if let content = try? String(contentsOfFile: "/etc/paths.d/\(entry)", encoding: .utf8) {
                    result.append(contentsOf: content.split(separator: "\n").map(String.init))
                }
            }
        }
        return result
    }
}

// MARK: - Locator

public struct ExecutableLocator: Sendable {
    private let directories: [String]

    public init(path: String? = nil) {
        let raw = path ?? EnvironmentSnapshot.path()
        self.directories = raw.split(separator: ":").map(String.init)
    }

    public init(directories: [String]) {
        self.directories = directories
    }

    /// Absolute, symlink-resolved executable path.
    public func find(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for directory in directories {
            let candidate = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            }
        }
        return nil
    }

    /// The path as invoked (not symlink-resolved), useful for display and for
    /// detecting manager ownership before the real path is inspected.
    public func findLink(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for directory in directories {
            let candidate = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    public var searchPath: [String] { directories }
}
