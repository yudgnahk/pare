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
        )
    ]
)

/// Strict-concurrency checking (warnings in Swift 5 language mode).
/// Applied to every target so data-race issues surface at build time ahead of
/// the Swift 6 language-mode migration.
///
/// Both spellings are passed deliberately: on current toolchains the upcoming-
/// feature flag alone only enables *targeted* checking under swift-tools 5.9;
/// the experimental `StrictConcurrency=complete` spelling forces complete
/// checking (equivalent to `-strict-concurrency=complete`).
var strictConcurrency: [SwiftSetting] {
    [
        .enableUpcomingFeature("StrictConcurrency"),
        .enableExperimentalFeature("StrictConcurrency=complete"),
    ]
}
