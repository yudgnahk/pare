import Foundation

/// Result of probing whether the process likely has Full Disk Access (FDA).
public enum FullDiskAccessStatus: String, Sendable, Equatable {
    /// At least one protected path exists and every existing probe path was listable.
    case granted
    /// At least one existing probe path returned a permission error.
    case denied
    /// No probe paths exist on this Mac (cannot decide).
    case unknown
}

/// Heuristic Full Disk Access detection for non-sandboxed macOS apps.
///
/// There is no public TCC API for FDA. Pare probes user-library paths that macOS
/// typically protects (Safari, Mail, Messages, TCC database, etc.). If listing
/// any **existing** probe path fails with a permission error, FDA is treated as denied.
public enum FullDiskAccessChecker {
    /// Relative paths under the user's home that usually require Full Disk Access.
    public static let defaultProbeRelativePaths: [String] = [
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Cookies",
        "Library/Calendars",
        "Library/Reminders",
        "Library/Application Support/MobileSync",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/Knowledge",
    ]

    /// Prefer modern Privacy & Security deep link; fall back to legacy System Preferences URL.
    public static var systemSettingsURLs: [URL] {
        [
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
        ].compactMap { $0 }
    }

    /// Evaluate FDA status using injectable filesystem callbacks (unit-testable).
    ///
    /// - Parameters:
    ///   - homeDirectory: User home root used to resolve probe paths.
    ///   - relativePaths: Paths relative to `homeDirectory`.
    ///   - fileExists: Whether a probe path exists.
    ///   - listDirectory: Attempt to list a directory; throw on denial/IO error.
    public static func status(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        relativePaths: [String] = defaultProbeRelativePaths,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        listDirectory: (URL) throws -> [String] = {
            try FileManager.default.contentsOfDirectory(atPath: $0.path)
        }
    ) -> FullDiskAccessStatus {
        var sawExisting = false
        var sawPermissionFailure = false
        var sawSuccess = false

        for relative in relativePaths {
            let url = homeDirectory.appending(path: relative)
            guard fileExists(url) else { continue }
            sawExisting = true
            do {
                _ = try listDirectory(url)
                sawSuccess = true
            } catch {
                if isPermissionError(error) {
                    sawPermissionFailure = true
                }
                // Non-permission errors (e.g. not a directory) do not prove missing FDA.
            }
        }

        if sawPermissionFailure {
            return .denied
        }
        if sawSuccess {
            return .granted
        }
        if !sawExisting {
            return .unknown
        }
        return .unknown
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain {
            return ns.code == Int(EACCES) || ns.code == Int(EPERM)
        }
        if ns.domain == NSCocoaErrorDomain {
            return ns.code == NSFileReadNoPermissionError
        }
        return false
    }
}

