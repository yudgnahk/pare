import Foundation

public struct TopFile: Sendable {
    public let path: String
    public let sizeBytes: Int64

    public init(path: String, sizeBytes: Int64) {
        self.path = path
        self.sizeBytes = sizeBytes
    }
}

public struct AppRollup: Sendable {
    public let app: String
    public let totalBytes: Int64
    public let fileCount: Int
    /// Top 10 files ≥ 1 MB, sorted largest-first.
    public let topFiles: [TopFile]

    public init(app: String, totalBytes: Int64, fileCount: Int, topFiles: [TopFile] = []) {
        self.app = app
        self.totalBytes = totalBytes
        self.fileCount = fileCount
        self.topFiles = topFiles
    }
}

public struct ScanReportAnnotator: Sendable {
    public init() {}

    public static func sourceApp(for finding: ScanFinding) -> String {
        sourceApp(forPath: finding.path)
    }

    /// Same attribution as the “Where space goes” chart — used to group category browser rows by tool.
    public static func sourceApp(forPath path: String) -> String {
        let path = path.lowercased()
        if path.contains("com.microsoft.vscode") || path.contains("/code/") || path.contains("/.vscode/")
            || path.contains("com.visualstudio.code") {
            return "VS Code"
        }
        if path.contains("jetbrains") || path.contains("intellij") || path.contains("datagrip")
            || path.contains("pycharm") || path.contains("webstorm") || path.contains("phpstorm")
            || path.contains("rubymine") || path.contains("androidstudio") || path.contains("goland")
            || path.contains("clion") || path.contains("rustrover") {
            return "JetBrains"
        }
        if path.contains("com.docker.docker") || path.contains("/docker/") {
            return "Docker"
        }
        if path.contains("xcode") || path.contains("coresimulator") || path.contains("deriveddata") {
            return "Xcode"
        }
        if path.contains("com.apple.safari") || path.contains("/safari/") {
            return "Safari"
        }
        if path.contains("google/chrome") || path.contains("chromium") || path.contains("google chrome") {
            return "Chrome"
        }
        if path.contains("bravesoftware") || path.contains("brave-browser") {
            return "Brave"
        }
        if path.contains("microsoft edge") || path.contains("com.microsoft.edgemac") {
            return "Edge"
        }
        if path.contains("firefox") {
            return "Firefox"
        }
        if path.contains("com.operasoftware.opera") || path.contains("/opera/") {
            return "Opera"
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
        // Package managers / language toolchains (match chart + Developer Package Caches).
        if path.contains("homebrew") || path.contains("/.npm/") || path.contains("/npm/")
            || path.contains("node_modules") || path.contains("/.cargo/") || path.contains("/.rustup/")
            || path.contains("/.gradle/") || path.contains("/.m2/") || path.contains("/.ivy2/")
            || path.contains("/pnpm/") || path.contains("cocoapods") || path.contains("swiftpm")
            || path.contains("org.swift.swiftpm") || path.contains("/go/pkg/") || path.contains("go-build")
            || path.contains("/.pyenv/") || path.contains("/.gem/") || path.contains("/.bundle/")
            || path.contains("/.rbenv/") || path.contains("/.cache/pip") || path.contains("/.cache/opencode")
            || path.contains("/yarn/") {
            return "Package Managers"
        }
        if path.contains("cursor") && (path.contains("cache") || path.contains("application support")) {
            return "Cursor"
        }
        if path.contains("opencode") {
            return "OpenCode"
        }
        if path.contains("/library/logs/") || path.contains("/diagnosticreports/") || path.contains("/crashreporter/") {
            return "System Logs"
        }
        if path.contains("/var/folders/") || path.contains("/caches/temporaryitems") || path.contains("/private/tmp/") {
            return "Temp Files"
        }
        if path.contains("slack") {
            return "Slack"
        }
        if path.contains("zoom") {
            return "Zoom"
        }
        if path.contains("spotify") {
            return "Spotify"
        }
        if path.contains("com.microsoft.teams") || path.contains("teams.microsoft") {
            return "Teams"
        }
        if path.contains("discord") {
            return "Discord"
        }
        if path.contains("telegram") {
            return "Telegram"
        }
        if path.contains("1password") || path.contains("agilebits") {
            return "1Password"
        }
        if path.contains("notion") {
            return "Notion"
        }
        if path.contains("arc") && (path.contains("the browser company") || path.contains("user data")) {
            return "Arc"
        }
        if path.contains("com.apple.mail") || path.contains("/mail/") {
            return "Mail"
        }
        if path.contains("com.apple.music") {
            return "Music"
        }
        if path.contains("com.apple.photos") {
            return "Photos"
        }
        if path.contains("com.apple.imovie") {
            return "iMovie"
        }
        // Fallback: extract the app name from a reverse-DNS bundle ID in cache paths
        // e.g. ~/Library/Caches/com.apple.Maps/ → "Maps"
        if let bundleApp = bundleAppName(from: path) {
            return bundleApp
        }
        return "Other"
    }

    /// Extracts a human-readable app name from a reverse-DNS bundle ID in a cache path.
    /// e.g. `~/Library/Caches/com.apple.Maps/file` → "Maps"
    private static func bundleAppName(from path: String) -> String? {
        guard let range = path.range(of: "/Caches/", options: .caseInsensitive) else { return nil }
        let afterCaches = path[range.upperBound...]
        let component: String
        if let slash = afterCaches.firstIndex(of: "/") {
            component = String(afterCaches[..<slash])
        } else {
            component = String(afterCaches)
        }
        // Must be a reverse-DNS bundle ID with at least two dots
        let parts = component.split(separator: ".")
        guard parts.count >= 3,
              let tld = parts.first,
              ["com", "io", "co", "us", "net", "org", "app", "ru", "tv"].contains(tld.lowercased())
        else { return nil }
        guard let last = parts.last, last.count > 2 else { return nil }
        let name = String(last)
        let genericComponents: Set<String> = ["app", "application", "helper", "agent", "daemon", "service", "framework", "plugin", "extension", "support"]
        guard !genericComponents.contains(name.lowercased()) else { return nil }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    public static func appRollups(from findings: [ScanFinding]) -> [AppRollup] {
        var grouped: [String: [ScanFinding]] = [:]
        for finding in findings {
            let app = sourceApp(for: finding)
            grouped[app, default: []].append(finding)
        }

        let minRollupBytes: Int64 = 1_048_576  // 1 MB to get its own row
        let minFileBytes: Int64 = 1_048_576    // 1 MB to appear in top-files list

        var result: [AppRollup] = []
        var otherFindings: [ScanFinding] = grouped["Other"] ?? []

        for (app, files) in grouped where app != "Other" {
            let total = files.reduce(0) { $0 + $1.sizeBytes }
            if total >= minRollupBytes {
                let topFiles = files
                    .filter { $0.sizeBytes >= minFileBytes }
                    .sorted { $0.sizeBytes > $1.sizeBytes }
                    .prefix(10)
                    .map { TopFile(path: $0.path, sizeBytes: $0.sizeBytes) }
                result.append(AppRollup(app: app, totalBytes: total, fileCount: files.count, topFiles: Array(topFiles)))
            } else {
                otherFindings.append(contentsOf: files)
            }
        }

        if !otherFindings.isEmpty {
            let otherTotal = otherFindings.reduce(0) { $0 + $1.sizeBytes }
            let otherTopFiles = otherFindings
                .filter { $0.sizeBytes >= minFileBytes }
                .sorted { $0.sizeBytes > $1.sizeBytes }
                .prefix(10)
                .map { TopFile(path: $0.path, sizeBytes: $0.sizeBytes) }
            result.append(AppRollup(app: "Other", totalBytes: otherTotal, fileCount: otherFindings.count, topFiles: Array(otherTopFiles)))
        }

        return result.sorted { $0.totalBytes > $1.totalBytes }
    }
}
