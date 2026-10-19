import Foundation
import Testing

@testable import RemigeCore

struct UpgradeHandoffTests {
    private func item(
        id: String = "brew:cask:demo",
        name: String = "demo",
        executable: String = "/opt/homebrew/bin/brew",
        arguments: [String] = ["upgrade", "--cask", "demo"]
    ) -> OutdatedItem {
        OutdatedItem(
            id: id,
            name: name,
            source: .homebrew,
            kind: .cask,
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            upgrade: .command(executable, arguments)
        )
    }

    @Test func interactiveFailureOffersTerminal() {
        let result = UpgradeResult(
            itemID: "brew:cask:demo",
            name: "demo",
            command: "/opt/homebrew/bin/brew upgrade --cask demo",
            success: false,
            exitCode: 1,
            message: "sudo: a password is required",
            output: "sudo: a password is required\n"
        )
        #expect(result.requiresTerminal)
    }

    @Test(
        arguments: [
            "Password: ",
            "sudo: a password is required",
            "[sudo] password for nichenqin:",
            "This command requires a terminal.",
            "Not signed in",
            "Proceed? [y/N]",
        ]
    )
    func detectsInteractivePrompts(_ text: String) {
        #expect(InteractivePrompt.matches(text))
    }

    @Test func ordinaryFailureDoesNotOfferTerminal() {
        let result = UpgradeResult(
            itemID: "brew:cask:demo",
            name: "demo",
            command: "/opt/homebrew/bin/brew upgrade --cask demo",
            success: false,
            exitCode: 1,
            message: "Error: Could not resolve host: formulae.brew.sh",
            output: "Error: Could not resolve host: formulae.brew.sh\n"
        )
        #expect(!result.requiresTerminal)
    }

    @Test func successDoesNotOfferTerminal() {
        let result = UpgradeResult(
            itemID: "brew:cask:demo",
            name: "demo",
            command: "/opt/homebrew/bin/brew upgrade --cask demo",
            success: true,
            exitCode: 0,
            output: "Password: ignored\n"
        )
        #expect(!result.requiresTerminal)
    }

    @Test func terminalScriptKeepsPromptsAndQuotesArguments() throws {
        let script = UpgradeTerminalScript.make(
            items: [
                item(arguments: ["upgrade", "--cask", "two words"]),
                item(
                    id: "custom:quoted",
                    name: "quoted",
                    executable: "/usr/local/bin/custom tool",
                    arguments: ["update", "it's"]
                ),
            ]
        )
        let text = try #require(script)
        #expect(text.contains("run_update '/usr/local/bin/custom tool' update 'it'\\''s'"))
        #expect(text.contains("read -r _"))
        #expect(!text.contains("NONINTERACTIVE"))
    }

    @Test func terminalScriptRunsAndReturnsCommandStatus() throws {
        #expect(try runTerminalScript(executable: "/usr/bin/true") == 0)
        #expect(try runTerminalScript(executable: "/usr/bin/false") == 1)
    }

    private func runTerminalScript(executable: String) throws -> Int32 {
        let script = try #require(
            UpgradeTerminalScript.make(
                items: [item(executable: executable, arguments: [])]
            )
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("remige-test-\(UUID().uuidString).command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data("\n".utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func terminalScriptSkipsNonCommandPlans() {
        let openItem = OutdatedItem(
            id: "app:demo",
            name: "demo",
            source: .app,
            kind: .application,
            currentVersion: "1.0",
            latestVersion: "2.0",
            upgrade: .open(URL(string: "https://example.com/download")!)
        )
        #expect(UpgradeTerminalScript.make(items: [openItem]) == nil)
    }

    @Test func streamingRunnerStopsAtPasswordPrompt() async {
        let runner = StreamingProcessRunner()
        let started = Date()
        let stream = runner.stream(
            CommandSpec(
                executable: "/bin/sh",
                arguments: ["-c", "printf 'Password: '; exec sleep 10"]
            ),
            timeout: 30
        )
        var output = ""
        var result: CommandResult?
        for await event in stream {
            switch event {
            case .output(let text): output += text
            case .finished(let finished): result = finished
            }
        }
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(output.contains("Password:"))
        #expect(result?.succeeded == false)
    }
}
