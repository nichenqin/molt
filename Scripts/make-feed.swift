import CryptoKit
import Foundation

// Generates the static update/download feed served by the website.
//   swift Scripts/make-feed.swift 0.2.0 dist site

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: make-feed.swift <version> <dist> <site>\n".utf8))
    exit(2)
}
let version = args[1]
let dist = URL(fileURLWithPath: args[2], isDirectory: true)
let site = URL(fileURLWithPath: args[3], isDirectory: true)
let repo = "nichenqin/molt"
let tag = "v\(version)"

func sha256(_ url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func releaseNotes(version: String) -> String {
    let changelog = URL(fileURLWithPath: "CHANGELOG.md")
    guard let text = try? String(contentsOf: changelog, encoding: .utf8) else { return "" }
    let lines = text.components(separatedBy: "\n")
    var collecting = false
    var result: [String] = []
    for line in lines {
        if line.hasPrefix("## ") {
            if collecting { break }
            collecting = line.contains(version)
            continue
        }
        if collecting { result.append(line) }
    }
    return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

struct Asset: Encodable {
    var name: String
    var url: String
    var sha256: String
    var size: Int
}

struct Manifest: Encodable {
    var schema: Int
    var version: String
    var published: String
    var notes: String
    var pageURL: String
    var assets: [String: Asset]
}

let names = ["Molt-macos.zip", "Molt-macos.dmg", "molt-cli"]
var assets: [String: Asset] = [:]
for name in names {
    let url = dist.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else {
        FileHandle.standardError.write(Data("missing asset: \(url.path)\n".utf8))
        exit(1)
    }
    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    assets[name] = Asset(
        name: name,
        url: "https://github.com/\(repo)/releases/download/\(tag)/\(name)",
        sha256: try sha256(url),
        size: size
    )
}

let formatter = ISO8601DateFormatter()
let manifest = Manifest(
    schema: 1,
    version: version,
    published: formatter.string(from: Date()),
    notes: releaseNotes(version: version),
    pageURL: "https://github.com/\(repo)/releases/tag/\(tag)",
    assets: assets
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
let data = try encoder.encode(manifest)
try data.write(to: site.appendingPathComponent("latest.json"), options: [.atomic])
print("wrote \(site.appendingPathComponent("latest.json").path)")
