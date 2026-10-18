import Foundation
import MoltCore

public enum MoltCLI {
    @discardableResult
    public static func run(arguments: [String]) async -> Int32 {
        let parsed = ArgumentParser.parse(arguments)
        let palette = CLIFormat.Palette(
            enabled: isatty(STDOUT_FILENO) == 1
                && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
                && !parsed.flag("no-color")
        )

        if parsed.flag("version") || parsed.command == "version" {
            print("molt \(MoltVersion.current)")
            return 0
        }
        if parsed.flag("help") || parsed.command == "help" {
            print(help(for: parsed.positionals.first ?? parsed.command))
            return 0
        }
        if !parsed.errors.isEmpty {
            for error in parsed.errors { FileHandle.standardError.write(Data(("error: " + error + "\n").utf8)) }
            print("Run `molt --help` for usage.")
            return 2
        }

        do {
            switch parsed.command ?? "list" {
            case "list", "ls", "outdated", "scan":
                return try await list(parsed, palette: palette)
            case "upgrade", "up":
                return try await upgrade(parsed, palette: palette)
            case "changelog", "notes":
                return try await changelog(parsed, palette: palette)
            case "open":
                return try await open(parsed)
            case "sources":
                return try await sources(parsed, palette: palette)
            case "doctor":
                return try await doctor(parsed, palette: palette)
            case "cache":
                return try await cache(parsed, palette: palette)
            case "config":
                return try config(parsed, palette: palette)
            case "app", "gui":
                return try openApp()
            default:
                throw CLIError("Unknown command “\(parsed.command ?? "")”. Run `molt --help`.")
            }
        } catch {
            FileHandle.standardError.write(Data(("error: " + error.localizedDescription + "\n").utf8))
            return 1
        }
    }

    // MARK: List

    private static func list(_ parsed: ParsedArguments, palette: CLIFormat.Palette) async throws -> Int32 {
        let sources = try selectedSources(parsed)
        let scanner = MoltCore.Scanner()
        let snapshot: ScanSnapshot
        if parsed.flag("cached") {
            guard let cached = await scanner.cachedSnapshot() else {
                throw CLIError("No cached scan yet. Run `molt list` once.")
            }
            snapshot = cached
        } else {
            snapshot = await scanner.scan(
                options: ScanOptions(forceRefresh: parsed.flag("refresh"))
            )
        }

        var filtered = snapshot
        if !sources.isEmpty {
            filtered.items = snapshot.items.filter { sources.contains($0.source) }
        }

        if parsed.flag("json") {
            printJSON(filtered)
            return 0
        }

        print("")
        print(
            palette.bold("molt \(MoltVersion.current)") + "  " + palette.dim(CLIFormat.relative(snapshot.generatedAt)))
        if filtered.items.isEmpty {
            print(palette.green("All up to date."))
        } else {
            print(CLIFormat.table(items: filtered.items, palette: palette))
        }
        print("")
        let automatic = filtered.items.filter(\.upgrade.canRunAutomatically).count
        print(
            "  \(filtered.items.count) updates"
                + " · " + "\(automatic) one-click"
                + " · " + "scanned in \(CLIFormat.duration(snapshot.duration))"
        )
        for report in filtered.reports where report.state == .failed {
            print(
                "  "
                    + palette.yellow(
                        "\(report.source.rawValue): \(report.message ?? "failed")\(report.stale ? " (cached)" : "")"))
        }
        for warning in snapshot.warnings ?? [] {
            print("  " + palette.yellow("config: \(warning)"))
        }
        print("")
        return 0
    }

    // MARK: Upgrade

    private static func upgrade(_ parsed: ParsedArguments, palette: CLIFormat.Palette) async throws -> Int32 {
        let scanner = MoltCore.Scanner()
        let snapshot = await scanner.scan(options: ScanOptions(forceRefresh: parsed.flag("refresh")))
        let selectedItems: [OutdatedItem]
        if parsed.flag("all") {
            selectedItems = snapshot.items
        } else {
            guard !parsed.positionals.isEmpty else {
                throw CLIError("Name at least one package, or pass --all.")
            }
            selectedItems = try parsed.positionals.map { try CLIQuery.resolve($0, in: snapshot.items) }
        }
        guard !selectedItems.isEmpty else {
            print("Nothing to upgrade.")
            return 0
        }

        let automatic = selectedItems.filter(\.upgrade.canRunAutomatically)
        let openable = selectedItems.filter { $0.upgrade.kind == .openURL }
        let manual = selectedItems.filter { $0.upgrade.kind == .manual }
        if automatic.isEmpty && openable.isEmpty {
            print("No automatic upgrades. \(manual.count) item(s) need a manual update.")
            return 0
        }

        if parsed.flag("dry-run") {
            for item in selectedItems {
                switch item.upgrade.kind {
                case .command:
                    print("\(item.id): \(item.upgrade.displayCommand ?? "")")
                case .openURL:
                    print("\(item.id): open \(item.upgrade.url?.absoluteString ?? "")")
                case .manual:
                    print("\(item.id): manual — \(item.upgrade.hint ?? "")")
                }
            }
            return 0
        }

        if !parsed.flag("yes") {
            guard isatty(STDIN_FILENO) == 1 else {
                throw CLIError("Refusing to upgrade without --yes in a non-interactive shell.")
            }
            print(
                "Upgrade \(automatic.count) package(s)"
                    + (openable.isEmpty ? "" : " and open \(openable.count) download page(s)") + "? [y/N] ",
                terminator: "")
            fflush(stdout)
            guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                print("Cancelled.")
                return 0
            }
        }

