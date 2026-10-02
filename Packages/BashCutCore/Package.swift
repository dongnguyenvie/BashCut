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
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(name: "BashCutProject", dependencies: [
            .product(name: "DequeModule", package: "swift-collections")
        ]),
        .target(name: "BashCutPlugin", dependencies: ["BashCutProject"]),
        .target(name: "BashCutImport", dependencies: ["BashCutProject"]),
        .target(name: "BashCutInterchange", dependencies: ["BashCutProject"]),
        .testTarget(name: "BashCutProjectTests", dependencies: ["BashCutProject", "BashCutImport",
            "BashCutInterchange",
            "BashCutPlugin",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
        ])
    ]
)
