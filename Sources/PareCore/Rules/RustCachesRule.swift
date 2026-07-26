import Foundation

/// Reconstructible Cargo/rustup download caches as whole folders.
/// Does NOT touch ~/.cargo/bin/ or ~/.rustup/toolchains/.
public struct RustCachesRule: ScanRule {
    public let id = "rust-caches"
    public let title = "Rust Toolchain Caches"
    public let reason = "Rust toolchain download cache (Cargo/rustup — reconstructible)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        let targets: [(String, String)] = [
            (".cargo/registry/cache", "Cargo registry download cache — reconstructible"),
            (".cargo/registry/src", "Cargo registry extracted source cache — reconstructible"),
            (".cargo/git/db", "Cargo git crate database — reconstructible"),
            (".cargo/git/checkouts", "Cargo git checkouts — reconstructible"),
            (".rustup/downloads", "rustup component download cache — reconstructible"),
        ]

        var findings: [ScanFinding] = []
        for (path, reason) in targets {
            findings += ScanFindingBuilder.directoryFindings(
                at: home.appending(path: path),
                category: category,
                riskLevel: riskLevel,
                reason: reason,
                confidence: confidence
            )
        }
        return findings
    }
}
