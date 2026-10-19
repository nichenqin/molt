import Foundation

public struct ScanOptions: Sendable {
    public var forceRefresh: Bool
    public var usePreviousOnFailure: Bool

    public init(forceRefresh: Bool = false, usePreviousOnFailure: Bool = true) {
        self.forceRefresh = forceRefresh
        self.usePreviousOnFailure = usePreviousOnFailure
    }
}

public struct Scanner: Sendable {
    private struct DetectorRun: Sendable {
        var source: SourceKind
        var output: DetectorOutput?
        var error: String?
        var duration: Double
    }

    public let configStore: ConfigStore
    private let runner: CommandRunning
    private let http: HTTPGetting
    private let cache: DiskCache
    private let environment: EnvironmentInfo
    private let store: SnapshotStore

    public init(
        configStore: ConfigStore = ConfigStore(),
        runner: CommandRunning = ProcessRunner(),
        http: HTTPGetting = URLSessionHTTPClient(),
        cache: DiskCache = DiskCache(),
        environment: EnvironmentInfo = EnvironmentInfo(),
        store: SnapshotStore? = nil
    ) {
        self.configStore = configStore
        self.runner = runner
        self.http = http
        self.cache = cache
        self.environment = environment
        self.store = store ?? SnapshotStore(cache: cache)
    }

    public func cachedSnapshot() async -> ScanSnapshot? {
        await store.load()
    }

    public func scan(options: ScanOptions = ScanOptions()) async -> ScanSnapshot {
        let started = Date()
        var warnings: [String] = []
        let config: MoltConfig
        do {
            config = try configStore.load()
        } catch {
            config = .empty
            warnings.append(error.localizedDescription)
        }

        let context = ScanContext(
            runner: runner,
            http: http,
            cache: cache,
            config: config,
            environment: environment,
            forceRefresh: options.forceRefresh
        )
        let detectors = Self.detectors
        let previous = options.usePreviousOnFailure ? await store.load() : nil

        var runs: [SourceKind: DetectorRun] = [:]
        await withTaskGroup(of: DetectorRun.self) { group in
            for detector in detectors {
                guard config.isEnabled(detector.source) else { continue }
                group.addTask {
                    let sourceStarted = Date()
                    do {
                        let output = try await withTimeout(
                            Self.timeout(for: detector.source),
                            label: detector.source.rawValue
                        ) {
                            try await detector.scan(context)
                        }
                        return DetectorRun(
                            source: detector.source,
                            output: output,
                            duration: Date().timeIntervalSince(sourceStarted)
                        )
                    } catch {
                        return DetectorRun(
                            source: detector.source,
                            error: error.localizedDescription,
                            duration: Date().timeIntervalSince(sourceStarted)
                        )
                    }
                }
            }
            for await run in group {
                runs[run.source] = run
            }
        }

        var items: [OutdatedItem] = []
        var reports: [SourceReport] = []
        for source in SourceKind.allCases {
            guard detectors.contains(where: { $0.source == source }) else { continue }
            if !config.isEnabled(source) {
                reports.append(SourceReport(source: source, state: .disabled, message: "Disabled in config"))
                continue
            }
            guard let run = runs[source] else {
                reports.append(SourceReport(source: source, state: .failed, message: "No result"))
                continue
            }
            if let error = run.error {
                let carried = previous?.items.filter { $0.source == source } ?? []
                items.append(contentsOf: carried)
                reports.append(
                    SourceReport(
                        source: source,
                        state: .failed,
                        message: error,
                        duration: run.duration,
                        count: carried.count,
                        stale: !carried.isEmpty
                    )
                )
            } else if let output = run.output {
                if output.skipped {
                    reports.append(
                        SourceReport(
                            source: source,
                            state: .skipped,
                            message: output.message,
                            duration: run.duration,
                            details: output.details
                        )
                    )
                } else {
                    items.append(contentsOf: output.items)
                    reports.append(
                        SourceReport(
                            source: source,
                            state: .ok,
                            message: output.message,
                            duration: run.duration,
                            count: output.items.count,
                            details: output.details
                        )
                    )
                }
            } else {
                reports.append(SourceReport(source: source, state: .failed, message: "No result"))
            }
        }

        let merged = Self.merge(items)
        let counts = Dictionary(grouping: merged, by: \.source).mapValues(\.count)
        reports = reports.map { report in
            var updated = report
            updated.count = counts[report.source] ?? 0
            return updated
        }

        let snapshot = ScanSnapshot(
            generatedAt: Date(),
            duration: Date().timeIntervalSince(started),
            items: merged,
            reports: reports.sorted { $0.source.sortOrder < $1.source.sortOrder },
            warnings: warnings.isEmpty ? nil : warnings
        )
        if !Task.isCancelled {
            await store.save(snapshot)
        }
        return snapshot
    }

    public static var detectors: [OutdatedSourceDetector] {
        [
            HomebrewDetector(),
            NpmGlobalDetector(),
            PnpmGlobalDetector(),
            BunGlobalDetector(),
            AppUpdateDetector(),
            CLIToolDetector(),
            MacAppStoreDetector(),
            CustomToolDetector(),
        ]
    }

    private static func timeout(for source: SourceKind) -> TimeInterval {
        switch source {
        case .homebrew: 60
        case .npm, .pnpm, .bun: 35
        case .app, .cli, .mas, .custom: 40
        }
    }

    /// Drops duplicates so one app/package never shows twice.
    public static func merge(_ items: [OutdatedItem]) -> [OutdatedItem] {
        var result = items
        var brewByPath: [String: Int] = [:]
        for (index, item) in result.enumerated() where item.source == .homebrew {
            if let path = item.installedPath {
                brewByPath[path.lowercased()] = index
            }
        }

        var removed = Set<Int>()
        for (index, item) in result.enumerated() where item.source == .app {
            guard let path = item.installedPath?.lowercased(),
                let brewIndex = brewByPath[path]
            else { continue }
            // The cask row already has the one-click brew upgrade. Borrow the
            // Sparkle app's path/bundle id for its icon, then drop the app row.
            result[brewIndex].installedPath = item.installedPath
            result[brewIndex].bundleIdentifier = item.bundleIdentifier
            removed.insert(index)
        }

        var seenIDs = Set<String>()
        var seenPaths = Set<String>()
        let ordered = result.enumerated()
            .filter { !removed.contains($0.offset) }
            .sorted { lhs, rhs in
                if lhs.element.source.sortOrder != rhs.element.source.sortOrder {
                    return lhs.element.source.sortOrder < rhs.element.source.sortOrder
                }
                return lhs.element.displayName.localizedStandardCompare(rhs.element.displayName) == .orderedAscending
            }

        var final: [OutdatedItem] = []
        for (_, item) in ordered {
            if !seenIDs.insert(item.id).inserted { continue }
            // Custom entries win over the built-in catalog for the same binary.
            if item.kind == .binary, let path = item.installedPath,
                seenPaths.contains(path)
            {
                continue
            }
            if item.kind == .custom, let path = item.installedPath {
                seenPaths.insert(path)
                final.removeAll { $0.kind == .binary && $0.installedPath == path }
            }
            if item.kind == .binary, let path = item.installedPath {
                seenPaths.insert(path)
            }
            final.append(item)
        }
        return final
    }
}
