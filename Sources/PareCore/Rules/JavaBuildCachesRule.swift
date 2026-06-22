import Foundation

/// Removes caches written by Java/JVM build tools.
/// Gradle caches and wrapper distributions are `.safe` (always reconstructed from build scripts).
/// Maven local repository and Ivy2 cache are `.safe` for most users; Maven is tagged `.review`
/// because some teams publish internal artifacts to the local repo and rely on it offline.
public struct JavaBuildCachesRule: ScanRule {
    public let id = "java-build-caches"
    public let title = "Java/JVM Build Caches"
    public let reason = "Java/JVM build tool cache (Gradle/Maven/Ivy — reconstructible from build scripts)"
    public let category: ScanCategory = .developerBuildArtifacts
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.90

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory

        struct Target {
            let path: String
            let risk: RiskLevel
            let reason: String
        }

        let targets: [Target] = [
            Target(path: ".gradle/caches",
                   risk: .safe,
                   reason: "Gradle dependency and build cache (reconstructible)"),
            Target(path: ".gradle/wrapper/dists",
                   risk: .safe,
                   reason: "Gradle wrapper distribution archives (reconstructible)"),
            Target(path: ".m2/repository",
                   risk: .review,
                   reason: "Maven local repository — safe for most users; review if you publish internal artifacts offline"),
            Target(path: ".ivy2/cache",
                   risk: .safe,
                   reason: "Ivy/SBT dependency cache (reconstructible)"),
        ]

        var findings: [ScanFinding] = []
        for target in targets {
            let url = home.appending(path: target.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let size = FileSystemUtils.directorySize(url: url)
            guard size > 0 else { continue }
            let lastUsed = try? url
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            findings.append(ScanFinding(
                category: category,
                riskLevel: target.risk,
                reason: target.reason,
                path: url.path,
                sizeBytes: size,
                lastUsed: lastUsed,
                confidence: confidence
            ))
        }
        return findings
    }
}
