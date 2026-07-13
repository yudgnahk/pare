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

    /// Docker Desktop log paths only (not the VM disk). Used by review/safe log rules.
    /// Never include `…/data/vms` here — that tree is the VM disk image (images, containers, volumes).
    public static let developerDockerReviewPathMarkers = [
        "/library/containers/com.docker.docker/data/log",
        "/library/group containers/group.com.docker/log",
    ]

    public static let developerDockerSafePathMarkers: [String] = [
        "/library/containers/com.docker.docker/data/log",
        "/library/containers/com.docker.docker/data/lifecycle-server.log",
        "/library/group containers/group.com.docker/log",
    ]

    /// Docker VM disk area — detect-only. Contains images, containers, build cache, AND volumes
    /// (e.g. Postgres data). Never delete via filesystem; never treat as normal cache.
    /// Prefer `isDockerNeverDeletePath` over matching these markers for cleanup.
    public static let developerDockerAdvancedPathMarkers: [String] = [
        "/library/containers/com.docker.docker/data/vms/0/data/docker.raw",
        "/library/containers/com.docker.docker/data/vms/0/data/",
        "/library/containers/com.docker.docker/data/vms/",
    ]

    /// `true` for Docker Desktop VM disk paths (`Docker.raw` and the `vms/…/data` tree).
    /// These must never be moved to Trash by Pare — reclaim space only via Docker CLI
    /// (`docker system prune` / `builder prune`) **without** `--volumes`.
    public static func isDockerNeverDeletePath(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        // Entire VM disk payload (not daemon logs under Data/log).
        if path.contains("/library/containers/com.docker.docker/data/vms/") {
            return true
        }
        if path.hasSuffix("/docker.raw") || path.contains("/docker.raw/") {
            return true
        }
        return false
    }

    /// Shader and GPU caches stored by Chromium-based browsers in Application Support.
    public static let browserExtendedSafePathMarkers: [String] = [
        "/library/application support/google/chrome/grshadercache",
        "/library/application support/microsoft edge/grshadercache",
        "/library/application support/BraveSoftware/brave-browser/grshadercache",
        "/library/application support/arc/user data/grshadercache",
        "/library/application support/com.operasoftware.opera/grshadercache",
    ]

    /// Session restore, WebSQL, IndexedDB, and local storage for Chromium-based browsers.
    public static let browserReviewDataPathMarkers: [String] = [
        // Safari
        "/library/safari/history.db",
        "/library/safari/cookies.binarycookies",
        "/library/safari/databases",
        "/library/safari/localstorage",
        // Chrome
        "/library/application support/google/chrome/default/history",
        "/library/application support/google/chrome/default/cookies",
        "/library/application support/google/chrome/default/web data",
        "/library/application support/google/chrome/default/indexeddb",
        "/library/application support/google/chrome/default/databases",
        // Brave
        "/library/application support/bravesoftware/brave-browser/default/history",
        "/library/application support/bravesoftware/brave-browser/default/cookies",
        "/library/application support/bravesoftware/brave-browser/default/web data",
        "/library/application support/bravesoftware/brave-browser/default/indexeddb",
        "/library/application support/bravesoftware/brave-browser/default/databases",
        // Edge
        "/library/application support/microsoft edge/default/history",
        "/library/application support/microsoft edge/default/cookies",
        "/library/application support/microsoft edge/default/web data",
        "/library/application support/microsoft edge/default/indexeddb",
        "/library/application support/microsoft edge/default/databases",
        // Arc
        "/library/application support/arc/user data/default/history",
        "/library/application support/arc/user data/default/cookies",
        "/library/application support/arc/user data/default/web data",
        "/library/application support/arc/user data/default/indexeddb",
        "/library/application support/arc/user data/default/databases",
        // Opera
        "/library/application support/com.operasoftware.opera/default/history",
        "/library/application support/com.operasoftware.opera/default/cookies",
        "/library/application support/com.operasoftware.opera/default/web data",
        "/library/application support/com.operasoftware.opera/default/indexeddb",
        "/library/application support/com.operasoftware.opera/default/databases",
    ]

    /// iOS / iPadOS backup directory markers.
    public static let mobileSyncBackupPathMarkers: [String] = [
        "/library/application support/mobilesync/backup",
    ]

    /// Safe cache paths for common productivity and collaboration apps.
    public static let productivitySafePathMarkers: [String] = [
        "/library/application support/slack/cache",
        "/library/application support/slack/cacheddata",
        "/library/caches/com.tinyspeck.slackmacgap",
        "/library/caches/us.zoom.xos",
        "/library/caches/com.google.drivefs.finderext",
        "/library/caches/com.dropbox.client2",
        "/library/application support/microsoft/teams/cache",
        "/library/caches/com.microsoft.teams2",
        "/library/caches/com.microsoft.teams",
        "/library/caches/com.microsoft.onedrive-mac",
        "/library/caches/com.microsoft.word",
        "/library/caches/com.microsoft.excel",
        "/library/caches/com.microsoft.powerpoint",
        "/library/caches/com.microsoft.outlook",
    ]

    /// Review-risk paths for productivity apps (recordings, document folders).
    public static let productivityReviewPathMarkers: [String] = [
        "/documents/zoom",
    ]

    /// Path marker for user-level launch agents.
    public static let launchAgentPathMarkers: [String] = [
        "/library/launchagents/",
    ]

    public static let browserExtendedReviewPathMarkers: [String] = [
        "/library/application support/google/chrome/default/sessions",
        "/library/application support/google/chrome/default/databases",
        "/library/application support/google/chrome/default/indexeddb",
        "/library/application support/google/chrome/default/local storage",
        "/library/application support/microsoft edge/default/sessions",
        "/library/application support/microsoft edge/default/databases",
        "/library/application support/microsoft edge/default/indexeddb",
        "/library/application support/microsoft edge/default/local storage",
        "/library/application support/bravesoftware/brave-browser/default/sessions",
        "/library/application support/bravesoftware/brave-browser/default/databases",
        "/library/application support/bravesoftware/brave-browser/default/indexeddb",
        "/library/application support/bravesoftware/brave-browser/default/local storage",
        "/library/application support/arc/user data/default/sessions",
        "/library/application support/arc/user data/default/databases",
        "/library/application support/arc/user data/default/indexeddb",
        "/library/application support/arc/user data/default/local storage",
        "/library/application support/com.operasoftware.opera/default/sessions",
        "/library/application support/com.operasoftware.opera/default/databases",
        "/library/application support/com.operasoftware.opera/default/indexeddb",
        "/library/application support/com.operasoftware.opera/default/local storage",
    ]

    /// Directory names that identify project build artifacts (e.g. node_modules, dist, venv).
    /// Used by `ProjectArtifactRule`, `ProjectArtifactsRule`, and `CleanupEngine` to allow safely
    /// cleaning user project trees.
    public static let projectArtifactDirectoryNames: Set<String> = [
        "node_modules", "target", "venv", ".venv", "__pycache__",
        "build", ".gradle", ".bundle", "dist", ".next", ".nuxt", ".cache",
        ".parcel-cache", ".turbo", ".nx",
    ]

    /// Path markers for polyglot package manager caches stored in dotfiles (Python/Ruby/Rust/Go/Java).
    /// These paths are NOT under ~/Library/Caches/ so they don't pass `isLowImpactPath` without help.
    /// Registered in `CleanupEngine.isPersonaPath` so findings from the Phase 6 cache rules can be cleaned.
    public static let developerPackageCacheMarkers: [String] = [
        "/.pyenv/cache",
        "/.cargo/registry/cache",
        "/.cargo/registry/src",
        "/.cargo/git/",
        "/.rustup/downloads",
        "/go/pkg/mod/cache",
        "/.gradle/caches",
        "/.gradle/wrapper/dists",
        "/.m2/repository",
        "/.ivy2/cache",
        "/.gem/ruby/",
        "/.bundle/cache",
        "/.rbenv/cache",
    ]

    /// Returns `true` when the URL's last path component is a known build-artifact directory name.
    public static func isProjectArtifact(_ url: URL) -> Bool {
        projectArtifactDirectoryNames.contains(url.lastPathComponent.lowercased())
    }

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
        return base + catalogPaths + browserExtendedSafePathMarkers + browserExtendedReviewPathMarkers
            + browserReviewDataPathMarkers + developerDockerSafePathMarkers + mobileSyncBackupPathMarkers
            + productivitySafePathMarkers + productivityReviewPathMarkers
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
        case .projectArtifacts:
            return 7 * 24 * 60 * 60  // 7 days — avoid flagging freshly created build dirs
        case .deviceBackups:
            return 30 * 24 * 60 * 60  // 30 days — don't flag recent backups
        case .productivityCaches:
            return defaultCacheMinAgeSeconds  // 3 days
        case .launchAgents:
            return 30 * 24 * 60 * 60  // 30 days — don't flag recently installed agents
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
    /// Returns `true` for apps inside /System/Applications — SIP-protected and cannot be removed.
    public static func isSystemApp(_ url: URL) -> Bool {
        url.path.hasPrefix("/System/")
    }

    /// Returns `true` for paths inside ~/Library/Group Containers.
    /// These are shared across app suites and must never be auto-selected for deletion.
    public static func isGroupContainer(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()
        return url.path.lowercased().hasPrefix("\(home)/library/group containers/")
    }

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
