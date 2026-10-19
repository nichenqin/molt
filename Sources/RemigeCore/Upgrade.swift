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
}

public enum UpgradeEvent: Sendable {
    case started(itemID: String, name: String, command: String)
    case output(String)
    case finished(UpgradeResult)
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
        guard item.upgrade.kind == .command, let executable = item.upgrade.executable else {
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

        let spec = CommandSpec(
            executable: executable,
            arguments: item.upgrade.arguments,
            environment: [
                "HOMEBREW_NO_AUTO_UPDATE": "1",
                "HOMEBREW_NO_ANALYTICS": "1",
                "HOMEBREW_NO_COLOR": "1",
                "NO_COLOR": "1",
                "npm_config_color": "false",
            ]
        )
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
