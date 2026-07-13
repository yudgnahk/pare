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

    /// Whether an app path / name looks managed by a known Caskroom token.
    public static func manages(
        appName: String,
        path: String,
        installedTokens: Set<String>? = nil
    ) -> Bool {
        if path.contains("/Caskroom/") { return true }

        let tokens = installedTokens ?? Self.installedTokens()
        guard !tokens.isEmpty else { return false }

        let normalized = normalizeAppName(appName)
        let pathBase = URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
        let normalizedPath = normalizeAppName(pathBase)

        for token in tokens {
            let t = token.lowercased()
            if t == normalized || t == normalizedPath { return true }
            // e.g. token "google-chrome" vs app "Google Chrome"
            if normalized.contains(t) || t.contains(normalized) { return true }
            if normalizedPath.contains(t) || t.contains(normalizedPath) { return true }
        }
        return false
    }

    /// Best-effort cask token for an app, if any Caskroom entry matches.
    public static func token(
        forAppName appName: String,
        path: String,
        installedTokens: Set<String>? = nil
    ) -> String? {
        if path.contains("/Caskroom/") {
            // …/Caskroom/<token>/<version>/App.app
            let parts = path.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(of: "Caskroom"), idx + 1 < parts.count {
                return parts[idx + 1]
            }
        }

        let tokens = installedTokens ?? Self.installedTokens()
        let normalized = normalizeAppName(appName)
        let pathBase = normalizeAppName(
            URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        )

        // Prefer exact matches
        for token in tokens {
            let t = token.lowercased()
            if t == normalized || t == pathBase { return token }
        }
        for token in tokens {
            let t = token.lowercased()
            if normalized.contains(t) || t.contains(normalized)
                || pathBase.contains(t) || t.contains(pathBase) {
                return token
            }
        }
        return nil
    }

    public static func normalizeAppName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: " ", with: "-")
    }
}
