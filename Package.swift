// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanMyMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CleanMyMacCore",
            targets: ["CleanMyMacCore"]
        ),
        .executable(
            name: "cleanmymac-cli",
            targets: ["CleanMyMacCLI"]
        )
    ],
    targets: [
        .target(
            name: "CleanMyMacCore"
        ),
        .executableTarget(
            name: "CleanMyMacCLI",
            dependencies: ["CleanMyMacCore"]
        ),
        .testTarget(
            name: "CleanMyMacCoreTests",
            dependencies: ["CleanMyMacCore"]
        )
    ]
)
