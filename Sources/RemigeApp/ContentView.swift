import AppKit
import RemigeCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HeaderView()
            UpdateBanner()
            FilterBar()
            Divider().opacity(0.45)
            HSplitView {
                UpdateList()
                    .frame(minWidth: 390, idealWidth: 455, maxWidth: 600)
                DetailPane()
                    .frame(minWidth: 430)
            }
            Divider().opacity(0.45)
            FooterView()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 900, minHeight: 580)
        .sheet(isPresented: $model.showUpgradeSheet) {
            UpgradeSheet()
                .environment(model)
        }
        .sheet(isPresented: $model.showHistorySheet) {
            UpdateHistorySheet()
                .environment(model)
        }
        .sheet(isPresented: $model.showUpdateSheet) {
            UpdateSheet()
                .environment(model)
        }
        .confirmationDialog(
            model.pendingUpgrade?.title ?? "",
            isPresented: Binding(
                get: { model.pendingUpgrade != nil },
                set: { if !$0 { model.cancelPendingUpgrade() } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingUpgrade
        ) { pending in
            Button(L.t("confirm.upgrade.action")) { model.confirmPendingUpgrade() }
            if let url = pending.changelogURL {
                Button(L.t("action.releaseNotes")) { NSWorkspace.shared.open(url) }
            }
            Button(L.t("action.cancel"), role: .cancel) { model.cancelPendingUpgrade() }
        } message: { pending in
            Text(pending.message)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(message: toast)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }
}

// MARK: - Header

private struct HeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(L.t("app.name"))
                    .font(.system(size: 18, weight: .semibold))
                statusLine
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppTheme.Spacing.medium)

            searchField
                .frame(width: 200)

            Button {
                Task { await model.refresh(force: true) }
            } label: {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .opacity(model.isRefreshing ? 0 : 1)
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help(L.t("action.refresh"))
            .disabled(model.isRefreshing)

            Button {
                model.showHistorySheet = true
            } label: {
                Label(L.t("action.history"), systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L.t("history.title"))
            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help(L.t("action.settings"))

            Button {
                model.upgradeAll()
            } label: {
                Label(L.t("action.upgradeAll"), systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.accentColor)
            .disabled(model.automaticCount == 0 || model.upgradeRunning)
            .help(L.t("upgrade.all.title"))
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.failedReports.isEmpty ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            if model.isRefreshing && model.items.isEmpty {
                Text(L.t("header.scanning"))
            } else if let snapshot = model.snapshot {
                Text(L.updates(model.items.count))
                Text("·")
                Text(L.oneClick(model.automaticCount))
                Text("·")
                Text(L.checked(L.relative(snapshot.generatedAt)))
            } else {
                Text(L.t("header.scanning"))
            }
        }
    }

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(L.t("search.placeholder"), text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .strokeBorder(AppTheme.hairline)
        )
    }
}

// MARK: - Filters

