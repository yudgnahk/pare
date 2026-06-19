import Foundation

public enum ScanPolicy {
    public static let largeFileThresholdBytes: Int64 = 50 * 1024 * 1024
    public static let defaultCacheMinAgeSeconds: TimeInterval = 3 * 24 * 60 * 60

    // AI dotfile markers (e.g. "/.continue/cache", "/.tabnine") are appended from app-catalog.json
    // at first access — add new AI tools to the catalog, not here.
    private static let lowImpactMarkers: [String] = {
        let base: [String] = [
            "/library/caches/",
            "/library/logs/",
            "/library/diagnosticreports/",
            "/tmp/",
            "/temp/",
            "temporaryitems",
            "deriveddata",
            "/xcode/archives",
            "_cacache",
            "coresimulator/caches",
            "code cache",
            "gpucache",
        ]
        let catalogHomePaths = AppCatalog.shared.entries(forCategory: "ai")
            .flatMap { $0.homePaths }
            .map { "/\($0.lowercased())" }
        return base + catalogHomePaths
    }()

    private static let protectedPathMarkers = [
        "/documents/",
        "/desktop/",
        "/downloads/",
        "/library/application support/",
        "/library/containers/",
        "/library/group containers/",
        "/.git/"
    ]

    private static let sensitiveDataMarkers = [
        "bookmarks",
        "history",
        "login",
        "session",
        "cookies",
        "keychain"
    ]

    /// App-specific state paths that must never be deleted — removing them would
    /// break credentials, active sessions, or IDE state for the matching tool.
    private static let appStateSensitiveMarkers = [
        // VS Code — active user settings / keybindings / snippets
        "/library/application support/code/user/settings.json",
        "/library/application support/code/user/keybindings.json",
        "/library/application support/code/user/snippets",
        // JetBrains — active licence and IDE session tokens
        "/library/application support/jetbrains/consentoptions",
        "/library/application support/jetbrains/prefs.xml",
        // Docker — active daemon config
        "/library/containers/com.docker.docker/data/config",
        "/library/containers/com.docker.docker/data/daemon.json",
        // GitHub Desktop / git credentials
        "/.gitconfig",
        "/.git-credentials",
        // SSH keys (always protected)
        "/.ssh/"
    ]

    public static let designerSafePathMarkers = [
        "/library/caches/adobe",
        "/library/caches/com.adobe",
        "/library/caches/com.figma.desktop",
        "/library/application support/adobe/common/media cache",
        "/library/application support/figma/cache",
        "/library/application support/figma/desktop/cache"
    ]

    public static let designerReviewPathMarkers = [
        "/library/application support/adobe/common/peak files",
        "/movies/adobe premiere pro video previews",
        "/movies/adobe after effects disk cache"
    ]

    public static let videoBuilderSafePathMarkers = [
        "/library/caches/com.apple.finalcut",
        "/library/caches/adobe/premiere",
        "/library/caches/adobe/after effects",
        "/library/caches/blackmagic design/davinci resolve",
        "/library/application support/blackmagic design/davinci resolve/cache"
    ]

    public static let videoBuilderReviewPathMarkers = [
        "/movies/final cut pro render files",
        "/movies/final cut pro backups",
        "/movies/adobe premiere pro video previews",
        "/movies/adobe after effects disk cache",
        "/movies/davinci resolve/cacheclip"
    ]

    public static let developerSafePathMarkers = [
        "/library/caches/com.microsoft.vscode.shipit",
        "/library/application support/code/cachedextensionvsixs",
        "/library/logs/jetbrains",
        // Homebrew download cache — path contains "/downloads/" so isLowImpactPath blocks it;
        // listed here so matchesPersonaPath can reach it via the personaProtectedPathOverrides gate.
        "/library/caches/homebrew/downloads",
    ]

    /// Library paths for all AI tools in the catalog, lowercased for path matching.
    /// Derived from app-catalog.json — add new tools there, not here.
    public static let aiToolSafePathMarkers: [String] = AppCatalog.shared
        .entries(forCategory: "ai")
        .flatMap { $0.libraryPaths }
        .map { "/library/\($0.lowercased())" }

