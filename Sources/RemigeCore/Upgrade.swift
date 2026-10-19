import Foundation

public struct UpgradeResult: Codable, Sendable {
    public var itemID: String
    public var name: String
    public var command: String?
    public var success: Bool
    public var exitCode: Int32
    public var timedOut: Bool
    public var duration: TimeInterval
    public var message: String?
    public var output: String

    public init(
        itemID: String,
        name: String,
        command: String?,
        success: Bool,
        exitCode: Int32,
        timedOut: Bool = false,
        duration: TimeInterval = 0,
        message: String? = nil,
        output: String = ""
    ) {
        self.itemID = itemID
        self.name = name
        self.command = command
        self.success = success
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.duration = duration
        self.message = message
        self.output = output
    }

    /// True when the failure looks like a prompt that could not be answered
    /// because the child process had no terminal.
    public var requiresTerminal: Bool {
        guard !success, let command, !command.isEmpty else { return false }
        return InteractivePrompt.matches((message ?? "") + "\n" + String(output.suffix(8_000)))
    }
}

public enum UpgradeEvent: Sendable {
    case started(itemID: String, name: String, command: String)
    case output(String)
    case finished(UpgradeResult)
}

/// Builds the argv and environment shared by the app, the CLI and Terminal
/// handoff. `NONINTERACTIVE` belongs only to the background runner: the
/// handoff exists to let the same command ask for input.
public enum UpgradeCommand {
    public static let environment: [String: String] = [
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "HOMEBREW_NO_ANALYTICS": "1",
        "HOMEBREW_NO_COLOR": "1",
        "HOMEBREW_NO_ENV_HINTS": "1",
        "NONINTERACTIVE": "1",
        "NO_COLOR": "1",
        "npm_config_color": "false",
        "npm_config_yes": "true",
    ]

    public static let terminalEnvironment: [String: String] = environment.filter {
        $0.key != "NONINTERACTIVE"
    }

    public static func spec(for item: OutdatedItem) -> CommandSpec? {
        guard item.upgrade.kind == .command, let executable = item.upgrade.executable else {
            return nil
        }
        return CommandSpec(
            executable: executable,
            arguments: item.upgrade.arguments,
            environment: environment
        )
    }
}

/// Runs one upgrade plan and streams its transcript. Plans that need a GUI
/// (`openURL`) or human action (`manual`) are reported as skipped rather than
/// executed behind the user's back.
public struct UpgradeService: Sendable {
    private let runner: StreamingCommandRunning

    public init(runner: StreamingCommandRunning = StreamingProcessRunner()) {
        self.runner = runner
    }

    public func run(item: OutdatedItem, timeout: TimeInterval = 900) -> AsyncStream<UpgradeEvent> {
        guard let spec = UpgradeCommand.spec(for: item) else {
            return AsyncStream { continuation in
                continuation.yield(
                    .finished(
                        UpgradeResult(
                            itemID: item.id,
                            name: item.displayName,
                            command: item.upgrade.displayCommand,
                            success: false,
                            exitCode: -1,
                            message: item.upgrade.kind == .openURL
                                ? "This update opens a download page."
                                : (item.upgrade.hint ?? "This update needs a manual step.")
                        )
                    )
                )
                continuation.finish()
            }
        }

        let stream = runner.stream(spec, timeout: timeout)

        return AsyncStream { continuation in
            continuation.yield(.started(itemID: item.id, name: item.displayName, command: spec.display))
            let task = Task {
                for await event in stream {
                    switch event {
                    case .output(let text):
                        continuation.yield(.output(text))
                    case .finished(let result):
                        let success = result.succeeded
                        continuation.yield(
                            .finished(
                                UpgradeResult(
                                    itemID: item.id,
                                    name: item.displayName,
                                    command: spec.display,
                                    success: success,
                                    exitCode: result.exitCode,
                                    timedOut: result.timedOut,
                                    duration: result.duration,
                                    message: success ? nil : result.failureMessage,
                                    output: result.stdoutText + result.stderrText
                                )
                            )
                        )
                        continuation.finish()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