        var results: [UpgradeResult] = []
        let service = UpgradeService()
        let quiet = parsed.flag("json")

        for item in automatic {
            if !quiet {
                print(palette.dim("→ \(item.displayName): \(item.upgrade.displayCommand ?? "")"))
            }
            var final: UpgradeResult?
            for await event in service.run(item: item) {
                switch event {
                case .started:
                    break
                case .output(let text):
                    if !quiet { FileHandle.standardOutput.write(Data(text.utf8)) }
                case .finished(let result):
                    final = result
                }
            }
            if let final {
                results.append(final)
                if !quiet {
                    if final.success {
                        print(palette.green("✓ \(item.displayName)"))
                    } else {
                        print(palette.red("✗ \(item.displayName): \(final.message ?? "failed")"))
                    }
                }
            }
        }

        for item in openable {
            guard let url = item.upgrade.url else { continue }
            let result = await ProcessRunner().run(
                CommandSpec(executable: "/usr/bin/open", arguments: [url.absoluteString]),
                timeout: 20
            )
            let upgradeResult = UpgradeResult(
                itemID: item.id,
                name: item.displayName,
                command: "open \(url.absoluteString)",
                success: result.succeeded,
                exitCode: result.exitCode,
                duration: result.duration,
                message: result.failureMessage
            )
            results.append(upgradeResult)
            if !quiet {
                if upgradeResult.success {
                    print(palette.cyan("↗ \(item.displayName): opened download page"))
                } else {
                    print(palette.red("✗ \(item.displayName): \(upgradeResult.message ?? "could not open")"))
                }
            }
        }

        for item in manual where !quiet {
            print(palette.dim("· \(item.displayName): manual update required"))
        }

