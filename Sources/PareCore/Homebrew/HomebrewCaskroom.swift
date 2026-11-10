import Foundation

/// Shared helpers for detecting Homebrew-managed casks on disk.
///
/// After `brew install --cask --adopt <token>`, a receipt appears under
/// `/opt/homebrew/Caskroom/<token>` (or `/usr/local/Caskroom`).  The migrate
/// list must exclude any token already present there, and App Manager should
/// mark matching apps as Homebrew-managed.
public enum HomebrewCaskroom: Sendable {

    public static let searchPaths = [
        "/opt/homebrew/Caskroom",
        "/usr/local/Caskroom"
    ]

    /// Tokens of casks currently recorded in Caskroom (adopted or installed).
    public static func installedTokens() -> Set<String> {
        var tokens = Set<String>()
        for root in searchPaths {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else {
                continue
            }
            for entry in entries where !entry.hasPrefix(".") {
                // Require at least one version directory so empty folders don't count.
                let versionDir = "\(root)/\(entry)"
                if let versions = try? FileManager.default.contentsOfDirectory(atPath: versionDir),
                   versions.contains(where: { !$0.hasPrefix(".") }) {
                    tokens.insert(entry)
                }
            }
        }
        return tokens
    }

    /// Resolved targets of the artifact symlinks Caskroom keeps in each `<token>/<version>/` (lowercased paths).
    public static func installedArtifactPaths(roots: [String] = searchPaths) -> Set<String> {
        var targets = Set<String>()
        let fm = FileManager.default
        for root in roots {
            for token in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !token.hasPrefix(".") {
                let tokenDir = "\(root)/\(token)"
                for version in (try? fm.contentsOfDirectory(atPath: tokenDir)) ?? [] where !version.hasPrefix(".") {
                    let versionDir = "\(tokenDir)/\(version)"
                    for entry in (try? fm.contentsOfDirectory(atPath: versionDir)) ?? [] {
                        guard let dest = try? fm.destinationOfSymbolicLink(atPath: "\(versionDir)/\(entry)"),
                              dest.hasPrefix("/") else { continue }
                        targets.insert(dest.lowercased())
                    }
                }
            }
        }
        return targets
    }

    /// Whether this exact bundle was installed by a cask: a Caskroom path, an installed artifact target, or a top-level app named exactly like a token.
    public static func manages(
        appName: String,
        path: String,
        installedTokens: Set<String>? = nil,
        installedArtifactPaths: Set<String>? = nil
    ) -> Bool {
        if isCaskroomPath(path) { return true }
        let artifacts = installedArtifactPaths ?? Self.installedArtifactPaths()
        if artifacts.contains(path.lowercased()) { return true }
        return exactToken(
            appName: appName, path: path, tokens: installedTokens ?? Self.installedTokens()
        ) != nil
    }

    /// Best-effort cask token for an app: Caskroom path, else an exact top-level name match.
    public static func token(
        forAppName appName: String,
        path: String,
        installedTokens: Set<String>? = nil
    ) -> String? {
        if isCaskroomPath(path) {
            // …/Caskroom/<token>/<version>/App.app
            let parts = path.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(where: { $0.lowercased() == "caskroom" }), idx + 1 < parts.count {
                return parts[idx + 1]
            }
        }
        return exactToken(appName: appName, path: path, tokens: installedTokens ?? Self.installedTokens())
    }

    private static func isCaskroomPath(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.lowercased() == "caskroom" }
    }

    /// Exact normalized-name match, only for apps sitting directly in /Applications or ~/Applications.
    private static func exactToken(appName: String, path: String, tokens: Set<String>) -> String? {
        guard !tokens.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let parent = url.deletingLastPathComponent()
        let topLevel = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
            .contains { $0.standardizedFileURL.pathComponents.map { $0.lowercased() }
                == parent.standardizedFileURL.pathComponents.map { $0.lowercased() } }
        guard topLevel else { return nil }

        let names: Set<String> = [
            normalizeAppName(appName),
            normalizeAppName(url.deletingPathExtension().lastPathComponent)
        ]
        return tokens.first { names.contains($0.lowercased()) }
    }

    public static func normalizeAppName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: " ", with: "-")
    }
}
