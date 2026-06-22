import Foundation

/// Removes reconstructible caches written by the Rust toolchain (Cargo and rustup).
/// Targets downloaded crate archives, extracted crate source, git-sourced crates,
/// and rustup component downloads.
/// Does NOT touch ~/.cargo/bin/ (installed binaries) or ~/.rustup/toolchains/ (installed toolchains).
public struct RustCachesRule: ScanRule {
    public let id = "rust-caches"
    public let title = "Rust Toolchain Caches"
    public let reason = "Rust toolchain download cache (Cargo/rustup — always reconstructible)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        let targets: [String] = [
            ".cargo/registry/cache",
            ".cargo/registry/src",
            ".cargo/git/db",
            ".cargo/git/checkouts",
            ".rustup/downloads",
        ]

        var findings: [ScanFinding] = []
        for path in targets {
            let url = home.appending(path: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let size = FileSystemUtils.directorySize(url: url)
            guard size > 0 else { continue }
            let lastUsed = try? url
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            findings.append(ScanFinding(
                category: category,
                riskLevel: riskLevel,
                reason: reason,
                path: url.path,
                sizeBytes: size,
                lastUsed: lastUsed,
                confidence: confidence
            ))
        }
        return findings
    }
}
