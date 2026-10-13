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
    public static func sourceApp(for finding: ScanFinding) -> String {
        sourceApp(forPath: finding.path)
    }

    /// Same attribution as the “Where space goes” chart — used to group category browser rows by tool.
    public static func sourceApp(forPath path: String) -> String {
        let path = path.lowercased()
        let m = PathMatcher(path)
        if m.has("com.microsoft.vscode") || m.has("/code/") || m.has("/.vscode/")
            || m.has("com.visualstudio.code") {
            return "VS Code"
        }
        if m.has("jetbrains") || m.has("intellij") || m.has("datagrip")
            || m.has("pycharm") || m.has("webstorm") || m.has("phpstorm")
            || m.has("rubymine") || m.has("androidstudio") || m.has("goland")
            || m.has("clion") || m.has("rustrover") {
            return "JetBrains"
        }
        if m.has("com.docker.docker") || m.has("/docker/") {
            return "Docker"
        }
        if m.has("xcode") || m.has("coresimulator") || m.has("deriveddata") {
            return "Xcode"
        }
        if m.has("com.apple.safari") || m.has("/safari/") {
            return "Safari"
        }
        if m.has("google/chrome") || m.has("chromium") || m.has("google chrome") {
            return "Chrome"
        }
        if m.has("bravesoftware") || m.has("brave-browser") {
            return "Brave"
        }
        if m.has("microsoft edge") || m.has("com.microsoft.edgemac") {
            return "Edge"
        }
        if m.has("firefox") {
            return "Firefox"
        }
        if m.has("com.operasoftware.opera") || m.has("/opera/") {
            return "Opera"
        }
        if m.has("com.adobe") || m.has("/adobe/") {
            return "Adobe"
        }
        if m.has("com.figma") || m.has("/figma/") {
            return "Figma"
        }
        if m.has("com.blackmagicdesign") || m.has("davinci resolve") {
            return "DaVinci Resolve"
        }
        if m.has("finalcut") || m.has("final cut pro") {
            return "Final Cut Pro"
        }
        // Package managers / language toolchains (match chart + Developer Package Caches).
        if m.has("homebrew") || m.has("/.npm/") || m.has("/npm/")
            || m.has("node_modules") || m.has("/.cargo/") || m.has("/.rustup/")
            || m.has("/.gradle/") || m.has("/.m2/") || m.has("/.ivy2/")
            || m.has("/pnpm/") || m.has("cocoapods") || m.has("swiftpm")
            || m.has("org.swift.swiftpm") || m.has("/go/pkg/") || m.has("go-build")
            || m.has("/.pyenv/") || m.has("/.gem/") || m.has("/.bundle/")
            || m.has("/.rbenv/") || m.has("/.cache/pip") || m.has("/.cache/opencode")
            || m.has("/yarn/") {
            return "Package Managers"
        }
        if m.has("cursor") && (m.has("cache") || m.has("application support")) {
            return "Cursor"
        }
        if m.has("opencode") {
            return "OpenCode"
        }
        if m.has("/library/logs/") || m.has("/diagnosticreports/") || m.has("/crashreporter/") {
            return "System Logs"
        }
        if m.has("/var/folders/") || m.has("/caches/temporaryitems") || m.has("/private/tmp/") {
            return "Temp Files"
        }
        if m.has("slack") {
            return "Slack"
        }
        if m.has("zoom") {
            return "Zoom"
        }
        if m.has("spotify") {
            return "Spotify"
        }
        if m.has("com.microsoft.teams") || m.has("teams.microsoft") {
            return "Teams"
        }
        if m.has("discord") {
            return "Discord"
        }
        if m.has("telegram") {
            return "Telegram"
        }
        if m.has("1password") || m.has("agilebits") {
            return "1Password"
        }
        if m.has("notion") {
            return "Notion"
        }
        if m.has("arc") && (m.has("the browser company") || m.has("user data")) {
            return "Arc"
        }
        if m.has("com.apple.mail") || m.has("/mail/") {
            return "Mail"
        }
        if m.has("com.apple.music") {
            return "Music"
        }
        if m.has("com.apple.photos") {
            return "Photos"
        }
        if m.has("com.apple.imovie") {
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
