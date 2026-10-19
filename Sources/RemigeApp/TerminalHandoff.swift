import Foundation
import RemigeCore

enum TerminalHandoffError: LocalizedError {
    case noCommand
    case writeFailed(String)
    case terminalFailed(String)

    var errorDescription: String? {
        switch self {
        case .noCommand:
            "No failing command needs a terminal."
        case .writeFailed(let message):
            "Could not write the Terminal script: \(message)"
        case .terminalFailed(let message):
            "Could not open Terminal: \(message)"
        }
    }
}

/// Hands failed upgrade commands to Terminal so sudo, App Store sign-in and
/// other prompts can be answered by the user. Remige never reads the reply.
enum TerminalHandoff {
    static func open(items: [OutdatedItem]) throws {
        guard let script = UpgradeTerminalScript.make(items: items) else {
            throw TerminalHandoffError.noCommand
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("remige-upgrade-\(UUID().uuidString).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        } catch {
            throw TerminalHandoffError.writeFailed(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", url.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw TerminalHandoffError.terminalFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalHandoffError.terminalFailed(
                message.isEmpty ? "open exited \(process.terminationStatus)" : message
            )
        }
    }
}
