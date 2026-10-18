import AppKit
import MoltCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var cacheSize: String = "—"
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section(L.t("settings.general")) {
                Toggle(L.t("settings.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        model.setLaunchAtLogin(value)
                    }
            }

            Section(L.t("settings.sources")) {
                ForEach(SourceKind.allCases, id: \.self) { source in
                    Toggle(
                        isOn: Binding(
                            get: { model.config.isEnabled(source) },
                            set: { model.setSource(source, enabled: $0) }
                        )
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: source.symbol)
                                .foregroundStyle(source.tint)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(L.source(source))
                                Text(sourceDescription(source))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section(L.t("settings.customTools")) {
                Text(L.t("settings.customTools.help"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(ConfigStore.defaultURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L.t("settings.editConfig")) { model.openConfig() }
                }
                if let error = model.configError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                }
            }

            Section(L.t("settings.cache")) {
                HStack {
                    Text(cacheSize)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L.t("settings.clearCache")) {
                        Task {
                            await model.clearCache()
                            await refreshCacheSize()
                        }
                    }
                }
            }

            Section(L.t("settings.about")) {
                LabeledContent(L.t("settings.version"), value: MoltVersion.current)
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = model.launchesAtLogin
            Task { await refreshCacheSize() }
        }
    }

    private func refreshCacheSize() async {
        let cache = DiskCache()
        let bytes = await cache.sizeOnDisk()
        cacheSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func sourceDescription(_ source: SourceKind) -> String {
        L.t("source.desc.\(source.rawValue)")
    }
}
