import AppKit
import RemigeCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L.t("app.name"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(L.updates(model.items.count))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .hoverHighlight(cornerRadius: 6, horizontalInset: 2, verticalInset: 2)
                    .help(L.t("action.refresh"))
                }
            }
            .padding(12)

            Divider()

            if model.items.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text(L.t("list.empty.title"))
                        .font(.system(size: 12))
                }
                .padding(14)
            } else {
                VStack(spacing: 1) {
                    ForEach(model.items.prefix(6)) { item in
                        Button {
                            MenuBarPanel.dismiss()
                            model.selectedID = item.id
                            model.perform(item)
                            openWindow(id: "main")
                        } label: {
                            HStack(spacing: 8) {
                                ItemIcon(item: item, size: 22)
                                Text(item.displayName)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 6)
                                VersionTransition(item: item, compact: true)
                                    .layoutPriority(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverHighlight(cornerRadius: 6, horizontalInset: 4)
                        .disabled(model.upgradeRunning)
                        .help(rowHelp(item))
                    }
                }
                .padding(.vertical, 4)

                if model.items.count > 6 {
                    Text(L.t("menu.more", model.items.count - 6))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
            }

            Divider()

            VStack(spacing: 0) {
                Button {
                    MenuBarPanel.dismiss()
                    model.upgradeAll()
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                } label: {
                    Label(L.t("action.upgradeAll"), systemImage: "bolt.fill")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 6, horizontalInset: 6, verticalInset: 1)
                .disabled(model.automaticCount == 0)

                Button {
                    MenuBarPanel.dismiss()
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                } label: {
                    Label(L.t("menu.open"), systemImage: "macwindow")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 6, horizontalInset: 6, verticalInset: 1)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label(L.t("menu.quit"), systemImage: "power")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 6, horizontalInset: 6, verticalInset: 1)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 330)
        .onAppear {
            model.refreshIfStale()
        }
    }

    private func rowHelp(_ item: OutdatedItem) -> String {
        switch item.upgrade.kind {
        case .command: L.t("action.upgrade")
        case .openURL: L.t("action.download")
        case .manual: L.t("action.manual")
        }
    }
}
