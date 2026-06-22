import Foundation

/// Targets extended browser artifacts not covered by `BrowserCachesRule`:
///   - **Safe** (auto-cleanable): shader / GPU caches stored in Application Support
///     (GrShaderCache directories used by Chromium-based browsers).
///   - **Review**: session restore files, WebSQL databases, IndexedDB stores, and
///     local storage for Chrome, Edge, Brave, Arc, and Opera.
///
/// Uses `customScan` so that findings can carry mixed risk levels and the rule can
/// skip browsers that are not installed without any traversal overhead.
public struct BrowserExtendedArtifactsRule: ScanRule {
    public let id = "browser-extended-artifacts"
    public let title = "Browser Extended Artifacts"
    public let reason = "Browser session, storage, or shader cache artifact"
    public let category: ScanCategory = .browserCaches
    public let riskLevel: RiskLevel = .review  // most conservative; individual findings vary
    public let confidence: Double = 0.85

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        var findings: [ScanFinding] = []

        // -- Shader caches (.safe) --
        let shaderPaths: [(String, String)] = [
            ("Library/Application Support/Google/Chrome/GrShaderCache", "Chrome"),
            ("Library/Application Support/Microsoft Edge/GrShaderCache", "Microsoft Edge"),
            ("Library/Application Support/BraveSoftware/Brave-Browser/GrShaderCache", "Brave"),
            ("Library/Application Support/Arc/User Data/GrShaderCache", "Arc"),
            ("Library/Application Support/com.operasoftware.Opera/GrShaderCache", "Opera"),
        ]
        for (relPath, browser) in shaderPaths {
            findings += artifactFindings(
                at: home.appending(path: relPath),
                reason: "\(browser) GPU shader cache (regenerated automatically)",
                riskLevel: .safe
            )
        }

        // -- Session restore, WebSQL, IndexedDB, local storage (.review) --
        let reviewTargets: [(String, String)] = [
            ("Library/Application Support/Google/Chrome/Default/Sessions", "Chrome session restore"),
            ("Library/Application Support/Google/Chrome/Default/databases", "Chrome WebSQL databases"),
            ("Library/Application Support/Google/Chrome/Default/IndexedDB", "Chrome IndexedDB"),
            ("Library/Application Support/Google/Chrome/Default/Local Storage", "Chrome local storage"),
            ("Library/Application Support/Microsoft Edge/Default/Sessions", "Edge session restore"),
            ("Library/Application Support/Microsoft Edge/Default/databases", "Edge WebSQL databases"),
            ("Library/Application Support/Microsoft Edge/Default/IndexedDB", "Edge IndexedDB"),
            ("Library/Application Support/Microsoft Edge/Default/Local Storage", "Edge local storage"),
            ("Library/Application Support/BraveSoftware/Brave-Browser/Default/Sessions", "Brave session restore"),
            ("Library/Application Support/BraveSoftware/Brave-Browser/Default/databases", "Brave WebSQL databases"),
            ("Library/Application Support/BraveSoftware/Brave-Browser/Default/IndexedDB", "Brave IndexedDB"),
            ("Library/Application Support/BraveSoftware/Brave-Browser/Default/Local Storage", "Brave local storage"),
            ("Library/Application Support/Arc/User Data/Default/Sessions", "Arc session restore"),
            ("Library/Application Support/Arc/User Data/Default/databases", "Arc WebSQL databases"),
            ("Library/Application Support/Arc/User Data/Default/IndexedDB", "Arc IndexedDB"),
            ("Library/Application Support/Arc/User Data/Default/Local Storage", "Arc local storage"),
            ("Library/Application Support/com.operasoftware.Opera/Default/Sessions", "Opera session restore"),
            ("Library/Application Support/com.operasoftware.Opera/Default/databases", "Opera WebSQL databases"),
            ("Library/Application Support/com.operasoftware.Opera/Default/IndexedDB", "Opera IndexedDB"),
            ("Library/Application Support/com.operasoftware.Opera/Default/Local Storage", "Opera local storage"),
        ]
        for (relPath, reason) in reviewTargets {
            findings += artifactFindings(
                at: home.appending(path: relPath),
                reason: reason,
                riskLevel: .review
            )
        }

        return findings
    }

    // MARK: Private

    private func artifactFindings(at url: URL, reason: String, riskLevel: RiskLevel) -> [ScanFinding] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = FileSystemUtils.directorySize(url: url)
        guard size > 0 else { return [] }

        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let lastUsed = resourceValues?.contentModificationDate

        // Skip directories that haven't aged past the cache minimum.
        if let date = lastUsed,
           Date().timeIntervalSince(date) < ScanPolicy.defaultCacheMinAgeSeconds {
            return []
        }

        return [ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            path: url.path,
            sizeBytes: size,
            lastUsed: lastUsed,
            confidence: confidence
        )]
    }
}
