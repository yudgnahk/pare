import Foundation

/// Finds macOS installer files (.dmg, .pkg, .iso, .xip) in ~/Downloads and ~/Desktop
/// that are at least 7 days old. These are safe to remove after the app has been installed.
///
/// Risk is `.review` — installer files may be intentionally kept, so the user must confirm.
/// The 7-day age gate avoids flagging a freshly downloaded installer that hasn't been
/// opened yet.
public struct InstallerFileRule: ScanRule {
    public let id = "installer-files"
    public let title = "Installer Files"
    public let reason = "macOS installer — safe to remove after the app has been installed"
    public let category: ScanCategory = .installerFiles
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.80

    // 7 days — gives users time to install before the file is flagged.
    static let minimumAgeSeconds: TimeInterval = 7 * 24 * 60 * 60

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Downloads"),
            environment.homeDirectory.appending(path: "Desktop"),
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        guard ScanPolicy.installerExtensions.contains(ext) else { return false }
        // Bypass isLowImpactPath — installer files are intentionally in protected paths
        // (Downloads/Desktop). Safety is maintained by extension filtering + age gate + .review risk.
        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: Self.minimumAgeSeconds
        )
    }
}
