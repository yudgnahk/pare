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

    public static func defaultMinimumAgeSeconds(for category: ScanCategory) -> TimeInterval? {
        switch category {
        case .userCaches, .temporaryFiles, .browserCaches, .developerPackageCaches, .developerSimulatorCaches:
            return defaultCacheMinAgeSeconds
        case .logsAndCrashReports, .developerBuildArtifacts:
            return nil
        }
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
