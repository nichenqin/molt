import Foundation

public enum CommandStreamEvent: Sendable {
    case output(String)
    case finished(CommandResult)
}

public protocol StreamingCommandRunning: Sendable {
    func stream(_ command: CommandSpec, timeout: TimeInterval) -> AsyncStream<CommandStreamEvent>
}

/// Watches a small tail of both output streams for prompts that need a human.
/// Only the first match is reported so two readability handlers cannot both
/// terminate the process.
final class InteractivePromptMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var tail = ""
    private var detected = false

    func consume(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        defer { lock.unlock() }
        guard !detected else { return false }
        tail.append(text)
        if tail.count > 4_096 {
            tail = String(tail.suffix(4_096))
        }
        guard InteractivePrompt.matches(tail) else { return false }
        detected = true
        return true
    }
}

/// Streams a child process while retaining the complete transcript for results.
public final class StreamingProcessRunner: StreamingCommandRunning, @unchecked Sendable {
    private let baseEnvironment: [String: String]

    public init(environment: [String: String]? = nil) {
        self.baseEnvironment = environment ?? EnvironmentSnapshot.current()
    }

    public func stream(_ command: CommandSpec, timeout: TimeInterval) -> AsyncStream<CommandStreamEvent> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            var environment = baseEnvironment
            for (key, value) in command.environment { environment[key] = value }
            process.environment = environment
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let lock = NSLock()
            let promptMonitor = InteractivePromptMonitor()
            var stdout = Data()
            var stderr = Data()
            var finished = false

            let stopForPrompt: @Sendable () -> Void = {
                guard process.isRunning else { return }
                process.terminate()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
            let started = Date()

            func append(_ data: Data, to target: inout Data) {
                target.append(data)
            }

            func finish(_ result: CommandResult) {
                lock.lock()
                if finished {
                    lock.unlock()
                    return
                }
                finished = true
                lock.unlock()
                continuation.yield(.finished(result))
                continuation.finish()
            }

            let readOut: @Sendable (FileHandle) -> Void = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                let prompt = promptMonitor.consume(data)
                lock.lock()
                append(data, to: &stdout)
                lock.unlock()
                continuation.yield(.output(String(decoding: data, as: UTF8.self)))
                if prompt { stopForPrompt() }
            }
            let readErr: @Sendable (FileHandle) -> Void = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                let prompt = promptMonitor.consume(data)
                lock.lock()
                append(data, to: &stderr)
                lock.unlock()
                continuation.yield(.output(String(decoding: data, as: UTF8.self)))
                if prompt { stopForPrompt() }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = readOut
            stderrPipe.fileHandleForReading.readabilityHandler = readErr

            process.terminationHandler = { finishedProcess in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let restOut = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let restErr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                lock.lock()
                append(restOut, to: &stdout)
                append(restErr, to: &stderr)
                let out = stdout
                let err = stderr
                lock.unlock()
                if !restOut.isEmpty {
                    continuation.yield(.output(String(decoding: restOut, as: UTF8.self)))
                }
                if !restErr.isEmpty {
                    continuation.yield(.output(String(decoding: restErr, as: UTF8.self)))
                }
                finish(
                    CommandResult(
                        stdout: out,
                        stderr: err,
                        exitCode: finishedProcess.terminationStatus,
                        timedOut: false,
                        duration: Date().timeIntervalSince(started)
                    )
                )
            }

            let timeoutTask = Task { [weak process] in
                guard let process else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(1, timeout) * 1_000_000_000))
                if Task.isCancelled { return }
                if process.isRunning {
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                timeoutTask.cancel()
                finish(
                    CommandResult(
                        exitCode: -1,
                        duration: Date().timeIntervalSince(started),
                        launchError: "Could not launch \(command.executable): \(error.localizedDescription)"
                    )
                )
                return
            }

            continuation.onTermination = { @Sendable _ in
                timeoutTask.cancel()
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}
