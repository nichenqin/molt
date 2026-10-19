import AppKit
import RemigeCore
import SwiftUI

enum AppTheme {
    enum Spacing {
        static let compact: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let section: CGFloat = 20
    }

    enum Radius {
        static let control: CGFloat = 7
        static let selection: CGFloat = 8
        static let card: CGFloat = 12
    }

    static let hairline = Color.primary.opacity(0.07)
    static let quietFill = Color.primary.opacity(0.045)
    static let hoverFill = Color.primary.opacity(0.05)
    static let selectionFill = Color.accentColor.opacity(0.11)
    static let detailBackground = Color(nsColor: .textBackgroundColor)
    static let cardBackground = quietFill
}

extension SourceKind {
    var tint: Color {
        switch self {
        case .homebrew: Color(red: 0.95, green: 0.62, blue: 0.18)
        case .npm: Color(red: 0.80, green: 0.16, blue: 0.16)
        case .pnpm: Color(red: 0.95, green: 0.60, blue: 0.15)
        case .bun: Color(red: 0.85, green: 0.55, blue: 0.72)
        case .app: Color(red: 0.24, green: 0.52, blue: 0.95)
        case .cli: Color(red: 0.05, green: 0.62, blue: 0.58)
        case .mas: Color(red: 0.36, green: 0.40, blue: 0.90)
        case .custom: Color(red: 0.45, green: 0.47, blue: 0.52)
        }
    }

    var symbol: String {
        switch self {
        case .homebrew: "cup.and.saucer.fill"
        case .npm: "shippingbox.fill"
        case .pnpm: "shippingbox.fill"
        case .bun: "takeoutbag.and.cup.and.straw.fill"
        case .app: "app.fill"
        case .cli: "terminal.fill"
        case .mas: "storefront.fill"
        case .custom: "wrench.and.screwdriver.fill"
        }
    }
}

enum AppIconStore {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let source = NSWorkspace.shared.icon(forFile: path)
        // App icons can carry several large representations. Downsample once;
        // the UI never renders them above 64pt.
        let side: CGFloat = 128
        let resized = NSImage(size: NSSize(width: side, height: side))
        resized.lockFocus()
        source.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        resized.unlockFocus()
        cache.setObject(resized, forKey: key)
        return resized
    }
}

struct ItemIcon: View {
    let item: OutdatedItem
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let path = item.installedPath, path.hasSuffix(".app") {
                Image(nsImage: AppIconStore.image(for: path))
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(item.source.tint.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                                .strokeBorder(item.source.tint.opacity(0.12))
                        }
                    Text(monogram)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(item.source.tint)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var monogram: String {
        let base = item.name.split(separator: "/").last.map(String.init) ?? item.name
        return String(base.prefix(1)).uppercased()
    }
}

struct SourceBadge: View {
    let source: SourceKind
    var compact = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Circle()
                .fill(source.tint)
                .frame(width: 5, height: 5)
            Text(compact ? source.rawValue : L.source(source))
                .font(.system(size: compact ? 10.5 : 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, compact ? 0 : 7)
        .padding(.vertical, compact ? 0 : 2)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AppTheme.quietFill)
            }
        }
    }
}

struct VersionTransition: View {
    let item: OutdatedItem

    var body: some View {
        HStack(spacing: 5) {
            Text(item.currentVersion)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(item.latestVersion)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
        .monospacedDigit()
    }
}

struct ActionBadge: View {
    let plan: UpgradePlan

    var body: some View {
        switch plan.kind {
        case .command:
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
                .help(L.t("detail.oneClick"))
        case .openURL:
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .help(L.t("detail.download"))
        case .manual:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .help(L.t("detail.manual"))
        }
    }
}

struct PinnedBadge: View {
    var body: some View {
        Text(L.t("detail.pinned"))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.12)))
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let tint: Color
    let action: () -> Void

    @State private var hovering = false

    /// The pointer target is the whole slot, not just the drawn card: the side
    /// gutters finish the gap between neighbours, so a click that lands between
    /// two chips still belongs to one of them.
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(selected ? .primary : .tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .fill(
                        selected
                            ? Color(nsColor: .textBackgroundColor)
                            : (hovering ? AppTheme.hoverFill : .clear)
                    )
                    .shadow(color: selected ? .black.opacity(0.08) : .clear, radius: 1, y: 1)
            }
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule()
                        .fill(tint)
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, AppTheme.Spacing.compact / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Hover feedback

/// Rounded pointer highlight for compact, plain-styled controls.
///
/// The menu bar popup uses the same subtle fill as the main window list, and a
/// disabled control never highlights.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 6
    var horizontalInset: CGFloat = 6
    var verticalInset: CGFloat = 0

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(isEnabled && hovering ? 0.07 : 0))
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, verticalInset)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

extension View {
    func hoverHighlight(
        cornerRadius: CGFloat = 6,
        horizontalInset: CGFloat = 6,
        verticalInset: CGFloat = 0
    ) -> some View {
        modifier(
            HoverHighlight(
                cornerRadius: cornerRadius,
                horizontalInset: horizontalInset,
                verticalInset: verticalInset
            )
        )
    }
}

// MARK: - Release notes

/// Release notes are rendered as text on purpose: the AppKit HTML importer is
/// convenient but retains hundreds of megabytes when several releases are on
/// screen. Opening the release page gives the fully formatted version.
struct HTMLBody: View {
    let html: String
    @State private var text = ""

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: html) {
                guard !html.isEmpty else { return }
                text = String(HTMLText.plain(from: html).prefix(12_000))
            }
    }
}
