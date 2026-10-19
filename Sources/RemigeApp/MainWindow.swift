import AppKit
import SwiftUI

/// Reopens and foregrounds the single main window from menu bar actions.
///
/// The menu bar panel dismisses itself with a simulated status-item click
/// (`MenuBarPanel.dismiss()`). That click is handled after the button action
/// returns, and closing the panel hands activation back to the previously
/// active app. An activation requested in the same run loop turn is therefore
/// lost, and the reopened window stays behind other apps. Re-assert activation
/// and front ordering for long enough to outlive the panel close, then stop as
/// soon as the app is active with the main window key.
@MainActor
enum MainWindow {
    private static let windowID = "main"
    private static let retryInterval = 0.05
    /// The panel close animation plus the activation hand-back takes well under
    /// this; claims stop early only once it has elapsed.
    private static let settleDuration = 0.5
    private static let maxAttempts = 24

    private static var generation = 0

    static func show(using openWindow: OpenWindowAction) {
        openWindow(id: windowID)
        generation &+= 1
        claim(
            token: generation,
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
