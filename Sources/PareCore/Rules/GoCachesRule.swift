import Foundation

/// Removes reconstructible caches written by the Go toolchain.
/// Targets the Go build cache (~/Library/Caches/go-build/) and the module download
/// cache (~/go/pkg/mod/cache/ — zip archives and the hash database only).
/// Does NOT touch ~/go/pkg/mod/ beyond the cache/ subdirectory — the top-level module
/// directories are extracted source used directly during builds.
public struct GoCachesRule: ScanRule {
    public let id = "go-caches"
    public let title = "Go Toolchain Caches"
    public let reason = "Go build/module download cache (always reconstructible)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        let targets: [URL] = [
            home.appending(path: "Library/Caches/go-build"),
            home.appending(path: "go/pkg/mod/cache"),
        ]

        var findings: [ScanFinding] = []
        for target in targets {
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            let size = FileSystemUtils.directorySize(url: target)
            guard size > 0 else { continue }
            let lastUsed = try? target
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            findings.append(ScanFinding(
                category: category,
                riskLevel: riskLevel,
                reason: reason,
                path: target.path,
                sizeBytes: size,
                lastUsed: lastUsed,
                confidence: confidence
            ))
        }
        return findings
    }
}
