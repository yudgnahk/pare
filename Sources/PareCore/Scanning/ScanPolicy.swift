import Foundation

public enum ScanPolicy {
    public static let largeFileThresholdBytes: Int64 = 50 * 1024 * 1024
    public static let defaultCacheMinAgeSeconds: TimeInterval = 3 * 24 * 60 * 60

    /// Pure reconstructible download/extract caches (npx, npm cacache, Go/Cargo
    /// module caches, AI tool package caches, Homebrew bottles). No age gate —
    /// they rebuild on demand (same policy as common Mac cleaners).
    public static let reconstructibleCacheMinAgeSeconds: TimeInterval = 0

    /// Path markers for pure reconstructible package/toolchain download caches.
    public static let reconstructibleCachePathMarkers: [String] = [
        "/.npm/_npx",
        "/.npm/_cacache",
        "/library/caches/go-build",
        "/.cargo/registry/",
        "/.cargo/git/",
        "/.rustup/downloads",
        "/go/pkg/mod/cache",
        "/.cache/opencode",
        "/.local/share/opencode/",
        "/library/caches/homebrew",
        "/library/caches/yarn",
        "/library/caches/pnpm",
        "/library/caches/cocoapods",
        "/library/caches/org.swift.swiftpm",
        "/.bun/install/cache",
        // UserCachesRule reports whole Library/Caches/* folders.
        "/library/caches/",
        // Wallpaper agent cache only — search-index paths are never reconstructible-clean targets.
        "/library/containers/com.apple.wallpaper.agent/data/library/caches",
    ]

    // MARK: - Search-index sensitive paths (never clean)

    /// Paths whose deletion forces Spotlight / Core Spotlight / Help / media analysis
    /// to rebuild indexes (high CPU, can take a long time). Never report or trash these.
    public static let searchIndexSensitivePathMarkers: [String] = [
        "/library/caches/com.apple.spotlight",
        "/library/caches/com.apple.metadata",
        "/library/caches/metadata",
        "/library/caches/com.apple.helpd",
        "/library/suggestions",
        "/library/containers/com.apple.mediaanalysisd/",
        "/library/metadata/",
        "/.spotlight-v100",
        "/.spotlight-v200",
    ]

    /// Top-level `~/Library/Caches` folder names that must never be offered for cleanup.
    public static let searchIndexSensitiveCacheFolderNames: Set<String> = [
        "com.apple.spotlight",
        "com.apple.metadata",
        "metadata",
        "com.apple.helpd",
    ]

    public static func isSearchIndexSensitivePath(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return searchIndexSensitivePathMarkers.contains { path.contains($0) }
    }

    /// Large cleans cause heavy incremental Spotlight work (FSEvents), even without
    /// touching search-index caches. Thresholds for a user-facing heads-up.
    public static let largeCleanSpotlightWarningItemThreshold = 100
    public static let largeCleanSpotlightWarningBytesThreshold: Int64 = 1 * 1024 * 1024 * 1024 // 1 GB

    public static func shouldWarnAboutSpotlightIndexing(itemCount: Int, totalBytes: Int64) -> Bool {
        itemCount >= largeCleanSpotlightWarningItemThreshold
            || totalBytes >= largeCleanSpotlightWarningBytesThreshold
    }

    public static func isReconstructibleCachePath(_ url: URL) -> Bool {
        if isSearchIndexSensitivePath(url) { return false }
        let path = url.path.lowercased()
        return reconstructibleCachePathMarkers.contains { path.contains($0) }
    }

    /// Age gate for cleanup re-checks. Reconstructible package caches use a short
    /// floor; other categories keep their default.
    public static func minimumAgeSeconds(forCleanupPath url: URL, category: ScanCategory) -> TimeInterval? {
        if isReconstructibleCachePath(url) {
            return reconstructibleCacheMinAgeSeconds
        }
        return defaultMinimumAgeSeconds(for: category)
    }

