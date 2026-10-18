// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Molt",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "molt", targets: ["molt"]),
        .executable(name: "MoltApp", targets: ["MoltApp"]),
        .library(name: "MoltCore", targets: ["MoltCore"]),
        .library(name: "MoltCLIKit", targets: ["MoltCLIKit"]),
    ],
    targets: [
        .target(
            name: "MoltCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MoltCLIKit",
            dependencies: ["MoltCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "molt",
            dependencies: ["MoltCLIKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MoltApp",
            dependencies: ["MoltCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MoltCoreTests",
            dependencies: ["MoltCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MoltCLIKitTests",
            dependencies: ["MoltCLIKit", "MoltCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
