// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BashCutCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BashCutProject", targets: ["BashCutProject"]),
        .library(name: "BashCutPlugin", targets: ["BashCutPlugin"]),
        .library(name: "BashCutImport", targets: ["BashCutImport"]),
        .library(name: "BashCutInterchange", targets: ["BashCutInterchange"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.4")
    ],
    targets: [
        .target(name: "BashCutProject", dependencies: [
            .product(name: "DequeModule", package: "swift-collections")
        ]),
        .target(name: "BashCutPlugin", dependencies: ["BashCutProject"]),
        .target(name: "BashCutImport", dependencies: ["BashCutProject"]),
        .target(name: "BashCutInterchange", dependencies: ["BashCutProject"]),
        // Tests: one target per module; shared project fixtures live in BashCutProjectFixtures.
        .target(name: "BashCutProjectFixtures", dependencies: ["BashCutProject"], path: "Tests/BashCutProjectFixtures"),
        .testTarget(name: "BashCutProjectTests", dependencies: ["BashCutProject", "BashCutProjectFixtures"]),
        .testTarget(name: "BashCutPluginTests", dependencies: ["BashCutPlugin", "BashCutProject"]),
        .testTarget(name: "BashCutImportTests", dependencies: ["BashCutImport", "BashCutProject"]),
        .testTarget(name: "BashCutInterchangeTests", dependencies: ["BashCutInterchange", "BashCutImport", "BashCutProject"]),
    ]
)
