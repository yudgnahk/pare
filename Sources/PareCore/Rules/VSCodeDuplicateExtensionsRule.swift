import Foundation

/// Detects older/duplicate versions of the same VS Code extension installed side-by-side
/// under `~/.vscode/extensions/`.  VS Code names extension directories as
/// `<publisher>.<name>-<semver>` (e.g. `ms-python.python-2024.2.1`).  When two or more
/// directories share the same publisher+name, every version except the newest is reclaimable.
///
/// This rule uses `customScan` because it must compare sibling directories against each
/// other — the standard per-file `include` hook can't express that relationship.
public struct VSCodeDuplicateExtensionsRule: ScanRule {
    public let id = "vscode-duplicate-extensions"
    public let title = "VS Code Duplicate Extension Versions"
    public let reason = "Older version of VS Code extension superseded by a newer install"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.92

    public init() {}

    // targetDirectories / include are unused — customScan drives everything.
    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let extensionsDir = environment.homeDirectory.appending(path: ".vscode/extensions")
        let fm = FileManager.default

        guard fm.fileExists(atPath: extensionsDir.path) else {
            return []
        }

        // Enumerate immediate subdirectories only.
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: extensionsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        let extDirs = contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        // Parse each directory name into (extensionID, version).
        // Format: <publisher>.<name>-<semver>
        // We split on the last occurrence of "-" that is followed by a digit (semver start).
        var parsed: [ExtDir] = []
        for dir in extDirs {
            let name = dir.lastPathComponent
            guard let extDir = parseExtensionDir(name: name, url: dir) else { continue }
            parsed.append(extDir)
        }

        // Group by extensionID.
        var grouped: [String: [ExtDir]] = [:]
        for ext in parsed {
            grouped[ext.extensionID, default: []].append(ext)
        }

        // For each group with duplicates, keep the newest, flag the rest.
        var findings: [ScanFinding] = []
        for (_, versions) in grouped where versions.count > 1 {
            let sorted = versions.sorted { compareVersion($0.version, $1.version) == .orderedDescending }
            // sorted[0] is the newest — skip it, flag the rest.
            for older in sorted.dropFirst() {
                let size = environment.sizeIndex.directorySize(url: older.url)
                let lastModified = (try? older.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

                // Honour minimum age — don't flag dirs modified within 3 days.
                if let mod = lastModified {
                    let age = Date().timeIntervalSince(mod)
                    if age < ScanPolicy.defaultCacheMinAgeSeconds { continue }
                }

                findings.append(
                    ScanFinding(
                        category: category,
                        riskLevel: riskLevel,
                        reason: "\(reason) (installed: \(older.versionString), newer: \(sorted[0].versionString))",
                        path: older.url.path,
                        sizeBytes: size,
                        lastUsed: lastModified,
                        confidence: confidence
                    )
                )
            }
        }

        return findings
    }

    // MARK: - Helpers

    private struct ExtDir {
        let url: URL
        let extensionID: String
        let version: [Int]
        let versionString: String
    }

    private func parseExtensionDir(name: String, url: URL) -> ExtDir? {
        // Find the last "-" that separates name from semver (digit-led component).
        // e.g. "ms-python.python-2024.2.1" → id="ms-python.python", ver="2024.2.1"
        var lastDashIdx: String.Index? = nil
        var idx = name.startIndex
        while idx < name.endIndex {
            if name[idx] == "-" {
                let next = name.index(after: idx)
                if next < name.endIndex, name[next].isNumber {
                    lastDashIdx = idx
                }
            }
            idx = name.index(after: idx)
        }
        guard let dashIdx = lastDashIdx else { return nil }

        let extID = String(name[name.startIndex ..< dashIdx])
        let verStr = String(name[name.index(after: dashIdx)...])
        guard !extID.isEmpty, !verStr.isEmpty else { return nil }

        // Parse semver components (major.minor.patch, ignoring pre-release suffixes).
        let components = verStr.split(separator: ".").prefix(3).compactMap { part -> Int? in
            Int(part.prefix(while: { $0.isNumber }))
        }
        guard !components.isEmpty else { return nil }

        return ExtDir(url: url, extensionID: extID, version: Array(components), versionString: verStr)
    }

    private func compareVersion(_ a: [Int], _ b: [Int]) -> ComparisonResult {
        let maxLen = max(a.count, b.count)
        for i in 0 ..< maxLen {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }

}
