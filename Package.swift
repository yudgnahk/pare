// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "App B",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "App BCore",
            targets: ["App BCore"]
        ),
        .executable(
            name: "pare-cli",
            targets: ["App BCLI"]
        )
    ],
    targets: [
        .target(
            name: "App BCore"
        ),
        .executableTarget(
            name: "App BCLI",
            dependencies: ["App BCore"]
        ),
        .testTarget(
            name: "App BCoreTests",
            dependencies: ["App BCore"]
        )
    ]
)