    /// `true` when the URL's last activity is at least `minimumAgeSeconds` ago.
    /// Prefers **mtime** (updates when the cache is used); falls back to creation date.
    public static func passesUnusedAge(for url: URL, minimumAgeSeconds: TimeInterval) -> Bool {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return true }
        guard let lastUsed = values.contentModificationDate ?? values.creationDate else { return true }
        return Date().timeIntervalSince(lastUsed) >= minimumAgeSeconds
    }

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
        // Installed extensions are live installs — only wrong-platform stubs and
        // duplicate versions are reclaimable, not the whole extension tree as review.
        "/library/application support/cursor/cachedextensionvsixs",
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
        "/library/application support/bravesoftware/brave-browser/grshadercache",
        "/library/application support/arc/user data/grshadercache",
        "/library/application support/com.operasoftware.opera/grshadercache",
        // Regenerable Chromium profile caches (Service Worker, GPU, Code Cache).
        "/service worker",
        "/gpucache",
        "/code cache",
        "/dawnwebgpucache",
        "/dawngraphitecache",
        "/graphitedawncache",
        "/shadercache",
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

    /// Project **dependency trees** (libs/deps at project root).
    /// These are *not* free space — removing them breaks installs until reinstall.
    /// Pare must **not** count them as reclaimable. Prefer global caches (`~/.npm`, cargo, etc.).
    public static let projectDependencyDirectoryNames: Set<String> = [
        "node_modules",
        "venv",
        ".venv",
        ".bundle",          // Ruby bundler project-local gems
    ]

    /// Project-**local** build/tool caches and outputs (regenerable by build).
    /// These are the only project dirs Pare surfaces as reclaimable findings.
    public static let projectLocalArtifactDirectoryNames: Set<String> = [
        "__pycache__",
        ".cache",
        ".parcel-cache",
        ".turbo",
        ".nx",
        ".next",
        ".nuxt",
        "target",           // Rust/Java-style build output (not third-party deps)
        "build",
        "dist",
        ".gradle",          // project-local Gradle cache
        ".pytest_cache",
        ".mypy_cache",
        ".ruff_cache",
        "coverage",
        ".tox",
        ".eggs",
    ]

    /// Union used by walkers and cleanup path allow-lists for *local* artifacts only.
    /// Does **not** include dependency trees (`node_modules`, `.venv`, …).
    public static let projectArtifactDirectoryNames: Set<String> = projectLocalArtifactDirectoryNames

    /// `true` when the directory name is a dependency tree that must never be reclaimable.
    public static func isProjectDependencyDirectory(_ name: String) -> Bool {
        projectDependencyDirectoryNames.contains(name.lowercased())
    }

    /// Path markers for polyglot package manager caches stored in dotfiles (Python/Ruby/Rust/Go/Java).
    /// These paths are NOT under ~/Library/Caches/ so they don't pass `isLowImpactPath` without help.
    /// Registered in `CleanupEngine.isPersonaPath` so findings from the Phase 6 cache rules can be cleaned.
    public static let developerPackageCacheMarkers: [String] = [
        "/.npm/_cacache",
        "/.npm/_npx",
        "/.cache/opencode",
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
        "/.bun/install/cache",
        "/.local/share/pnpm",
        "/library/pnpm",
        "/.local/share/opencode/",
        "/library/caches/homebrew",
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
        // Spotlight / Help / media-analysis indexes are never "low impact" to delete.
        if isSearchIndexSensitivePath(url) { return false }

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

    /// Simple directory names used by multi-platform native trees (Node prebuilds,
    /// JetBrains plugins, VS Code extension bins, etc.). Alone these can collide with
    /// source folders (e.g. `win32` type stubs), so callers should require a macOS
    /// sibling unless the root is a known native-only tree (JetBrains plugins).
    public static let nonMacPlatformDirectoryNames: Set<String> = [
        "win", "win32", "win64", "windows",
        "linux", "linux-x86_64", "linux-aarch64", "linux-arm64",
        "linux-x86", "linux_x64", "linux_aarch64", "linux_arm64",
    ]

    /// Directory names that hold macOS natives in multi-platform trees.
    public static let macPlatformDirectoryNames: Set<String> = [
        "darwin", "macos", "osx", "mac",
        "darwin-x64", "darwin-arm64", "darwin_x64", "darwin_arm64",
        "macos-x64", "macos-arm64", "osx-x64", "osx-arm64",
        "mac-x64", "mac-arm64",
    ]

    /// Home-relative roots that ship multi-platform natives where the *parent* tree
    /// is NOT fully reclaimable (installed editor extensions / IDE plugins).
    /// Fully reclaimable caches (npx, Yarn, pnpm, Bun) are owned by package-manager
    /// rules as whole folders — listing win32/ under them would double-count.
    public static let wrongPlatformScanRootRelativePaths: [String] = [
        ".vscode/extensions",
        ".cursor/extensions",
        ".windsurf/extensions",
        "Library/Application Support/Code/CachedExtensionVSIXs",
        "Library/Application Support/Cursor/CachedExtensionVSIXs",
        "Library/Application Support/JetBrains",
    ]

    /// Compound platform-arch directory names such as `win32-x64` / `linux-arm64`.
    /// These almost never collide with source folders and are safe to flag alone.
    public static func isCompoundNonMacPlatformDirectoryName(_ name: String) -> Bool {
        let n = name.lowercased()
        if macPlatformDirectoryNames.contains(n) { return false }
        if isMacPlatformDirectoryName(n) { return false }
        let prefixes = ["win32-", "win64-", "windows-", "win32_", "win64_", "windows_", "linux-", "linux_"]
        return prefixes.contains { n.hasPrefix($0) && n.count > $0.count }
    }

    public static func isMacPlatformDirectoryName(_ name: String) -> Bool {
        let n = name.lowercased()
        if macPlatformDirectoryNames.contains(n) { return true }
        return n.hasPrefix("darwin-") || n.hasPrefix("darwin_")
            || n.hasPrefix("macos-") || n.hasPrefix("macos_")
            || n.hasPrefix("osx-") || n.hasPrefix("osx_")
            || n.hasPrefix("mac-") || n.hasPrefix("mac_")
    }

    public static func isNonMacPlatformDirectoryName(_ name: String) -> Bool {
        let n = name.lowercased()
        return nonMacPlatformDirectoryNames.contains(n) || isCompoundNonMacPlatformDirectoryName(n)
    }

    /// `true` when any path component is a non-macOS platform native directory name.
    /// Used to avoid double-counting file findings under whole-folder wrong-platform hits.
    public static func isUnderWrongPlatformNativeDirectory(_ url: URL) -> Bool {
        url.pathComponents.contains { isNonMacPlatformDirectoryName($0) }
    }

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

    /// Downloads top-level wrong-platform files **or** paths inside non-macOS native
    /// platform directories (whole-folder reclaim). Age gates are skipped for both.
    public static func isWrongPlatformPath(_ url: URL) -> Bool {
        isWrongPlatformBinary(url) || isUnderWrongPlatformNativeDirectory(url)
    }
}
