import AppKit
import Foundation
import MoltCore
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var snapshot: ScanSnapshot?
    var items: [OutdatedItem] = []
    var reports: [SourceReport] = []
    var warnings: [String] = []
    var selectedID: String?
    var selectedSource: SourceKind?
    var searchText = ""
    var isRefreshing = false
    var hasLoadedCache = false
    var config: MoltConfig = .empty
    var configError: String?

    var showUpgradeSheet = false
    var upgradeRunning = false
    var upgradeLog = ""
    var toast: String?

    var availableUpdate: AvailableUpdate?
    var showUpdateSheet = false
    var isCheckingForUpdates = false
    var isInstallingUpdate = false
    var updateError: String?
    var autoCheckUpdates = UserDefaults.standard.object(forKey: "autoCheckMoltUpdates") as? Bool ?? true
    var updateStatus = ""
    var lastUpdateCheck: Date?
    var upgradeTitle = ""
    var upgradeResults: [UpgradeResult] = []

    var changelogs: [String: ChangelogResult] = [:]
    var changelogLoading: Set<String> = []
    private let scanner = MoltCore.Scanner()
    private let configStore = ConfigStore()
    private let cache = DiskCache()
    private let upgradeService = UpgradeService()
    private var scanTask: Task<Void, Never>?
    private var upgradeTask: Task<Void, Never>?

    init() {
        loadConfig()
        scanTask = Task { [weak self] in
            guard let self else { return }
            if let cached = await scanner.cachedSnapshot() {
                apply(cached)
                hasLoadedCache = true
            }
            await refresh(force: false)
        }
        Task { [weak self] in
            await self?.checkForUpdates(silent: true)
        }
    }

    // MARK: Filtering

    var filteredItems: [OutdatedItem] {
        var result = items
        if let selectedSource {
            result = result.filter { $0.source == selectedSource }
        }
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            result = result.filter {
                $0.displayName.lowercased().contains(needle)
                    || $0.name.lowercased().contains(needle)
                    || $0.summary?.lowercased().contains(needle) == true
            }
        }
        return result
    }

    var selectedItem: OutdatedItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    var automaticCount: Int {
        items.filter(\.upgrade.canRunAutomatically).count
    }

    var presentSources: [SourceKind] {
        SourceKind.allCases.filter { source in
            items.contains { $0.source == source }
        }
    }

    func count(for source: SourceKind?) -> Int {
        guard let source else { return items.count }
        return items.filter { $0.source == source }.count
    }

    var failedReports: [SourceReport] {
        reports.filter { $0.state == .failed }
    }

    var filteredBySource: [SourceKind: [OutdatedItem]] {
        Dictionary(grouping: filteredItems, by: \.source)
    }

    // MARK: Scanning

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let result = await scanner.scan(options: ScanOptions(forceRefresh: force))
        apply(result)
        isRefreshing = false
    }

    private func apply(_ snapshot: ScanSnapshot) {
        self.snapshot = snapshot
        items = snapshot.items
        reports = snapshot.reports
        warnings = snapshot.warnings ?? []
        if let selectedID, !snapshot.items.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        if selectedID == nil, let first = snapshot.items.first {
            selectedID = first.id
        }
    }

    func refreshIfStale() {
        guard !isRefreshing else { return }
        let age = snapshot.map { Date().timeIntervalSince($0.generatedAt) } ?? .infinity
        guard age > 15 * 60 else { return }
        Task { await refresh(force: false) }
    }

    // MARK: Changelog

    func loadChangelog(for item: OutdatedItem) async {
        if changelogs[item.id] != nil || changelogLoading.contains(item.id) { return }
        changelogLoading.insert(item.id)
        defer { changelogLoading.remove(item.id) }
        let service = ChangelogService(http: URLSessionHTTPClient(), cache: cache)
        let result = await service.changelog(for: item, limit: 3)
        changelogs[item.id] = result
    }

    // MARK: Actions

    func perform(_ item: OutdatedItem) {
        switch item.upgrade.kind {
        case .command:
            startUpgrade(items: [item], title: item.displayName)
        case .openURL:
            if let url = item.upgrade.url {
                NSWorkspace.shared.open(url)
            }
        case .manual:
            showToast(item.upgrade.hint ?? L.t("action.manual"))
        }
    }

    func upgradeAll() {
        let targets = items.filter(\.upgrade.canRunAutomatically)
        guard !targets.isEmpty else {
            showToast(L.t("upgrade.none"))
            return
        }
        startUpgrade(items: targets, title: L.t("upgrade.all.title"))
    }

    private func startUpgrade(items targets: [OutdatedItem], title: String) {
        guard !upgradeRunning else { return }
        upgradeTitle = title
        upgradeLog = ""
        upgradeResults = []
        showUpgradeSheet = true
        upgradeRunning = true
        upgradeTask = Task { [weak self] in
            guard let self else { return }
            for item in targets {
                if Task.isCancelled { break }
                if !upgradeLog.isEmpty { appendLog("\n") }
                for await event in upgradeService.run(item: item) {
                    if Task.isCancelled { break }
                    switch event {
                    case .started(_, _, let command):
                        appendLog("→ \(command)\n")
                    case .output(let text):
                        appendLog(text)
                    case .finished(let result):
                        upgradeResults.append(result)
                        appendLog(
                            result.success
                                ? "\n✓ \(result.name)\n" : "\n✗ \(result.name): \(result.message ?? "failed")\n")
                    }
                }
            }
            upgradeRunning = false
            if upgradeResults.contains(where: \.success) {
                await refresh(force: false)
            }
        }
    }

    func cancelUpgrade() {
        upgradeTask?.cancel()
        upgradeRunning = false
        appendLog("\n" + L.t("upgrade.cancelled") + "\n")
    }

    func closeUpgradeSheet() {
        guard !upgradeRunning else { return }
        showUpgradeSheet = false
    }

    private func appendLog(_ text: String) {
        upgradeLog += text
        if upgradeLog.count > 240_000 {
            upgradeLog = String(upgradeLog.suffix(200_000))
        }
    }

    func openHomepage(_ item: OutdatedItem) {
        if let url = item.homepage ?? item.repo?.webURL {
            NSWorkspace.shared.open(url)
        }
    }

    func openChangelogPage(_ item: OutdatedItem) {
        let result = changelogs[item.id]
        if let url = result?.webURL ?? item.changelogURL ?? item.repo?.releasesURL {
            NSWorkspace.shared.open(url)
        }
    }

    func reveal(_ item: OutdatedItem) {
        guard let path = item.installedPath,
            FileManager.default.fileExists(atPath: path)
        else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyCommand(_ item: OutdatedItem) {
        guard let command = item.upgrade.displayCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        showToast(L.t("action.copied"))
    }

    func copyID(_ item: OutdatedItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.id, forType: .string)
        showToast(L.t("action.copied"))
    }

    func showToast(_ message: String) {
        toast = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.toast == message { self?.toast = nil }
        }
    }

    // MARK: Config

    func loadConfig() {
        do {
            config = try configStore.load()
            configError = nil
        } catch {
            config = .empty
            configError = error.localizedDescription
        }
    }

    func setSource(_ source: SourceKind, enabled: Bool) {
        if enabled {
            config.disabledSources.removeAll { $0 == source.rawValue }
        } else if !config.disabledSources.contains(source.rawValue) {
            config.disabledSources.append(source.rawValue)
        }
        do {
            try configStore.save(config)
            configError = nil
            Task { await refresh(force: false) }
        } catch {
            configError = error.localizedDescription
        }
    }

    func openConfig() {
        try? FileManager.default.createDirectory(at: configStore.directory, withIntermediateDirectories: true)
        _ = try? configStore.ensureExists()
        NSWorkspace.shared.open(configStore.url)
    }

    func clearCache() async {
        await cache.clear()
        showToast(L.t("settings.cache.cleared"))
    }

    // MARK: Login item

    var launchesAtLogin: Bool {
        LoginItem.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    // MARK: Self-update

    func setAutoCheckUpdates(_ enabled: Bool) {
        autoCheckUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: "autoCheckMoltUpdates")
        if enabled {
            Task { await checkForUpdates(silent: true) }
        }
    }

    func checkForUpdates(silent: Bool) async {
        if isCheckingForUpdates { return }
        if silent && !autoCheckUpdates { return }
        let defaults = UserDefaults.standard
        if silent, let last = defaults.object(forKey: "lastMoltUpdateCheck") as? Date,
            Date().timeIntervalSince(last) < 24 * 3600
        {
            return
        }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        do {
            let update = try await UpdateService().check()
            defaults.set(Date(), forKey: "lastMoltUpdateCheck")
            lastUpdateCheck = Date()
            availableUpdate = update
            if update != nil {
                if !silent { showUpdateSheet = true }
            } else if !silent {
                showToast(L.t("update.current", MoltVersion.current))
            }
        } catch {
            if !silent {
                updateError = error.localizedDescription
                showUpdateSheet = true
            }
        }
    }

    func installUpdate() {
        guard let update = availableUpdate,
            let asset = update.manifest.appZip,
            !isInstallingUpdate
        else { return }
        isInstallingUpdate = true
        updateError = nil
        updateStatus = L.t("update.downloading")
        let target = Bundle.main.bundleURL
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await UpdateService().download(asset)
                updateStatus = L.t("update.installing")
                _ = try await Task.detached(priority: .userInitiated) {
                    try AppUpdater.install(
                        zipData: data,
                        expectedVersion: update.latestVersion,
                        targetApp: target
                    )
                }.value
                NSApp.terminate(nil)
            } catch {
                isInstallingUpdate = false
                updateError = error.localizedDescription
            }
        }
    }

    func openUpdatePage() {
        if let url = availableUpdate?.manifest.pageURL {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(MoltLinks.releases)
        }
    }

    func dismissUpdate() {
        showUpdateSheet = false
    }
}

// MARK: - Login item

private enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
