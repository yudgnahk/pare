import Foundation

/// Removes reconstructible download caches written by Python package managers.
/// Targets pip, Poetry, uv (under ~/Library/Caches/) and pyenv's build-time cache (~/.pyenv/cache/).
/// Does NOT touch ~/.pyenv/versions/ (installed Python runtimes) or any site-packages/ directory.
public struct PythonCachesRule: ScanRule {
    public let id = "python-caches"
    public let title = "Python Package Manager Caches"
    public let reason = "Python package manager download cache (always reconstructible)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        let lib = home.appending(path: "Library/Caches")
        let targets: [URL] = [
            lib.appending(path: "pip"),
            lib.appending(path: "pypoetry"),
            lib.appending(path: "uv"),
            home.appending(path: ".pyenv/cache"),
        ]

        var findings: [ScanFinding] = []
        for target in targets {
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            let size = environment.sizeIndex.directorySize(url: target)
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
