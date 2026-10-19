import Foundation
import RemigeCore

public enum RemigeCLI {
    @discardableResult
    public static func run(arguments: [String]) async -> Int32 {
        let parsed = ArgumentParser.parse(arguments)
        let palette = CLIFormat.Palette(
            enabled: isatty(STDOUT_FILENO) == 1
                && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
                && !parsed.flag("no-color")
        )

        if parsed.flag("version") || parsed.command == "version" {
            print("remige \(RemigeVersion.current)")
            return 0
        }
        if parsed.flag("help") || parsed.command == "help" {
            print(help(for: parsed.positionals.first ?? parsed.command))
            return 0
        }
        if !parsed.errors.isEmpty {
            for error in parsed.errors { FileHandle.standardError.write(Data(("error: " + error + "\n").utf8)) }
            print("Run `remige --help` for usage.")
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
            case "update", "self-update":
                return try await update(parsed, palette: palette)
            default:
                throw CLIError("Unknown command “\(parsed.command ?? "")”. Run `remige --help`.")
            }
        } catch {
            FileHandle.standardError.write(Data(("error: " + error.localizedDescription + "\n").utf8))
            return 1
        }
    }

    // MARK: List

    private static func list(_ parsed: ParsedArguments, palette: CLIFormat.Palette) async throws -> Int32 {
        let sources = try selectedSources(parsed)
        let scanner = RemigeCore.Scanner()
        let snapshot: ScanSnapshot
        if parsed.flag("cached") {
            guard let cached = await scanner.cachedSnapshot() else {
                throw CLIError("No cached scan yet. Run `remige list` once.")
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
            palette.bold("remige \(RemigeVersion.current)") + " · "
                + palette.dim(CLIFormat.relative(snapshot.generatedAt)))
        if filtered.items.isEmpty {
            print(palette.green("All up to date."))
        } else {
            print(CLIFormat.table(items: filtered.items, palette: palette))
        }
        print("")
        let batchable = filtered.items.filter(\.isBatchable).count
        let major = filtered.items.filter(\.majorVersionAvailable).count
        print(
            "  \(filtered.items.count) updates"
                + " · " + "\(batchable) in update-all"
                + (major > 0 ? " · \(major) major" : "")
                + " · " + "scanned in \(CLIFormat.duration(snapshot.duration))"
        )
        for report in filtered.reports where report.state == .failed {
            print(
                "  "
                    + palette.yellow(
                        "\(report.source.rawValue): \(report.message ?? "failed")\(report.stale ? " (cached)" : "")"))
        }
        if let appReport = filtered.reports.first(where: { $0.source == .app }) {
            let unsupported = appReport.details.filter { $0.state == .unsupported }
            if !unsupported.isEmpty {
                let names = unsupported.map(\.name)
                let visible = names.prefix(6).joined(separator: ", ")
                let suffix = names.count > 6 ? ", …" : ""
                print(
                    "  "
                        + palette.dim(
                            "\(unsupported.count) apps without update source: \(visible)\(suffix)"))
            }
        }
        for warning in snapshot.warnings ?? [] {
            print("  " + palette.yellow("config: \(warning)"))
        }
        print("")
        return 0
    }

    // MARK: Upgrade

    private static func upgrade(_ parsed: ParsedArguments, palette: CLIFormat.Palette) async throws -> Int32 {
        let scanner = RemigeCore.Scanner()
        let snapshot = await scanner.scan(options: ScanOptions(forceRefresh: parsed.flag("refresh")))
        let selectedItems: [OutdatedItem]
        if let target = parsed.value("to") {
            guard !parsed.flag("all") else {
                throw CLIError("--to applies to one package; it cannot be combined with --all.")
            }
            guard parsed.positionals.count == 1 else {
                throw CLIError("--to needs exactly one package.")
            }
            var item = try CLIQuery.resolve(parsed.positionals[0], in: snapshot.items)
            guard item.versionedInstall != nil else {
                throw CLIError(
                    "\(item.displayName) does not expose a versioned install command; its source only offers the latest release."
                )
            }
            guard item.selectTarget(target) else {
                throw CLIError(
                    "Target \(target) must be newer than \(item.currentVersion) and no newer than \(item.latestVersion)."
                )
            }
            selectedItems = [item]
        } else if parsed.flag("all") {
            selectedItems = snapshot.items.filter {
                !$0.pinned && (parsed.flag("include-major") || $0.isBatchEligible)
            }
            if !parsed.flag("include-major") {
                let excluded = snapshot.items.filter { !$0.pinned && !$0.isBatchEligible }
                if !excluded.isEmpty && !parsed.flag("json") {
                    let majors = excluded.filter(\.majorVersionAvailable).count
                    let suffix = majors == excluded.count ? "major update(s)" : "update(s)"
                    print(
                        palette.dim(
                            "  \(excluded.count) \(suffix) excluded by the update policy · pass --include-major to include them"
                        )
                    )
                }
            }
        } else {
            guard !parsed.positionals.isEmpty else {
                throw CLIError("Name at least one package, or pass --all.")
            }
            selectedItems = try parsed.positionals.map { try CLIQuery.resolve($0, in: snapshot.items) }
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
                        if final.requiresTerminal {
                            print(
                                palette.yellow(
                                    "  Needs a terminal for input. Run: \(final.command ?? "")"))
                        }
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
            throw CLIError("Usage: remige changelog <id|name> [--limit N] [--json]")
        }
        let scanner = RemigeCore.Scanner()
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
            throw CLIError("Usage: remige open <id|name>")
        }
        let scanner = RemigeCore.Scanner()
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
            throw CLIError("Remige.app is not installed. Build it with `make app` or install from a release.")
        }
        return result
    }

    private static func runSyncOpenApp() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Remige"]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let paths = [
                "/Applications/Remige.app",
                NSHomeDirectory() + "/Applications/Remige.app",
            ]
            if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                let fallback = Process()
                fallback.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                fallback.arguments = [path]
                try fallback.run()
                fallback.waitUntilExit()
                return fallback.terminationStatus
            }
            throw CLIError("Remige.app is not installed.")
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
            (.app, true, "Sparkle appcasts, Electron manifests and cataloged app releases"),
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
            version: RemigeVersion.current,
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
        print(palette.bold("remige") + " \(report.version)")
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

    private static func update(_ parsed: ParsedArguments, palette: CLIFormat.Palette) async throws -> Int32 {
        let service = UpdateService()
        let available: AvailableUpdate?
        do {
            available = try await service.check()
        } catch {
            throw CLIError("Could not check for updates: \(error.localizedDescription)")
        }

        guard let available else {
            if parsed.flag("json") {
                struct Payload: Codable {
                    var current: String
                    var upToDate: Bool
                }
                printJSON(Payload(current: RemigeVersion.current, upToDate: true))
            } else {
                print("Remige \(RemigeVersion.current) is up to date.")
            }
            return 0
        }

        if parsed.flag("check") {
            if parsed.flag("json") {
                struct Payload: Codable {
                    var current: String
                    var latest: String
                    var notes: String
                    var pageURL: URL?
                    var assets: [String: UpdateAsset]
                }
                printJSON(
                    Payload(
                        current: available.currentVersion,
                        latest: available.latestVersion,
                        notes: available.manifest.notes,
                        pageURL: available.manifest.pageURL,
                        assets: available.manifest.assets
                    )
                )
            } else {
                print("Remige \(available.latestVersion) is available (you have \(available.currentVersion)).")
                print("Download: \(available.manifest.pageURL?.absoluteString ?? RemigeLinks.releases.absoluteString)")
            }
            return 0
        }

        guard let asset = available.manifest.cli else {
            throw CLIError("Release \(available.latestVersion) has no CLI binary.")
        }
        if !parsed.flag("json") {
            print("Updating Remige \(available.currentVersion) → \(available.latestVersion)…")
        }
        let data = try await service.download(asset)
        guard let executable = Bundle.main.executableURL else {
            throw CLIError("Cannot locate the running remige binary.")
        }
        let real = executable.resolvingSymlinksInPath()
        if real.path.contains("/Cellar/") || real.path.contains("/homebrew/") {
            throw CLIError("This remige is managed by Homebrew. Use `brew upgrade remige`.")
        }
        try CLIUpdater.install(data: data, at: real)

        if parsed.flag("json") {
            struct Payload: Codable {
                var current: String
                var latest: String
                var installed: Bool
                var executable: String
            }
            printJSON(
                Payload(
                    current: available.currentVersion,
                    latest: available.latestVersion,
                    installed: true,
                    executable: real.path
                )
            )
        } else {
            print(palette.green("Updated to Remige \(available.latestVersion)."))
            print(palette.dim("The next invocation uses the new binary."))
            if available.manifest.appZip != nil {
                print(palette.dim("The desktop app has the same update; use “Check for Updates…” in Remige."))
            }
        }
        return 0
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
            throw CLIError("Usage: remige cache path|size|clear")
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
            print(String(decoding: try JSONEncoder.remige.encode(config), as: UTF8.self))
        case "edit":
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try store.ensureExists()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-e", store.url.path]
            try process.run()
        default:
            throw CLIError("Usage: remige config path|init|show|edit")
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
        let encoder = JSONEncoder.remige
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func help(for command: String?) -> String {
        switch command {
        case "upgrade":
            return """
                usage: remige upgrade <id|name…> | --all [--to <version>] [--include-major]
                                      [--dry-run] [--yes] [--json] [--source …]

                Runs each package's own upgrade command (brew, npm, pnpm, bun, mas, self-update).
                Download-only apps open their release page. Nothing runs silently: without
                --yes, remige asks once on a TTY and refuses in scripts.

                --all honors the configured major-update policy; --include-major overrides it.
                --to targets one npm/pnpm/Bun package at an exact version for this run.
                """
        case "changelog":
            return """
                usage: remige changelog <id|name> [--limit N] [--json]

                Release notes from GitHub's Atom feed or the app's Sparkle appcast.
                Cached for six hours.
                """
        case "doctor":
            return "usage: remige doctor [--json]\n\nShows detected managers, paths, config and cache state."
        case "sources":
            return "usage: remige sources [--json]\n\nLists every source, whether it is enabled, and how it was found."
        case "cache":
            return "usage: remige cache path|size|clear"
        case "update", "self-update":
            return """
                usage: remige update [--check] [--json]

                Checks the release feed and replaces the running remige CLI atomically.
                The desktop app updates itself from its "Check for Updates…" menu.
                Homebrew installs should use `brew upgrade remige`.
                """
        case "config":
            return "usage: remige config path|init|show|edit"
        default:
            return """
                remige \(RemigeVersion.current) — every update on your Mac, in one place.

                usage:
                  remige [list] [--json] [--cached] [--source <name>] [--refresh] [--no-color]
                  remige upgrade <id|name…> | --all [--to <version>] [--include-major]
                                 [--dry-run] [--yes] [--json]
                  remige changelog <id|name> [--limit N] [--json]
                  remige open <id|name>
                  remige sources [--json]
                  remige doctor [--json]
                  remige cache path|size|clear
                  remige config path|init|show|edit
                  remige update [--check] [--json]
                  remige app
                  remige version

                sources:
                  homebrew  formulae and casks via `brew outdated --json=v2 --greedy`
                  npm       global packages via `npm outdated -g --json`
                  pnpm      global packages via `pnpm list -g` + the npm registry
                  bun       global packages in ~/.bun/install/global
                  app       Sparkle appcasts, Electron manifests and cataloged releases
                  cli       curl/installer tools (uv, claude, rustup, rg, …)
                  mas       Mac App Store updates when `mas` is installed
                  custom    tools declared in ~/.config/remige/config.json

                Custom tool example:
                  {"customTools":[{"name":"mytool","versionArgs":["--version"],
                    "github":"owner/repo","upgradeArgs":["mytool","self-update"]}]}
                """
        }
    }
}