private struct FilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                FilterChip(
                    title: L.t("filter.all"),
                    count: model.items.count,
                    selected: model.selectedSource == nil,
                    tint: Color.accentColor
                ) {
                    model.selectedSource = nil
                }
                ForEach(model.presentSources, id: \.self) { source in
                    FilterChip(
                        title: L.source(source),
                        count: model.count(for: source),
                        selected: model.selectedSource == source,
                        tint: source.tint
                    ) {
                        model.selectedSource = source
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.large - AppTheme.Spacing.compact / 2)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

// MARK: - List

private struct UpdateList: View {
    @Environment(AppModel.self) private var model

    private var sources: [SourceKind] {
        SourceKind.allCases.filter { model.filteredBySource[$0] != nil }
    }

    var body: some View {
        Group {
            if model.filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sources, id: \.self) { source in
                            Section {
                                ForEach(model.filteredBySource[source] ?? []) { item in
                                    UpdateRow(item: item, selected: model.selectedID == item.id)
                                        .onTapGesture {
                                            model.selectedID = item.id
                                        }
                                }
                            } header: {
                                sectionHeader(source)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sectionHeader(_ source: SourceKind) -> some View {
        HStack(spacing: 6) {
            Image(systemName: source.symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(source.tint)
            Text(L.source(source).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.65)
                .foregroundStyle(.secondary)
            Text("\(model.count(for: source))")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .frame(height: 28)
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text(L.t("list.empty.title"))
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        } description: {
            Text(L.t("list.empty.body"))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct UpdateRow: View {
    @Environment(AppModel.self) private var model
    let item: OutdatedItem
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            ItemIcon(item: item, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if item.pinned { PinnedBadge() }
                }
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    SourceBadge(source: item.source, compact: true)
                }
            }

            Spacer(minLength: AppTheme.Spacing.small)

            VersionTransition(item: item)
                .frame(maxWidth: 195, alignment: .trailing)

            ActionBadge(plan: item.upgrade)

            Button {
                model.perform(item)
            } label: {
                Image(systemName: item.upgrade.kind == .command ? "arrow.up.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.upgrade.kind == .command ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(actionHelp)
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .frame(minHeight: 50)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.selection, style: .continuous)
                .fill(selected ? AppTheme.selectionFill : (hovering ? AppTheme.hoverFill : .clear))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if item.upgrade.canRunAutomatically {
                Button(L.t("action.upgrade")) { model.perform(item) }
            }
            Button(L.t("action.releaseNotes")) { model.openChangelogPage(item) }
            if item.installedPath != nil {
                Button(L.t("action.reveal")) { model.reveal(item) }
            }
            if item.upgrade.displayCommand != nil {
                Button(L.t("action.copyCommand")) { model.copyCommand(item) }
            }
            Divider()
            Button(L.t("action.copyID")) { model.copyID(item) }
        }
    }

    private var actionHelp: String {
        switch item.upgrade.kind {
        case .command: L.t("action.upgrade")
        case .openURL: L.t("action.download")
        case .manual: L.t("action.manual")
        }
    }
}

// MARK: - Footer

private struct FooterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            if model.isRefreshing {
                ProgressView().controlSize(.small)
                Text(L.t("header.scanning"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else if let snapshot = model.snapshot {
                Text(L.t("footer.lastChecked", L.relative(snapshot.generatedAt)))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(String(format: "%.1fs", snapshot.duration))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !model.unsupportedAppDetails.isEmpty {
                Label(
                    L.t("footer.appsUnsupported", model.unsupportedAppDetails.count),
                    systemImage: "questionmark.circle"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .help(model.appCoverageHelp)
            }
            if !model.failedReports.isEmpty {
                Label(
                    L.t("footer.failed", model.failedReports.count),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .help(model.failedReports.compactMap(\.message).joined(separator: "\n"))
            }
            if !model.warnings.isEmpty {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help(model.warnings.joined(separator: "\n"))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .frame(height: 30)
        .background(.bar)
    }
}

// MARK: - Detail

private struct DetailPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let item = model.selectedItem {
                DetailContent(item: item)
                    .id(item.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L.t("list.select"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppTheme.detailBackground)
    }
}

private struct DetailContent: View {
    @Environment(AppModel.self) private var model
    let item: OutdatedItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                header
                versionCard
                actions
                Divider().opacity(0.55)
                changelog
            }
            .padding(AppTheme.Spacing.section)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .task(id: item.id) {
            await model.loadChangelog(for: item)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.medium) {
            ItemIcon(item: item, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .textSelection(.enabled)
                HStack(spacing: 7) {
                    SourceBadge(source: item.source)
                    if item.pinned { PinnedBadge() }
                    Text(item.name)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
    }

    private var versionCard: some View {
        HStack(spacing: AppTheme.Spacing.large) {
            versionColumn(title: L.t("detail.installed"), version: item.currentVersion, muted: true)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
            versionColumn(title: L.t("detail.latest"), version: item.latestVersion, muted: false)
            Spacer(minLength: AppTheme.Spacing.small)
            actionBadge
        }
        .padding(AppTheme.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .strokeBorder(AppTheme.hairline)
        )
    }

    private func versionColumn(title: String, version: String, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.55)
                .foregroundStyle(.tertiary)
            Text(version)
                .font(.system(size: muted ? 13.5 : 15, weight: muted ? .regular : .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var actionBadge: some View {
        switch item.upgrade.kind {
        case .command:
            Label(L.t("detail.oneClick"), systemImage: "bolt.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.green)
        case .openURL:
            Label(L.t("detail.download"), systemImage: "arrow.up.forward")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        case .manual:
            Label(L.t("detail.manual"), systemImage: "hand.raised.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            primaryAction

            Button {
                model.openChangelogPage(item)
            } label: {
                Label(L.t("action.releaseNotes"), systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if item.installedPath != nil {
                Button {
                    model.reveal(item)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L.t("action.reveal"))
            }

            Menu {
                if item.upgrade.displayCommand != nil {
                    Button(L.t("action.copyCommand")) { model.copyCommand(item) }
                }
                Button(L.t("action.copyID")) { model.copyID(item) }
                if item.homepage != nil || item.repo != nil {
                    Button(L.t("action.homepage")) { model.openHomepage(item) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        let button = Button {
            model.perform(item)
        } label: {
            Label(primaryTitle, systemImage: primarySymbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 116)
        }
        .controlSize(.small)
        .help(item.upgrade.displayCommand ?? item.upgrade.hint ?? "")

        if item.upgrade.kind == .command {
            button
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
        } else {
            button
                .buttonStyle(.bordered)
        }
    }

    private var primaryTitle: String {
        switch item.upgrade.kind {
        case .command: L.t("action.upgrade")
        case .openURL: L.t("action.download")
        case .manual: L.t("action.manual")
        }
    }

    private var primarySymbol: String {
        item.upgrade.kind == .command ? "arrow.up.circle.fill" : "arrow.up.forward"
    }

    @ViewBuilder
    private var changelog: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                Text(L.t("detail.whatsNew"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.changelogLoading.contains(item.id) {
                    ProgressView().controlSize(.small)
                }
                if let url = model.changelogs[item.id]?.webURL ?? item.changelogURL ?? item.repo?.releasesURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(L.t("detail.openNotes"), systemImage: "arrow.up.forward.square")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.link)
                }
            }

            if model.changelogLoading.contains(item.id) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.t("detail.loading"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let result = model.changelogs[item.id], !result.releases.isEmpty {
                ForEach(result.releases) { release in
                    ReleaseCard(release: release)
                }
            } else {
                Text(L.t("detail.noNotes"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
    }
}

private struct ReleaseCard: View {
    let release: ChangelogRelease

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(release.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                if let date = release.publishedAt {
                    Text(date, format: .dateTime.year().month().day())
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            if !release.bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HTMLBody(html: release.bodyHTML)
            }
            if let url = release.url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text(url.host ?? url.absoluteString)
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.link)
            }
        }
        .padding(AppTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .strokeBorder(AppTheme.hairline)
        )
    }
}

// MARK: - Upgrade sheet

private struct UpdateBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let update = model.availableUpdate {
            HStack(spacing: 9) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 12, weight: .semibold))
                Text(L.t("update.available", update.latestVersion))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(L.t("update.have", update.currentVersion))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button(L.t("update.install")) {
                    model.showUpdateSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color.accentColor)
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

private struct UpdateSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("update.sheet.title"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    if let update = model.availableUpdate {
                        Text(L.t("update.available", update.latestVersion))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let update = model.availableUpdate {
                        Text(L.t("update.have", update.currentVersion))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        if !update.manifest.notes.isEmpty {
                            Text(notes(update.manifest.notes))
                                .font(.system(size: 12.5))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        }
                    } else if let error = model.updateError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    } else {
                        Text(L.t("update.current", RemigeVersion.current))
                            .font(.system(size: 12.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .frame(minHeight: 220)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35))

            Divider()

            HStack(spacing: 9) {
                if model.isInstallingUpdate {
                    ProgressView().controlSize(.small)
                    Text(model.updateStatus)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Text(L.t("update.doNotQuit"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else if let error = model.updateError, model.availableUpdate == nil {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button(L.t("update.releasePage")) { model.openUpdatePage() }
                    .buttonStyle(.link)
                Button(L.t("update.later")) { model.dismissUpdate() }
                if model.availableUpdate != nil {
                    Button(L.t("update.installNow")) { model.installUpdate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isInstallingUpdate)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 620, height: 480)
        .interactiveDismissDisabled(model.isInstallingUpdate)
    }

    private func notes(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: #"(?m)^#{1,6}\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s*[-*]\s+"#, with: "• ", options: .regularExpression)
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct UpdateHistorySheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(L.t("history.title"), systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Button(L.t("action.close")) { model.showHistorySheet = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            if model.updateHistory.isEmpty {
                ContentUnavailableView {
                    Label(L.t("history.empty.title"), systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(L.t("history.empty.body"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.updateHistory) { entry in
                            UpdateHistoryRow(entry: entry)
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
        }
        .frame(width: 620, height: 500)
    }
}

private struct UpdateHistoryRow: View {
    let entry: UpdateHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(L.source(entry.source))
                    Text("·")
                    Text(entry.versionLine)
                        .font(.system(.caption, design: .monospaced))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                if let message = entry.message, !message.isEmpty, entry.status != .success {
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                Text(L.relative(entry.date))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var statusSymbol: String {
        switch entry.status {
        case .success: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .success: .green
        case .failed: .orange
        case .cancelled: .secondary
        }
    }

    private var statusTitle: String {
        switch entry.status {
        case .success: L.t("history.status.success")
        case .failed: L.t("history.status.failed")
        case .cancelled: L.t("history.status.cancelled")
        }
    }
}

private struct UpgradeSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if model.upgradeRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(
                        systemName: model.upgradeResults.contains(where: { !$0.success })
                            ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(model.upgradeResults.contains(where: { !$0.success }) ? .orange : .green)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.upgradeTitle)
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.upgradeRunning ? L.t("upgrade.running") : summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                Text(model.upgradeLog.isEmpty ? L.t("upgrade.running") : model.upgradeLog)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))

            Divider()

            HStack {
                Spacer()
                if model.upgradeRunning {
                    Button(L.t("upgrade.cancel")) { model.cancelUpgrade() }
                } else {
                    Button(L.t("upgrade.close")) { model.closeUpgradeSheet() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(width: 660, height: 430)
        .interactiveDismissDisabled(model.upgradeRunning)
    }

    private var summary: String {
        let success = model.upgradeResults.filter(\.success).count
        let failed = model.upgradeResults.filter { !$0.success }.count
        return L.t("upgrade.complete", success, failed)
    }
}
