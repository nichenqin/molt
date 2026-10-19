import AppKit

/// Closes the window-style `MenuBarExtra` panel from a control inside it.
///
/// SwiftUI exposes no API for this (FB11984872). Calling `close()` or
/// `orderOut(nil)` on the panel hides it but leaves MenuBarExtra's presentation
/// state convinced it is still open, so the next status-item click does nothing.
/// Clicking the status item itself closes the panel and resets that state, which
/// is what this reproduces.
@MainActor
enum MenuBarPanel {
    static func dismiss() {
        // Actions exist only inside the presented panel, so this click always
        // toggles the panel closed.
        statusItem()?.button?.performClick(nil)
    }

    private static func statusItem() -> NSStatusItem? {
        // Each display owns a status bar window; only the primary one holds a
        // real status item, the others are replicas without a button.
        NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }
            .first { $0.button != nil }
    }
}
