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

        // -- Shader / GPU / Code caches (.safe) — no age gate (regenerable) --
        let safeRoots: [(String, String)] = [
            ("Library/Application Support/Google/Chrome", "Chrome"),
            ("Library/Application Support/Microsoft Edge", "Microsoft Edge"),
            ("Library/Application Support/BraveSoftware/Brave-Browser", "Brave"),
            ("Library/Application Support/Arc/User Data", "Arc"),
            ("Library/Application Support/com.operasoftware.Opera", "Opera"),
        ]
        let safeSuffixes: [(String, String)] = [
            ("GrShaderCache", "GPU shader cache"),
            ("GraphiteDawnCache", "Graphite Dawn cache"),
            ("ShaderCache", "shader cache"),
        ]
        let safeProfileSuffixes: [(String, String)] = [
            ("Service Worker", "Service Worker cache (regenerated automatically)"),
            ("GPUCache", "GPU cache"),
            ("Code Cache", "V8 code cache"),
            ("DawnWebGPUCache", "WebGPU cache"),
            ("DawnGraphiteCache", "Dawn Graphite cache"),
        ]

        for (rootRel, browser) in safeRoots {
            let root = home.appending(path: rootRel)
            for (suffix, label) in safeSuffixes {
                findings += artifactFindings(
                    at: root.appending(path: suffix),
                    reason: "\(browser) \(label) (regenerated automatically)",
                    riskLevel: .safe,
                    applyAgeGate: false,
                    sizeIndex: environment.sizeIndex
                )
            }
            // Multi-profile: Default, Profile 1, Guest Profile, …
            for profile in Self.chromiumProfileDirs(under: root) {
                let profileName = profile.lastPathComponent
                for (suffix, label) in safeProfileSuffixes {
                    findings += artifactFindings(
                        at: profile.appending(path: suffix),
                        reason: "\(browser) \(profileName) \(label)",
                        riskLevel: .safe,
                        applyAgeGate: false,
                        sizeIndex: environment.sizeIndex
                    )
                }
            }
        }

        // -- Session restore, WebSQL, IndexedDB, local storage (.review) --
        // Local Storage / IndexedDB can hold site state and auth tokens — never auto-clean.
        let reviewProfileSuffixes: [(String, String)] = [
            ("Sessions", "session restore"),
            ("databases", "WebSQL databases"),
            ("IndexedDB", "IndexedDB"),
            ("Local Storage", "local storage (may include site logins)"),
        ]
        for (rootRel, browser) in safeRoots {
            let root = home.appending(path: rootRel)
            for profile in Self.chromiumProfileDirs(under: root) {
                let profileName = profile.lastPathComponent
                for (suffix, label) in reviewProfileSuffixes {
                    findings += artifactFindings(
                        at: profile.appending(path: suffix),
                        reason: "\(browser) \(profileName) \(label)",
                        riskLevel: .review,
                        applyAgeGate: true,
                        sizeIndex: environment.sizeIndex
                    )
                }
            }
        }

        return findings
    }

    // MARK: Private

    /// Chromium profile directories (Default, Profile N, Guest Profile, System Profile).
    private static func chromiumProfileDirs(under root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            let name = url.lastPathComponent
            if name == "Default" || name == "Guest Profile" || name == "System Profile" {
                return true
            }
            if name.hasPrefix("Profile ") { return true }
            return false
        }
    }

    private func artifactFindings(
        at url: URL,
        reason: String,
        riskLevel: RiskLevel,
        applyAgeGate: Bool,
        sizeIndex: DirectorySizeIndex
    ) -> [ScanFinding] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = sizeIndex.directorySize(url: url)
        guard size > 0 else { return [] }

        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey])
        let lastUsed = resourceValues.flatMap(ScanPolicy.effectiveAgeDate)

        if applyAgeGate,
           let date = lastUsed,
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
