import Foundation

/// A pragmatic version comparator for package ecosystems.
///
/// It intentionally does not implement SemVer only: Homebrew revisions (`1_2`),
/// Sparkle build numbers, calendar versions and tags with a leading `v` all occur
/// in feeds. Numeric components compare numerically, a release outranks its
/// prereleases, and trailing zero components do not matter (`1.0 == 1.0.0`).
public struct Version: Comparable, Sendable, CustomStringConvertible {
    private enum Component: Hashable, Sendable {
        case number(UInt64)
        case text(String)
    }

    public let raw: String
    private let components: [Component]
    private let prerelease: [Component]

    public init?(_ input: String) {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        // Sparkle feeds and casks sometimes use "1.2.3,456" for version,build.
        if let comma = value.firstIndex(of: ",") {
            value = String(value[..<comma])
        }
        guard value.contains(where: \.isNumber) else { return nil }

        var preReleasePart: Substring?
        if let plus = value.firstIndex(of: "+") {
            value = String(value[..<plus])
        }
        if let dash = value.firstIndex(of: "-") {
            preReleasePart = value[value.index(after: dash)...]
            value = String(value[..<dash])
        }

        let base = Self.components(from: value)
        guard !base.isEmpty else { return nil }
        self.raw = input
        self.components = base
        self.prerelease = preReleasePart.map { Self.components(from: String($0)) } ?? []
    }

    private static func components(from value: String) -> [Component] {
        var result: [Component] = []
        var numberBuffer = ""
        var textBuffer = ""

        func flushNumber() {
            if !numberBuffer.isEmpty {
                result.append(.number(UInt64(numberBuffer) ?? Self.bigNumber(numberBuffer)))
                numberBuffer = ""
            }
        }
        func flushText() {
            if !textBuffer.isEmpty {
                result.append(.text(textBuffer.lowercased()))
                textBuffer = ""
            }
        }

        for character in value {
            if character.isNumber {
                flushText()
                numberBuffer.append(character)
            } else if character.isLetter {
                flushNumber()
                textBuffer.append(character)
            } else {
                flushNumber()
                flushText()
            }
        }
        flushNumber()
        flushText()
        return result
    }

    /// Saturates absurdly long numeric components; ordering by length still works.
    private static func bigNumber(_ digits: String) -> UInt64 {
        let significant = digits.drop(while: { $0 == "0" })
        guard significant.count <= 18 else { return UInt64.max }
        return UInt64(significant) ?? UInt64.max
    }

    public var description: String { raw }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        let base = compareComponents(lhs.components, rhs.components)
        if base != .orderedSame { return base == .orderedAscending }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false  // release > prerelease
        case (false, true): return true
        case (false, false):
            return compareComponents(lhs.prerelease, rhs.prerelease) == .orderedAscending
        }
    }

    public static func == (lhs: Version, rhs: Version) -> Bool {
        compareComponents(lhs.components, rhs.components) == .orderedSame
            && compareComponents(lhs.prerelease, rhs.prerelease) == .orderedSame
    }

    private static func compareComponents(_ lhs: [Component], _ rhs: [Component]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : nil
            let right = index < rhs.count ? rhs[index] : nil
            switch (left, right) {
            case (nil, nil):
                continue
            case (.some(let left), nil):
                if isZero(left) { continue }
                return .orderedDescending
            case (nil, .some(let right)):
                if isZero(right) { continue }
                return .orderedAscending
            case (.some(let left), .some(let right)):
                let result = compare(left, right)
                if result != .orderedSame { return result }
            }
        }
        return .orderedSame
    }

    private static func isZero(_ component: Component) -> Bool {
        if case .number(let value) = component { return value == 0 }
        return false
    }

    private static func compare(_ lhs: Component, _ rhs: Component) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.number(let left), .number(let right)):
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case (.text(let left), .text(let right)):
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case (.number, .text):
            // "1.0.1" is newer than "1.0.1beta" in the feeds we consume.
            return .orderedDescending
        case (.text, .number):
            return .orderedAscending
        }
    }

    public func isNewer(than other: Version) -> Bool {
        self > other
    }

    // MARK: Extraction

    private static let defaultVersionPattern = #"v?(\d+(?:[._]\d+)+(?:[-+][0-9A-Za-z.]+)?)"#

    /// Finds a dotted version in command output. A catalog entry may provide a
    /// tighter expression; capture group 1 wins when present.
    public static func extract(from text: String, regex: String? = nil) -> Version? {
        let pattern = regex ?? defaultVersionPattern
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }
        let capture = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard capture.location != NSNotFound, let swiftRange = Range(capture, in: text) else {
            return nil
        }
        let candidate = String(text[swiftRange])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n,;()[]"))
        return Version(candidate)
    }
}
