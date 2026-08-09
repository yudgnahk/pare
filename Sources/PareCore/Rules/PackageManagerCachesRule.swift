import Foundation

/// Reconstructible package-manager download/extract caches reported as **whole
/// folders** (one finding per cache root or npx extract), not per-file noise.
public struct PackageManagerCachesRule: ScanRule {
    public let id = "package-manager-caches"
    public let title = "Package Manager Caches"
    public let reason = "Package manager download/extract cache (reconstructible on demand)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        var findings: [ScanFinding] = []

        let wholeRoots: [(path: String, reason: String)] = [
            (".npm/_cacache", "npm download cache (_cacache) — reconstructible"),
            ("Library/Caches/Yarn", "Yarn download cache — reconstructible"),
            ("Library/Caches/pnpm", "pnpm download cache — reconstructible"),
            ("Library/Caches/CocoaPods", "CocoaPods download cache — reconstructible"),
            ("Library/Caches/org.swift.swiftpm", "SwiftPM download cache — reconstructible"),
            (".bun/install/cache", "Bun install cache — reconstructible"),
        ]

        for entry in wholeRoots {
            findings += ScanFindingBuilder.directoryFindings(
                at: home.appending(path: entry.path),
                category: category,
                riskLevel: riskLevel,
                reason: entry.reason,
                confidence: confidence,
                sizeIndex: environment.sizeIndex
            )
        }

        // npx keeps one extract tree per package invocation hash — report each as a unit.
        let npxRoot = home.appending(path: ".npm/_npx")
        if FileManager.default.fileExists(atPath: npxRoot.path),
           let children = try? FileManager.default.contentsOfDirectory(
               at: npxRoot,
               includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
               options: [.skipsHiddenFiles]
           ) {
            for child in children {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                findings += ScanFindingBuilder.directoryFindings(
                    at: child,
                    category: category,
                    riskLevel: riskLevel,
                    reason: "npx package extract cache — reconstructible on next npx run",
                    confidence: confidence,
                    sizeIndex: environment.sizeIndex
                )
            }
        }

        return findings
    }
}
