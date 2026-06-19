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
            name: "PareCore"
        ),
        .executableTarget(
            name: "PareApp",
            dependencies: ["PareCore"]
        ),
        .executableTarget(
            name: "PareCLI",
            dependencies: ["PareCore"]
        ),
        .testTarget(
            name: "PareCoreTests",
            dependencies: ["PareCore"]
        )
    ]
)
