import AppKit
import SwiftUI

/// Monospaced, selectable log that follows new output until the reader scrolls
/// away from the bottom.
///
/// Backed by AppKit instead of `ScrollView` because SwiftUI hides its overlay
/// scroll indicators as soon as scrolling stops, and cannot reliably keep a
/// growing text pinned to the bottom without fighting the reader.
struct UpgradeLogView: NSViewRepresentable {
    var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        // Keep the real scroller on screen instead of flashing it while scrolling.
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        context.coordinator.render(text.isEmpty ? placeholder : text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.render(text.isEmpty ? placeholder : text)
    }

    @MainActor
    final class Coordinator {
        private static let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private var rendered = ""
        private var isFollowing = true
        private var observer: NSObjectProtocol?

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scrollPositionChanged()
                }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func render(_ newText: String) {
            guard let textView, let storage = textView.textStorage else { return }
            guard newText != rendered else { return }

            // Append in place when output grows: repainting the whole log on
            // every chunk is expensive and can disturb a reader's position.
            if newText.hasPrefix(rendered) {
                let suffix = newText.dropFirst(rendered.count)
                if !suffix.isEmpty {
                    storage.append(
                        NSAttributedString(string: String(suffix), attributes: Self.attributes))
                }
            } else {
                storage.setAttributedString(
                    NSAttributedString(string: newText, attributes: Self.attributes))
                // An emptied log belongs to a fresh run, so start following again.
                if newText.isEmpty {
                    isFollowing = true
                }
            }
            rendered = newText

            guard isFollowing else { return }
            // Scroll after the next layout pass: the document frame has not
            // grown to the appended text yet, and scrolling now would stop
            // one chunk short of the bottom.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isFollowing else { return }
                self.scrollToBottom()
            }
        }

        private func scrollPositionChanged() {
            guard let scrollView else { return }
            let clipView = scrollView.contentView
            let overflow = max(0, contentHeight() - clipView.bounds.height)
            // Within a couple of points of the bottom counts as following.
            isFollowing = clipView.bounds.origin.y >= overflow - 2
        }

        private func scrollToBottom() {
            guard let scrollView else { return }
            let clipView = scrollView.contentView
            let overflow = max(0, contentHeight() - clipView.bounds.height)
            clipView.scroll(to: NSPoint(x: 0, y: overflow))
            scrollView.reflectScrolledClipView(clipView)
            isFollowing = true
        }

        /// Height the laid-out text actually occupies, including insets.
        private func contentHeight() -> CGFloat {
            guard let textView, let container = textView.textContainer else { return 0 }
            textView.layoutManager?.ensureLayout(for: container)
            let used = textView.layoutManager?.usedRect(for: container).height ?? textView.frame.height
            return used + textView.textContainerInset.height * 2
        }
    }
}
