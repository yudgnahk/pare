import Foundation

/// Cleans reconstructible cache files written by AI coding tools:
/// Cursor, Claude desktop, Windsurf (Application Support cache subdirs),
/// GitHub Copilot for Xcode (Library/Caches), Continue.dev and Tabnine (dotfile caches).
public struct AIToolCachesRule: ScanRule {
    public let id = "ai-tool-caches"
    public let title = "AI Tool Caches"
    public let reason = "AI coding tool cache (safe to regenerate)"
    public let category: ScanCategory = .aiToolCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.95

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        let home = environment.homeDirectory
        return [
            // Cursor (Electron) — HTTP, compiled JS, V8 bytecode caches
            home.appending(path: "Library/Application Support/Cursor/Cache"),
            home.appending(path: "Library/Application Support/Cursor/CachedData"),
            home.appending(path: "Library/Application Support/Cursor/Code Cache"),
            // Claude desktop (Electron)
            home.appending(path: "Library/Application Support/Claude/Cache"),
            home.appending(path: "Library/Application Support/Claude/CachedData"),
            home.appending(path: "Library/Application Support/Claude/Code Cache"),
            // Windsurf by Codeium (Electron)
            home.appending(path: "Library/Application Support/Windsurf/Cache"),
            home.appending(path: "Library/Application Support/Windsurf/CachedData"),
            home.appending(path: "Library/Application Support/Windsurf/Code Cache"),
            // GitHub Copilot for Xcode
            home.appending(path: "Library/Caches/com.github.copilot-for-xcode"),
            // Continue.dev — model response cache and embedding index
            home.appending(path: ".continue/cache"),
            home.appending(path: ".continue/.index"),
            // Tabnine — downloaded model binaries and intermediate caches
            home.appending(path: ".tabnine"),
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        guard ScanPolicy.isLowImpactPath(fileURL)
                || ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.aiToolSafePathMarkers) else {
            return false
        }
        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
