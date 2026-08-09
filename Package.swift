// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pare",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PareCore",
            targets: ["PareCore"]
        ),
        .executable(
            name: "PareApp",
            targets: ["PareApp"]
        ),
        .executable(
            name: "pare-cli",
            targets: ["PareCLI"]
        )
    ],
    targets: [
        .target(
            name: "PareCore",
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "PareApp",
            dependencies: ["PareCore"],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "PareCLI",
            dependencies: ["PareCore"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "PareCoreTests",
            dependencies: ["PareCore"],
            swiftSettings: strictConcurrency
        ),
        // Test targets may depend on executable targets since Swift 5.5;
        // debug builds compile with -enable-testing, so @testable import works.
        .testTarget(
            name: "PareAppTests",
            dependencies: ["PareApp"],
            swiftSettings: strictConcurrency
        )
    ]
)

/// Strict-concurrency checking (warnings in Swift 5 language mode).
/// Applied to every target so data-race issues surface at build time ahead of
/// the Swift 6 language-mode migration.
///
var strictConcurrency: [SwiftSetting] {
    [
        .enableUpcomingFeature("StrictConcurrency"),
    ]
}
