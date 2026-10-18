import Foundation
import MoltCore

enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: .module, comment: "")
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