    /// File extensions that identify macOS installer packages.
    public static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "xip"]

    /// Returns `true` for installer files sitting inside `~/Downloads`, `~/Desktop`, or
    /// iCloud Drive (`~/Library/Mobile Documents/`). ZIP files are included so that
    /// installer ZIPs found by `InstallerFileRule` (which performs binary verification
    /// at scan time) can be cleaned by `CleanupEngine` after user confirmation.
    public static func isInstallerFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard installerExtensions.contains(ext) || ext == "zip" else { return false }
        let path = url.path.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()
        return path.hasPrefix(home + "/downloads/")
            || path.hasPrefix(home + "/desktop/")
            || path.hasPrefix(home + "/library/mobile documents/")
    }

    public static let developerReviewPathMarkers = [
        "/library/application support/code/user/workspacestorage",
        "/library/application support/code/user/history",
        "/.vscode/extensions/",
        "/library/application support/jetbrains/goland",
        "/library/application support/jetbrains/datagrip",
        "/library/application support/jetbrains/intellijidea",
        "/library/application support/jetbrains/pycharm",
        "/library/application support/jetbrains/webstorm",
        "/library/application support/jetbrains/phpstorm",
        "/library/application support/jetbrains/rider",
        "/library/application support/jetbrains/clion",
        "/library/application support/jetbrains/rubymine",
        "/library/application support/jetbrains/androidstudio",
        "/library/application support/jetbrains/fleet",
        "/library/application support/jetbrains/aqua",
        "/library/application support/jetbrains/dataspell",
        "/library/application support/jetbrains/rustrover"
    ]

    public static let developerDockerReviewPathMarkers = [
        "/library/containers/com.docker.docker/data/log"
    ]

    public static let developerReviewExclusionMarkers = [
        "/options/",
        "/workspace.xml",
        "/workspace/storage",
        "/projects/",
        "/projectsettings/",
        "/.idea/"
    ]

    // AI Application Support cache paths are appended from app-catalog.json at first access.
    private static let personaProtectedPathOverrides: [String] = {
        let base: [String] = [
            "/library/application support/adobe/common/media cache",
            "/library/application support/adobe/common/peak files",
            "/library/application support/figma/cache",
            "/library/application support/figma/desktop/cache",
            "/library/application support/blackmagic design/davinci resolve/cache",
            "/library/application support/code/cachedextensionvsixs",
            "/library/application support/code/user/workspacestorage",
            "/library/application support/code/user/history",
            "/library/application support/jetbrains",
            "/library/containers/com.docker.docker/data/log",
            "/library/caches/homebrew/downloads",
        ]
        let catalogPaths = AppCatalog.shared.entries(forCategory: "ai")
            .flatMap { $0.libraryPaths }
            .map { "/library/\($0.lowercased())" }
        return base + catalogPaths
    }()

    public static func defaultMinimumAgeSeconds(for category: ScanCategory) -> TimeInterval? {
        switch category {
        case .userCaches, .temporaryFiles, .browserCaches, .developerPackageCaches,
             .developerSimulatorCaches, .designerCaches, .videoBuilderCaches, .aiToolCaches:
            return defaultCacheMinAgeSeconds  // 3 days
        case .logsAndCrashReports:
            return 24 * 60 * 60  // 1 day
        case .installerFiles:
            return 7 * 24 * 60 * 60  // 7 days — avoid flagging freshly downloaded installers
        case .developerBuildArtifacts, .applications:
            return nil
        }
    }

    public static func matchesPersonaPath(_ url: URL, allowedMarkers: [String]) -> Bool {
        let path = url.path.lowercased()

        let isProtected = protectedPathMarkers.contains { path.contains($0) }
        if isProtected {
            let allowsProtectedPath = personaProtectedPathOverrides.contains { path.contains($0) }
            guard allowsProtectedPath else {
                return false
            }
        }

        let containsSensitiveDataMarker = sensitiveDataMarkers.contains { path.contains($0) }
        guard !containsSensitiveDataMarker else {
            return false
        }

        let containsAppStateSensitiveMarker = appStateSensitiveMarkers.contains { path.hasSuffix($0) || path.contains($0) }
        guard !containsAppStateSensitiveMarker else {
            return false
        }

        return allowedMarkers.contains { path.contains($0) }
    }

    public static func isLowImpactPath(_ url: URL) -> Bool {
        let path = url.path.lowercased()

        let isProtected = protectedPathMarkers.contains { path.contains($0) }
        guard !isProtected else {
            return false
        }

        let containsSensitiveDataMarker = sensitiveDataMarkers.contains { path.contains($0) }
        guard !containsSensitiveDataMarker else {
            return false
        }

        let containsAppStateSensitiveMarker = appStateSensitiveMarkers.contains { path.hasSuffix($0) || path.contains($0) }
        guard !containsAppStateSensitiveMarker else {
            return false
        }

        return lowImpactMarkers.contains { path.contains($0) }
    }

    /// The effective reference date for age comparisons.
    /// For files: the modification date.
    /// For directories: the OLDER of creation date and modification date.
    /// Using the oldest date is intentional — it handles two opposing edge cases:
    ///   • App migration resets mtime to today on an old directory → creation date is older → use it.
    ///   • Backup/Migration Assistant resets birthtime to restore date → mtime from before restore is older → use it.
    /// Tests can back-date mtime via setAttributes; creation date defaults to "now" and is thus newer,
    /// so the min() still defers to the backdated mtime — which is what the test intends.
    public static func effectiveAgeDate(from values: URLResourceValues) -> Date? {
        guard values.isDirectory == true else { return values.contentModificationDate }
        let candidates = [values.creationDate, values.contentModificationDate].compactMap { $0 }
        return candidates.min()
    }

    public static func passesMinimumAge(for resourceValues: URLResourceValues, minimumAgeSeconds: TimeInterval?) -> Bool {
        guard let minimumAgeSeconds else { return true }
        guard let date = effectiveAgeDate(from: resourceValues) else { return true }
        return Date().timeIntervalSince(date) >= minimumAgeSeconds
    }

    public static func isLargeFile(_ bytes: Int64) -> Bool {
        bytes > largeFileThresholdBytes
    }

    public static let windowsExecutableExtensions: Set<String> = ["exe", "msi", "dll"]
    public static let linuxExecutableExtensions: Set<String> = ["deb", "rpm", "appimage"]
    // Union — used for the CleanupEngine bypass guard.
    static let nonMacOSDownloadExtensions: Set<String> =
        windowsExecutableExtensions.union(linuxExecutableExtensions)

    /// Returns `true` for files that are unambiguously non-macOS platform binaries
    /// sitting at the TOP LEVEL of `~/Downloads`. This anchoring is intentional:
    /// it avoids falsely matching `.exe` files inside project `downloads/` subdirs
    /// or nested tool caches.
    public static func isWrongPlatformBinary(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard nonMacOSDownloadExtensions.contains(ext) else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()
        let downloadsPrefix = home + "/downloads/"
        let path = url.path.lowercased()
        guard path.hasPrefix(downloadsPrefix) else { return false }
        // Top-level only — reject files inside subdirectories of ~/Downloads.
        return !path.dropFirst(downloadsPrefix.count).contains("/")
    }
}
