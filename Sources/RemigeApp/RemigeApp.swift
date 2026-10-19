import AppKit
import RemigeCore
import SwiftUI

@main
struct RemigeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window(L.t("app.name"), id: "main") {
            ContentView()
                .environment(model)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1020, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L.t("action.refresh")) {
                    Task { await model.refresh(force: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isRefreshing)

                Button(L.t("action.upgradeAll")) {
                    model.upgradeAll()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.automaticCount == 0 || model.upgradeRunning)
            }
            CommandMenu(L.t("app.name")) {
                Button(L.t("menu.update")) {
                    Task { await model.checkForUpdates(silent: false) }
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
                Divider()
                Button(L.t("action.settings")) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
                Divider()
                Button(L.t("menu.quit")) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                if !model.items.isEmpty {
                    Text("\(model.items.count)")
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
        .defaultSize(width: 540, height: 520)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
