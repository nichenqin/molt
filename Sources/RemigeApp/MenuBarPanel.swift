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
        guard let item = statusItem() else {
            panelWindow()?.close()
            return
        }

        // Never toggle blindly. The panel can already be closed (for example by
        // a pending click or by losing key), and a second toggle reopens it and
        // leaves the status item out of sync with what is on screen.
        if item.button?.state != .off {
            item.button?.performClick(nil)
        } else if let window = panelWindow(), window.isVisible {
            window.close()
        }
    }

    /// True while the panel is presented, including while its close is pending.
    static var isPresented: Bool {
        if let button = statusItem()?.button, button.state != .off {
            return true
        }
        return panelWindow()?.isVisible == true
    }

    private static func statusItem() -> NSStatusItem? {
        let items = NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }

        // Each display owns a status bar window. Only the real item drives the
        // panel; the others are `NSStatusItemReplicant` instances whose button
        // clicks do not change the presentation.
        if let item = items.first(where: isRealStatusItem) {
            return item
        }
        return items.first { $0.button != nil }
    }

    private static func isRealStatusItem(_ item: NSStatusItem) -> Bool {
        // macOS 26 renamed the real item; previously it was `NSStatusItem`.
        item.className == "NSSceneStatusItem" || item.className == "NSStatusItem"
    }

    private static func panelWindow() -> NSWindow? {
        // SwiftUI names the window-style panel's window `MenuBarExtraWindow`.
        NSApp.windows.first { $0.className.contains("MenuBarExtraWindow") }
    }
}
