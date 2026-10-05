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
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.4"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.15.1")
    ],
    targets: [
        .target(name: "BashCutProject", dependencies: [
            .product(name: "DequeModule", package: "swift-collections"),
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .target(name: "BashCutPlugin", dependencies: ["BashCutProject", .product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "BashCutImport", dependencies: ["BashCutProject"]),
        .target(name: "BashCutInterchange", dependencies: ["BashCutProject"]),
        // Tests: one target per module; shared project fixtures live in BashCutProjectFixtures.
        .target(name: "BashCutProjectFixtures", dependencies: ["BashCutProject"], path: "Tests/BashCutProjectFixtures"),
        // `swift run -c release bashcut-core-bench`: core edit, validation and history cost at scale.
        .executableTarget(name: "bashcut-core-bench", dependencies: ["BashCutProject"], path: "Benchmarks/CoreBench"),
        .testTarget(name: "BashCutProjectTests", dependencies: ["BashCutProject", "BashCutProjectFixtures"]),
        .testTarget(name: "BashCutPluginTests", dependencies: ["BashCutPlugin", "BashCutProject"]),
        .testTarget(name: "BashCutImportTests", dependencies: ["BashCutImport", "BashCutProject"]),
        .testTarget(name: "BashCutInterchangeTests", dependencies: ["BashCutInterchange", "BashCutImport", "BashCutProject"]),
    ]
)
