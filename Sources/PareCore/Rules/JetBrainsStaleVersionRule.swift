import Foundation

/// Detects Application Support data for superseded JetBrains IDE versions.
///
/// When multiple version-stamped folders exist for the same product (e.g. GoLand2024.3
/// alongside GoLand2025.1), every folder except the newest is a candidate for removal.
/// JetBrains migrates settings to the new version on first launch, so old version folders
/// are inert after migration. A 90-day age gate prevents false-positives during the
/// transition period immediately after an IDE upgrade.
///
/// This rule uses `customScan` because it needs to compare sibling directories to
/// determine which version is newest — the standard per-file `include` hook cannot
/// express that relationship.
public struct JetBrainsStaleVersionRule: ScanRule {
    public let id = "jetbrains-stale-version"
    public let title = "JetBrains Stale IDE Version Data"
    public let reason = "Application Support data for a superseded JetBrains IDE version"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.88

    private static let minimumAgeSeconds: TimeInterval = 90 * 24 * 60 * 60

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let jetbrainsDir = environment.homeDirectory
            .appending(path: "Library/Application Support/JetBrains")
        let fm = FileManager.default

        guard fm.fileExists(atPath: jetbrainsDir.path) else { return [] }

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: jetbrainsDir,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var parsed: [VersionedDir] = []
        var unversionedByProduct: [String: URL] = [:]

        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let entry = parseVersionedDir(url: url) {
                parsed.append(entry)
            } else if let product = parseUnversionedProductDir(url: url) {
                // e.g. "Datagrip" next to "DataGrip2026.1"
                unversionedByProduct[product.lowercased()] = url
            }
        }

        // Group by product name (case-insensitive).
        var grouped: [String: [VersionedDir]] = [:]
        for entry in parsed {
            grouped[entry.product.lowercased(), default: []].append(entry)
        }

        var findings: [ScanFinding] = []
        for (_, versions) in grouped where versions.count > 1 {
            let sorted = versions.sorted { lhs, rhs in
                FileSystemUtils.compareVersionStrings(
                    "\(lhs.year).\(lhs.minor)",
                    "\(rhs.year).\(rhs.minor)"
                ) == .orderedDescending
            }
            // sorted[0] is the newest — flag everything else.
            for older in sorted.dropFirst() {
                if let finding = makeStaleFinding(older: older, newest: sorted[0]) {
                    findings.append(finding)
                }
            }
        }

        // Unversioned product folder + at least one versioned peer → treat unversioned as stale.
        for (productKey, unversionedURL) in unversionedByProduct {
            guard let versions = grouped[productKey], let newest = versions.max(by: { lhs, rhs in
                FileSystemUtils.compareVersionStrings(
                    "\(lhs.year).\(lhs.minor)",
                    "\(rhs.year).\(rhs.minor)"
                ) == .orderedAscending
            }) else { continue }

            let res = try? unversionedURL.resourceValues(forKeys: [
                .contentModificationDateKey, .creationDateKey, .isDirectoryKey
            ])
            if let d = res.flatMap(ScanPolicy.effectiveAgeDate(from:)) {
                guard Date().timeIntervalSince(d) >= Self.minimumAgeSeconds else { continue }
            }
            let size = FileSystemUtils.directorySize(url: unversionedURL)
            guard size > 0 else { continue }
            findings.append(ScanFinding(
                category: category,
                riskLevel: riskLevel,
                reason: "\(reason) (unversioned \(newest.product) folder, superseded by \(newest.year).\(newest.minor))",
                path: unversionedURL.path,
                sizeBytes: size,
                lastUsed: res?.contentModificationDate,
                confidence: confidence
            ))
        }

        return findings
    }

    // MARK: - Helpers

    private struct VersionedDir {
        let url: URL
        let product: String
        let year: Int
        let minor: Int
    }

    private func makeStaleFinding(older: VersionedDir, newest: VersionedDir) -> ScanFinding? {
        let res = try? older.url.resourceValues(forKeys: [
            .contentModificationDateKey, .creationDateKey, .isDirectoryKey
        ])
        let modDate = res?.contentModificationDate
        if let d = res.flatMap(ScanPolicy.effectiveAgeDate(from:)) {
            guard Date().timeIntervalSince(d) >= Self.minimumAgeSeconds else { return nil }
        }
        let size = FileSystemUtils.directorySize(url: older.url)
        return ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "\(reason) (\(older.product) \(older.year).\(older.minor), superseded by \(newest.year).\(newest.minor))",
            path: older.url.path,
            sizeBytes: size,
            lastUsed: modDate,
            confidence: confidence
        )
    }

    private func parseVersionedDir(url: URL) -> VersionedDir? {
        let name = url.lastPathComponent
        // Find the index where the numeric version starts (e.g. "GoLand2025.1" → split at "2").
        guard let firstDigitIdx = name.firstIndex(where: { $0.isNumber }) else { return nil }
        guard firstDigitIdx != name.startIndex else { return nil }

        let product = String(name[name.startIndex ..< firstDigitIdx])
        let versionStr = String(name[firstDigitIdx...])

        let parts = versionStr.split(separator: ".")
        guard parts.count >= 2,
              let year = Int(parts[0]), year >= 2000, year <= 2100,
              let minor = Int(parts[1]) else { return nil }

        return VersionedDir(url: url, product: product, year: year, minor: minor)
    }

    /// Unversioned product folders: "Datagrip", "Goland", "IntelliJIdea" (no year).
    private func parseUnversionedProductDir(url: URL) -> String? {
        let name = url.lastPathComponent
        guard name.firstIndex(where: { $0.isNumber }) == nil else { return nil }
        // Skip non-product noise folders.
        let skip: Set<String> = [
            "bl", "crl", "consentoptions", "daemon", "privacypolicy", "acp-agents"
        ]
        if skip.contains(name.lowercased()) { return nil }
        guard name.count >= 3 else { return nil }
        return name
    }

}
