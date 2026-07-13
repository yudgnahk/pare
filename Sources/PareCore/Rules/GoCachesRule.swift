import Foundation

/// Reconstructible Go toolchain caches as whole folders.
/// Targets ~/Library/Caches/go-build/ and ~/go/pkg/mod/cache/ only.
/// Does NOT touch ~/go/pkg/mod/ beyond cache/ (extracted module source).
public struct GoCachesRule: ScanRule {
    public let id = "go-caches"
    public let title = "Go Toolchain Caches"
    public let reason = "Go build/module download cache (reconstructible on demand)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        let targets: [(URL, String)] = [
            (home.appending(path: "Library/Caches/go-build"),
             "Go build cache — reconstructible on next go build"),
            (home.appending(path: "go/pkg/mod/cache"),
             "Go module download cache — reconstructible on next go build"),
        ]

        var findings: [ScanFinding] = []
        for (target, reason) in targets {
            findings += PackageManagerCachesRule.directoryFindings(
                at: target,
                category: category,
                riskLevel: riskLevel,
                reason: reason,
                confidence: confidence
            )
        }
        return findings
    }
}
