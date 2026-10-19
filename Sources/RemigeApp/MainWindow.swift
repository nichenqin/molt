import AppKit
import SwiftUI

/// Reopens and foregrounds the single main window from menu bar actions.
///
/// The menu bar panel dismisses itself with a simulated status-item click
/// (`MenuBarPanel.dismiss()`). That click is handled after the button action
/// returns, and closing the panel hands activation back to the previously
/// active app. An activation requested in the same run loop turn is therefore
/// lost, and the reopened window stays behind other apps.
///
/// Wait for the panel to actually leave the screen before activating, then
/// re-assert activation and front ordering until the app is active with the
/// main window key.
@MainActor
enum MainWindow {
    private static let windowID = "main"
    private static let retryInterval = 0.05
    private static let settleDuration = 0.35
    private static let maxAttempts = 24
    /// Longest wait for the panel close animation before activating regardless.
    private static let dismissTimeout = 1.0
    private static let dismissPollInterval = 0.02

    private static var generation = 0

    static func show(using openWindow: OpenWindowAction) {
        openWindow(id: windowID)
        generation &+= 1
        waitForPanelClose(
            token: generation,
            deadline: Date().addingTimeInterval(dismissTimeout)
        )
    }

    private static func waitForPanelClose(token: Int, deadline: Date) {
        guard token == generation else { return }
        if MenuBarPanel.isPresented, Date() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + dismissPollInterval) {
                waitForPanelClose(token: token, deadline: deadline)
            }
            return
        }
        claim(
            token: token,
            remaining: maxAttempts,
            settleUntil: Date().addingTimeInterval(settleDuration)
        )
    }

    private static func claim(token: Int, remaining: Int, settleUntil: Date) {
        guard token == generation else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow() {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
        let now = Date()
        if now >= settleUntil, NSApp.isActive, let window = mainWindow(),
            window.isKeyWindow, !window.isMiniaturized
        {
            return
        }
        guard remaining > 0, now < settleUntil.addingTimeInterval(1) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryInterval) {
            claim(token: token, remaining: remaining - 1, settleUntil: settleUntil)
        }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == windowID }
    }
}
