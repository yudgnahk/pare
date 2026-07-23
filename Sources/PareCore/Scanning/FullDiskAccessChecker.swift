import Foundation

/// Result of probing whether the process likely has Full Disk Access (FDA).
public enum FullDiskAccessStatus: String, Sendable, Equatable {
    /// At least one probe path was listable and no probe returned a permission error.
    case granted
    /// At least one probe path returned a permission error.
    case denied
    /// No probe paths exist on this Mac, or only non-permission failures occurred (cannot decide).
    case unknown
}

/// Heuristic Full Disk Access detection for non-sandboxed macOS apps.
///
/// There is no public TCC API for FDA. Pare probes user-library paths that macOS
/// typically protects (Safari, Mail, Messages, TCC database, etc.). If listing
/// any probe path fails with a permission error, FDA is treated as denied.
///
/// Probes always attempt `listDirectory` first (no hard `fileExists` gate), so
/// TCC that masks protected trees as missing still surfaces as permission errors
/// when the list call fails with EPERM/EACCES rather than not-found.
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
    ///   - fileExists: Soft existence check used only when list fails with a non-permission error.
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
            // Always attempt list first — TCC may hide existence without FDA.
            do {
                _ = try listDirectory(url)
                sawExisting = true
                sawSuccess = true
            } catch {
                if isPermissionError(error) {
                    sawExisting = true
                    sawPermissionFailure = true
                } else if isNotFoundError(error) {
                    // Path genuinely absent — skip.
                    continue
                } else if fileExists(url) {
                    // Exists but non-permission failure (e.g. not a directory).
                    sawExisting = true
                }
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

    /// Permission denials at the top level or nested under `NSUnderlyingErrorKey`.
    static func isPermissionError(_ error: Error) -> Bool {
        isPermissionError(error, depth: 0)
    }

    private static func isPermissionError(_ error: Error, depth: Int) -> Bool {
        // Bound recursion against pathological underlying-error cycles.
        guard depth < 8 else { return false }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain {
            if ns.code == Int(EACCES) || ns.code == Int(EPERM) {
                return true
            }
        }
        if ns.domain == NSCocoaErrorDomain {
            if ns.code == NSFileReadNoPermissionError {
                return true
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionError(underlying, depth: depth + 1)
        }
        return false
    }

    /// True when the error indicates the path does not exist.
    static func isNotFoundError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOENT) {
            return true
        }
        if ns.domain == NSCocoaErrorDomain {
            return ns.code == NSFileNoSuchFileError || ns.code == NSFileReadNoSuchFileError
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return isNotFoundError(underlying)
        }
        return false
    }
}