        if quiet {
            struct Payload: Codable {
                var results: [UpgradeResult]
            }
            printJSON(Payload(results: results))
        } else {
            let failed = results.filter { !$0.success }.count
            print("")
            print("\(results.count - failed) upgraded · \(failed) failed")
        }
        return results.contains { !$0.success } ? 1 : 0
    }

    // MARK: Changelog

    private static func changelog(_ parsed: ParsedArguments, palette: CLIFormat.Palette) async throws -> Int32 {
        guard let query = parsed.positionals.first else {
            throw CLIError("Usage: molt changelog <id|name> [--limit N] [--json]")
        }
        let scanner = MoltCore.Scanner()
        let snapshot = await scanner.scan(options: ScanOptions(forceRefresh: parsed.flag("refresh")))
        let item = try CLIQuery.resolve(query, in: snapshot.items)
        let limit = max(1, min(20, Int(parsed.value("limit") ?? "6") ?? 6))
        FileHandle.standardError.write(Data("Fetching release notes for \(item.displayName)…\n".utf8))
        let service = ChangelogService(http: URLSessionHTTPClient(), cache: DiskCache())
        let result = await service.changelog(for: item, limit: limit)

        if parsed.flag("json") {
            struct Payload: Codable {
                var item: OutdatedItem
                var webURL: URL?
                var releases: [ChangelogRelease]
            }
            printJSON(Payload(item: item, webURL: result.webURL, releases: result.releases))
            return 0
        }

        print("")
        print(palette.bold(item.displayName) + "  " + palette.dim(item.versionLine))
        if let web = result.webURL {
            print(palette.dim(web.absoluteString))
        }
        if result.releases.isEmpty {
            print("\nNo release notes available.")
            return 0
        }
        for release in result.releases {
            print("")
            let date = release.publishedAt.map { " · " + CLIFormat.date($0) } ?? ""
            print(palette.bold(release.title) + palette.dim(date))
            if let url = release.url { print(palette.dim(url.absoluteString)) }
            let body = HTMLText.plain(from: release.bodyHTML)
            if !body.isEmpty {
                print(String(body.prefix(8_000)))
            }
        }
        print("")
        return 0
    }

    // MARK: Open

    private static func open(_ parsed: ParsedArguments) async throws -> Int32 {
        guard let query = parsed.positionals.first else {
            throw CLIError("Usage: molt open <id|name>")
        }
        let scanner = MoltCore.Scanner()
        let snapshot = await scanner.scan(options: ScanOptions())
        let item = try CLIQuery.resolve(query, in: snapshot.items)
        guard let url = item.homepage ?? item.repo?.webURL ?? item.changelogURL else {
            throw CLIError("No homepage recorded for \(item.displayName).")
        }
        let result = await ProcessRunner().run(
            CommandSpec(executable: "/usr/bin/open", arguments: [url.absoluteString]),
            timeout: 20
        )
        guard result.succeeded else {
            throw CLIError(result.failureMessage ?? "Could not open \(url.absoluteString)")
        }
        return 0
    }

    private static func openApp() throws -> Int32 {
        guard let result = try? runSyncOpenApp() else {
            throw CLIError("Molt.app is not installed. Build it with `make app` or install from a release.")
        }
        return result
    }

    private static func runSyncOpenApp() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Molt"]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let paths = [
                "/Applications/Molt.app",
                NSHomeDirectory() + "/Applications/Molt.app",
            ]
            if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                let fallback = Process()
                fallback.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                fallback.arguments = [path]
                try fallback.run()
                fallback.waitUntilExit()
                return fallback.terminationStatus
            }
            throw CLIError("Molt.app is not installed.")
        }
        return 0
    }

    // MARK: Sources / doctor / cache / config

    private static func sources(_ parsed: ParsedArguments, palette: CLIFormat.Palette) async throws -> Int32 {
        let config = try? ConfigStore().load()
        let environment = EnvironmentInfo()
        let rows: [(SourceKind, Bool, String)] = [
            (.homebrew, environment.brew != nil, environment.brew?.executable ?? "not installed"),
            (.npm, environment.npm != nil, environment.npm ?? "not installed"),
            (.pnpm, environment.pnpm != nil, environment.pnpm ?? "not installed"),
            (.bun, environment.bun != nil, environment.bun ?? "not installed"),
            (.app, true, "Sparkle appcasts"),
            (.cli, true, "\(ToolCatalog.tools.count) catalog tools"),
            (.mas, environment.mas != nil, environment.mas ?? "not installed"),
            (.custom, !(config?.customTools.isEmpty ?? true), "\(config?.customTools.count ?? 0) configured"),
        ]
        if parsed.flag("json") {
            struct Row: Codable {
                var source: String
                var enabled: Bool
                var available: Bool
                var detail: String
            }
            let payload = rows.map {
                Row(
                    source: $0.0.rawValue,
                    enabled: config?.isEnabled($0.0) ?? true,
                    available: $0.1,
                    detail: $0.2
                )
            }
            printJSON(payload)
            return 0
        }
        for (source, available, detail) in rows {
            let enabled = config?.isEnabled(source) ?? true
            let state = enabled ? (available ? palette.green("on") : palette.dim("—")) : palette.yellow("off")
            print(
                "\(state)  \(source.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(palette.dim(detail))"
            )
        }
        return 0
    }

    private static func doctor(_ parsed: ParsedArguments, palette: CLIFormat.Palette) async throws -> Int32 {
        struct Doctor: Codable {
            var version: String
            var host: HostInfo
            var configPath: String
            var cachePath: String
            var cacheBytes: Int64
            var brew: String?
            var npm: String?
            var pnpm: String?
            var bun: String?
            var mas: String?
            var configError: String?
            var snapshotAge: String?
            var snapshotItems: Int?
        }
        let configStore = ConfigStore()
        let cache = DiskCache()
        var configError: String?
        do { _ = try configStore.load() } catch { configError = error.localizedDescription }
        let snapshot = await SnapshotStore(cache: cache).load()
        let environment = EnvironmentInfo()
        let report = Doctor(
            version: MoltVersion.current,
            host: .current(),
            configPath: configStore.url.path,
            cachePath: DiskCache.defaultDirectory.path,
            cacheBytes: await cache.sizeOnDisk(),
            brew: environment.brew?.executable,
            npm: environment.npm,
            pnpm: environment.pnpm,
            bun: environment.bun,
            mas: environment.mas,
            configError: configError,
            snapshotAge: snapshot.map { CLIFormat.relative($0.generatedAt) },
            snapshotItems: snapshot?.items.count
        )
        if parsed.flag("json") {
            printJSON(report)
            return configError == nil ? 0 : 1
        }
        print(palette.bold("molt") + " \(report.version)")
        print("host      \(report.host.osVersion) \(report.host.architecture)")
        print("config    \(report.configPath)" + (configError == nil ? "" : palette.red("  invalid")))
        print(
            "cache     \(report.cachePath)  \(ByteCountFormatter.string(fromByteCount: report.cacheBytes, countStyle: .file))"
        )
        print("brew      \(environment.brew?.executable ?? "not installed")")
        print("npm       \(environment.npm ?? "not installed")")
        print("pnpm      \(environment.pnpm ?? "not installed")")
        print("bun       \(environment.bun ?? "not installed")")
        print("mas       \(environment.mas ?? "not installed")")
        if let snapshot {
            print("snapshot  \(snapshot.items.count) items · \(CLIFormat.relative(snapshot.generatedAt))")
        } else {
            print("snapshot  none")
        }
        if let configError { print(palette.red(configError)) }
        return configError == nil ? 0 : 1
    }

    private static func cache(_ parsed: ParsedArguments, palette: CLIFormat.Palette) async throws -> Int32 {
        let cache = DiskCache()
        switch parsed.positionals.first ?? "size" {
        case "path":
            print(DiskCache.defaultDirectory.path)
        case "size":
            print(ByteCountFormatter.string(fromByteCount: await cache.sizeOnDisk(), countStyle: .file))
        case "clear":
            await cache.clear()
            print("Cache cleared.")
        default:
            throw CLIError("Usage: molt cache path|size|clear")
        }
        return 0
    }

    private static func config(_ parsed: ParsedArguments, palette: CLIFormat.Palette) throws -> Int32 {
        let store = ConfigStore()
        switch parsed.positionals.first ?? "show" {
        case "path":
            print(store.url.path)
        case "init":
            let created = try store.ensureExists()
            print(created ? "Created \(store.url.path)" : "Already exists at \(store.url.path)")
        case "show":
            let config = try store.load()
            print(String(decoding: try JSONEncoder.molt.encode(config), as: UTF8.self))
        case "edit":
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try store.ensureExists()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-e", store.url.path]
            try process.run()
        default:
            throw CLIError("Usage: molt config path|init|show|edit")
        }
        return 0
    }

    // MARK: Helpers

    private static func selectedSources(_ parsed: ParsedArguments) throws -> Set<SourceKind> {
        let raw = parsed.values("source").flatMap { $0.split(separator: ",").map(String.init) }
        guard !raw.isEmpty else { return [] }
        var result = Set<SourceKind>()
        for value in raw {
            guard let source = SourceKind(rawValue: value.lowercased()) else {
                throw CLIError(
                    "Unknown source “\(value)”. Use: \(SourceKind.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            result.insert(source)
        }
        return result
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder.molt
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func help(for command: String?) -> String {
        switch command {
        case "upgrade":
            return """
                usage: molt upgrade <id|name…> | --all [--dry-run] [--yes] [--json] [--source …]

                Runs each package's own upgrade command (brew, npm, pnpm, bun, mas, self-update).
                Download-only apps open their release page. Nothing runs silently: without
                --yes, molt asks once on a TTY and refuses in scripts.
                """
        case "changelog":
            return """
                usage: molt changelog <id|name> [--limit N] [--json]

                Release notes from GitHub's Atom feed or the app's Sparkle appcast.
                Cached for six hours.
                """
        case "doctor":
            return "usage: molt doctor [--json]\n\nShows detected managers, paths, config and cache state."
        case "sources":
            return "usage: molt sources [--json]\n\nLists every source, whether it is enabled, and how it was found."
        case "cache":
            return "usage: molt cache path|size|clear"
        case "config":
            return "usage: molt config path|init|show|edit"
        default:
            return """
                molt \(MoltVersion.current) — every update on your Mac, in one place.

                usage:
                  molt [list] [--json] [--cached] [--source <name>] [--refresh] [--no-color]
                  molt upgrade <id|name…> | --all [--dry-run] [--yes] [--json]
                  molt changelog <id|name> [--limit N] [--json]
                  molt open <id|name>
                  molt sources [--json]
                  molt doctor [--json]
                  molt cache path|size|clear
                  molt config path|init|show|edit
                  molt app
                  molt version

                sources:
                  homebrew  formulae and casks via `brew outdated --json=v2 --greedy`
                  npm       global packages via `npm outdated -g --json`
                  pnpm      global packages via `pnpm list -g` + the npm registry
                  bun       global packages in ~/.bun/install/global
                  app       Sparkle appcasts for .app bundles in Applications
                  cli       curl/installer tools (uv, claude, rustup, rg, …)
                  mas       Mac App Store updates when `mas` is installed
                  custom    tools declared in ~/.config/molt/config.json

                Custom tool example:
                  {"customTools":[{"name":"mytool","versionArgs":["--version"],
                    "github":"owner/repo","upgradeArgs":["mytool","self-update"]}]}
                """
        }
    }
}
