import Foundation

public struct AppRollup: Sendable {
    public let app: String
    public let totalBytes: Int64
    public let fileCount: Int

    public init(app: String, totalBytes: Int64, fileCount: Int) {
        self.app = app
        self.totalBytes = totalBytes
        self.fileCount = fileCount
    }
}

public struct ScanReportAnnotator: Sendable {
    public init() {}

    public static func sourceApp(for finding: ScanFinding) -> String {
        let path = finding.path.lowercased()
        if path.contains("com.microsoft.vscode") || path.contains("/code/") || path.contains("/.vscode/") {
            return "VS Code"
        }
        if path.contains("jetbrains") {
            return "JetBrains"
        }
        if path.contains("com.docker.docker") || path.contains("/docker/") {
            return "Docker"
        }
        if path.contains("xcode") || path.contains("coresimulator") {
            return "Xcode"
        }
        if path.contains("com.apple.safari") || path.contains("/safari/") {
            return "Safari"
        }
        if path.contains("google/chrome") || path.contains("chromium") {
            return "Chrome"
        }
        if path.contains("firefox") {
            return "Firefox"
        }
        if path.contains("com.adobe") || path.contains("/adobe/") {
            return "Adobe"
        }
        if path.contains("com.figma") || path.contains("/figma/") {
            return "Figma"
        }
        if path.contains("com.blackmagicdesign") || path.contains("davinci resolve") {
            return "DaVinci Resolve"
        }
        if path.contains("finalcut") || path.contains("final cut pro") {
            return "Final Cut Pro"
        }
        if path.contains("homebrew") || path.contains("/npm/") || path.contains("node_modules") || path.contains("/.cargo/") || path.contains("/.gradle/") {
            return "Package Managers"
        }
        return "Other"
    }

    public static func appRollups(from findings: [ScanFinding]) -> [AppRollup] {
        var grouped: [String: (bytes: Int64, count: Int)] = [:]
        for finding in findings {
            let app = sourceApp(for: finding)
            let current = grouped[app] ?? (0, 0)
            grouped[app] = (bytes: current.bytes + finding.sizeBytes, count: current.count + 1)
        }
        return grouped
            .map { app, value in AppRollup(app: app, totalBytes: value.bytes, fileCount: value.count) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }
}
