import Foundation

/// Detects duplicate installations of the same app where an older version is still present
/// alongside a newer one. Groups apps by CFBundleIdentifier (or normalized display name as
/// fallback), then flags all but the highest-versioned copy as `.review` findings.
///
/// Scans `/Applications` and `~/Applications` at depth 1.
/// `/System/Applications` is never scanned.
public struct StaleAppVersionRule: ScanRule {
    public let id = "stale-app-version"
    public let title = "Duplicate App Versions"
    public let reason = "Older version of an app already installed in a newer version"
    public let category: ScanCategory = .applications
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.85

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    /// Directories scanned at depth 1 for `.app` bundles.
    public func scanDirectories(environment: ScanEnvironment) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            environment.homeDirectory.appending(path: "Applications")
        ]
    }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let fm = FileManager.default

        var appBundles: [URL] = []
        for dir in scanDirectories(environment: environment) {
            guard fm.fileExists(atPath: dir.path) else { continue }
            let contents = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in contents
                where url.pathExtension == "app"
                && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                appBundles.append(url.resolvingSymlinksInPath())
            }
        }

        let entries = appBundles.compactMap { AppEntry(url: $0) }

        var grouped: [String: [AppEntry]] = [:]
        for entry in entries {
            grouped[entry.groupKey, default: []].append(entry)
        }

        var findings: [ScanFinding] = []
        for (_, group) in grouped where group.count > 1 {
            guard Set(group.map { $0.version }).count > 1 else { continue }

            let sorted = group.sorted { lhs, rhs in
                let cmp = FileSystemUtils.compareVersionStrings(lhs.version, rhs.version)
                guard cmp == .orderedSame else { return cmp == .orderedDescending }
                let lAge = (try? lhs.url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]))
                    .flatMap(ScanPolicy.effectiveAgeDate(from:))
                let rAge = (try? rhs.url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]))
                    .flatMap(ScanPolicy.effectiveAgeDate(from:))
                switch (lAge, rAge) {
                case (.some(let l), .some(let r)): return l > r
                case (.some, .none): return true
                default: return false
                }
            }

            let newest = sorted[0]
            for older in sorted.dropFirst() {
                let res = try? older.url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                let modDate = res?.contentModificationDate
                let size = FileSystemUtils.directorySize(url: older.url)
                findings.append(ScanFinding(
                    category: category,
                    riskLevel: riskLevel,
                    reason: "\(reason) (\(older.displayName) \(older.version), superseded by \(newest.version))",
                    path: older.url.path,
                    sizeBytes: size,
                    lastUsed: modDate,
                    confidence: confidence
                ))
            }
        }

        return findings
    }
}

// MARK: - AppEntry

private struct AppEntry {
    let url: URL
    let groupKey: String
    let version: String
    let displayName: String

    init?(url: URL) {
        let plistURL = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        self.url = url
        self.version = (plist["CFBundleVersion"] as? String) ?? ""
        self.displayName = url.deletingPathExtension().lastPathComponent

        if let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty {
            self.groupKey = bundleID.lowercased()
        } else {
            self.groupKey = Self.normalizeName(url.deletingPathExtension().lastPathComponent)
        }
    }

    private static func normalizeName(_ name: String) -> String {
        var result = name
        // Strip trailing version like " 3" or " 2.1"
        if let range = result.range(of: #"\s+\d+(\.\d+)*$"#, options: .regularExpression) {
            result = String(result[..<range.lowerBound])
        }
        // Strip trailing "Beta", "Dev", "Alpha", "RC"
        for suffix in ["beta", "dev", "alpha", "rc"] {
            let pattern = #"(?i)\s+"# + suffix + "$"
            if let range = result.range(of: pattern, options: .regularExpression) {
                result = String(result[..<range.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
