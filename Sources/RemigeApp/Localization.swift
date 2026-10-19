import Foundation
import RemigeCore

enum L {
    /// Prefer the app bundle's standard Contents/Resources localization. The
    /// `.module` fallback keeps `swift run RemigeApp` working during development.
    private static let stringsBundle: Bundle = {
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }
        return .module
    }()

    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: stringsBundle, comment: "")
    }

    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: stringsBundle, comment: "")
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static func source(_ source: SourceKind) -> String {
        t("source.\(source.rawValue)")
    }

    static func updates(_ count: Int) -> String {
        count == 1 ? t("header.update.one") : t("header.updates", count)
    }

    static func oneClick(_ count: Int) -> String {
        t("header.oneClick", count)
    }

    static func major(_ count: Int) -> String {
        count == 1 ? t("header.major.one") : t("header.major", count)
    }

    static func checked(_ relative: String) -> String {
        t("header.checked", relative)
    }

    static func relative(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 45 { return t("time.now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
