import Foundation

// MARK: - Marker / name data (R1.7 split — data only, predicates live in +Safety)

extension ScanPolicy {

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

    /// Rule-ownership policy: top-level `~/Library/Caches` folder names (lowercased)
    /// that are owned by other scan rules and must not be double-reported by
    /// `UserCachesRule`. Includes never-clean search-index stores.
    public static let userCachesExcludedTopLevelFolderNames: Set<String> = Set([
        "google",                       // Chrome — BrowserCachesRule
        "com.apple.safari",             // BrowserCachesRule
        "firefox",                      // BrowserCachesRule
        "bravesoftware",                // BrowserCachesRule
        "microsoft edge",               // BrowserCachesRule
        "com.operasoftware.opera",      // BrowserCachesRule
        "yarn",                         // PackageManagerCachesRule
        "pnpm",                         // PackageManagerCachesRule
        "cocoapods",                    // PackageManagerCachesRule
        "org.swift.swiftpm",            // PackageManagerCachesRule
        "homebrew",                     // HomebrewCacheRule
        "go-build",                     // GoCachesRule
        "com.microsoft.vscode.shipit",  // VSCodeCachesRule
        "pip",                          // PythonCachesRule
        "pypoetry",                     // PythonCachesRule
        "uv",                           // Python tooling (report-only elsewhere)
        "com.github.copilot-for-xcode", // AIToolCachesRule
        "temporaryitems",               // TemporaryFilesRule
    ]).union(searchIndexSensitiveCacheFolderNames)

    // AI dotfile markers (e.g. "/.continue/cache", "/.tabnine") are appended from app-catalog.json
    // at first access — add new AI tools to the catalog, not here.
    static let lowImpactMarkers: [String] = {
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

    static let protectedPathMarkers = [
        "/documents/",
        "/desktop/",
        "/downloads/",
        "/library/application support/",
        "/library/containers/",
        "/library/group containers/",
        "/.git/"
    ]

    static let sensitiveDataMarkers = [
        "bookmarks",
        "history",
        "login",
        "session",
        "cookies",
        "keychain"
    ]

    /// VS Code review-required state locations (workspace storage / local history).
    public static let vscodeReviewStateMarkers = [
        "/library/application support/code/user/workspacestorage",
        "/library/application support/code/user/history",
    ]

    /// JetBrains review-required (IDE marker, subtree marker) pairs — plugin and
    /// JDBC-driver data that needs user review before removal.
    public static let jetBrainsReviewRequiredMarkerPairs: [(ide: String, subtree: String)] = [
        (ide: "/goland", subtree: "/plugins/"),
        (ide: "/datagrip", subtree: "/plugins/"),
        (ide: "/datagrip", subtree: "/jdbc-drivers/"),
    ]

    /// Path components that disqualify a Spotlight hit from being a project root
    /// (system/library trees, dependency dirs, Trash).
    public static let projectDiscoveryExcludedPathComponents = [
        "/Library/", "/System/", "/node_modules/", "/vendor/",
        "/venv/", "/.venv/", "/.Trash/", "/site-packages/",
        "/.Trash", "/Applications/"
    ]

    /// App-specific state paths that must never be deleted — removing them would
    /// break credentials, active sessions, or IDE state for the matching tool.
    static let appStateSensitiveMarkers = [
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

    /// Marker files/directories whose presence identifies a directory as a project root.
    /// Mirrors the Spotlight signal names used by `ProjectRootDiscovery`.
    public static let projectRootMarkerFileNames: [String] = [
        ".git", "package.json", "Package.swift", "Cargo.toml", "go.mod",
        "pyproject.toml", "setup.py", "Gemfile", "pom.xml", "build.gradle",
        "build.gradle.kts",
    ]

    /// How many ancestor directories to inspect for project-root evidence.
    static let projectRootEvidenceMaxAncestors = 8

    public static let developerReviewExclusionMarkers = [
        "/options/",
        "/workspace.xml",
        "/workspace/storage",
        "/projects/",
        "/projectsettings/",
        "/.idea/"
    ]

    // AI Application Support cache paths are appended from app-catalog.json at first access.
    static let personaProtectedPathOverrides: [String] = {
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
}
