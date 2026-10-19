import Foundation

public struct ParsedArguments: Sendable {
    public var command: String?
    public var positionals: [String] = []
    public var options: [String: [String]] = [:]
    public var flags: Set<String> = []
    public var errors: [String] = []

    public func value(_ name: String) -> String? {
        options[name]?.last
    }

    public func values(_ name: String) -> [String] {
        options[name] ?? []
    }

    public func flag(_ name: String) -> Bool {
        flags.contains(name)
    }
}

public enum ArgumentParser {
    private static let valueOptions: Set<String> = [
        "source", "lang", "limit", "timeout", "id", "name",
    ]

    private static let flagOptions: Set<String> = [
        "help", "json", "cached", "refresh", "all", "dry-run", "yes",
        "no-color", "quiet", "version", "check", "force",
    ]

    public static func parse(_ arguments: [String]) -> ParsedArguments {
        var parsed = ParsedArguments()
        var index = 0
        var positionalOnly = false

        while index < arguments.count {
            let argument = arguments[index]
            if positionalOnly {
                parsed.positionals.append(argument)
                index += 1
                continue
            }
            if argument == "--" {
                positionalOnly = true
                index += 1
                continue
            }
            if argument.hasPrefix("--") {
                let stripped = String(argument.dropFirst(2))
                let parts = stripped.split(separator: "=", maxSplits: 1).map(String.init)
                let name = parts[0]
                if parts.count == 2 {
                    guard valueOptions.contains(name) else {
                        parsed.errors.append("Unknown option --\(name)")
                        index += 1
                        continue
                    }
                    parsed.options[name, default: []].append(parts[1])
                } else if valueOptions.contains(name) {
                    guard index + 1 < arguments.count else {
                        parsed.errors.append("--\(name) needs a value")
                        index += 1
                        continue
                    }
                    parsed.options[name, default: []].append(arguments[index + 1])
                    index += 1
                } else if flagOptions.contains(name) {
                    parsed.flags.insert(name)
                } else {
                    parsed.errors.append("Unknown option --\(name)")
                }
                index += 1
                continue
            }
            if argument.hasPrefix("-"), argument != "-" {
                switch argument {
                case "-h": parsed.flags.insert("help")
                case "-j": parsed.flags.insert("json")
                case "-y": parsed.flags.insert("yes")
                case "-n": parsed.flags.insert("dry-run")
                case "-q": parsed.flags.insert("quiet")
                case "-v": parsed.flags.insert("version")
                default:
                    parsed.errors.append("Unknown option \(argument)")
                }
                index += 1
                continue
            }
            if parsed.command == nil {
                parsed.command = argument
            } else {
                parsed.positionals.append(argument)
            }
            index += 1
        }
        return parsed
    }
}
