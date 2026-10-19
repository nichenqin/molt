// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Remige",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "remige", targets: ["remige"]),
        .executable(name: "RemigeApp", targets: ["RemigeApp"]),
        .library(name: "RemigeCore", targets: ["RemigeCore"]),
        .library(name: "RemigeCLIKit", targets: ["RemigeCLIKit"]),
    ],
    targets: [
        .target(
            name: "RemigeCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "RemigeCLIKit",
            dependencies: ["RemigeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "remige",
            dependencies: ["RemigeCLIKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "RemigeApp",
            dependencies: ["RemigeCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RemigeCoreTests",
            dependencies: ["RemigeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RemigeCLIKitTests",
            dependencies: ["RemigeCLIKit", "RemigeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
