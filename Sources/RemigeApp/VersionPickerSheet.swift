import RemigeCore
import SwiftUI

struct VersionPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: OutdatedItem
    @State private var search = ""

    private var versions: [String] {
        model.versionCatalog[item.id] ?? []
    }

    private var filtered: [String] {
        guard !search.isEmpty else { return versions }
        return versions.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private var selectedTarget: String? {
        model.config.versionTargets[item.id]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460, height: 540)
        .task(id: item.id) {
            await model.loadVersions(for: item)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ItemIcon(item: item, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 8) {
                    Text(L.t("versionPicker.installed", item.currentVersion))
                    Text("·")
                    Text(L.t("versionPicker.latest", item.latestVersion))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            Spacer()
            if item.majorVersionAvailable {
                MajorBadge(held: item.targetOrigin == .heldMajor)
            }
        }
        .padding(16)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(L.t("versionPicker.search"), text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if model.versionCatalogLoading.contains(item.id) {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L.t("versionPicker.loading"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.versionCatalogError, versions.isEmpty {
            Text(error)
                .font(.system(size: 11.5))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            Text(L.t("versionPicker.empty"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered, id: \.self) { version in
                        versionRow(version)
                    }
                }
                .padding(.vertical, 6)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
        }
    }

    private func versionRow(_ version: String) -> some View {
        let isTarget = version == selectedTarget
        let isLatest = version == item.latestVersion
        return Button {
            model.setVersionTarget(version, for: item)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Text(version)
                    .font(.system(size: 12, weight: isTarget ? .semibold : .regular, design: .monospaced))
                    .monospacedDigit()
                if isLatest {
                    Text(L.t("versionPicker.newest"))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(AppTheme.quietFill))
                }
                Spacer()
                if isTarget {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: AppTheme.Radius.control, horizontalInset: 8, verticalInset: 0)
    }

    private var footer: some View {
        HStack {
            Button(L.t("versionPicker.followPolicy")) {
                model.setVersionTarget(nil, for: item)
                dismiss()
            }
            .buttonStyle(.link)
            .disabled(selectedTarget == nil)
            Spacer()
            Button(L.t("action.cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }
}
