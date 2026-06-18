import Foundation

public enum ScanPolicy {
    public static let largeFileThresholdBytes: Int64 = 50 * 1024 * 1024
    public static let defaultCacheMinAgeSeconds: TimeInterval = 3 * 24 * 60 * 60

    private static let lowImpactMarkers = [
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
        "gpucache"
    ]

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
        "/library/logs/jetbrains"
    ]

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

    private static let personaProtectedPathOverrides = [
        "/library/application support/adobe/common/media cache",
        "/library/application support/adobe/common/peak files",
        "/library/application support/figma/cache",
        "/library/application support/figma/desktop/cache",
        "/library/application support/blackmagic design/davinci resolve/cache",
        "/library/application support/code/cachedextensionvsixs",
        "/library/application support/code/user/workspacestorage",
        "/library/application support/code/user/history",
        "/library/application support/jetbrains",
        "/library/containers/com.docker.docker/data/log"
    ]

    public static func defaultMinimumAgeSeconds(for category: ScanCategory) -> TimeInterval? {
        switch category {
        case .userCaches, .temporaryFiles, .browserCaches, .developerPackageCaches, .developerSimulatorCaches, .designerCaches, .videoBuilderCaches:
            return defaultCacheMinAgeSeconds
        case .logsAndCrashReports:
            return 24 * 60 * 60
        case .developerBuildArtifacts:
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

    public static func passesMinimumAge(for resourceValues: URLResourceValues, minimumAgeSeconds: TimeInterval?) -> Bool {
        guard let minimumAgeSeconds else {
            return true
        }
        guard let modified = resourceValues.contentModificationDate else {
            return true
        }
        return Date().timeIntervalSince(modified) >= minimumAgeSeconds
    }

    public static func isLargeFile(_ bytes: Int64) -> Bool {
        bytes > largeFileThresholdBytes
    }
}
