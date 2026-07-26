import Foundation

/// Detects old iPhone/iPad backups stored locally by Finder (or iTunes).
///
/// Scans `~/Library/Application Support/MobileSync/Backup/` and reads each
/// backup's `Info.plist` for device name, iOS version, serial number, and
/// backup date.
///
/// Findings logic:
///   - Group by serial number (same device).
///   - Most-recent backup per device is never flagged.
///   - Any older backup > 30 days → `.review`.
///   - Single backup > 180 days → `.review` with advisory reason.
public struct MobileSyncBackupsRule: ScanRule {
    public let id = "mobile-sync-backups"
    public let title = "iOS / iPadOS Device Backups"
    public let reason = "Old or stale device backup taking significant disk space"
    public let category: ScanCategory = .deviceBackups
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.90

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let backupRoot = environment.homeDirectory.appending(path: "Library/Application Support/MobileSync/Backup")
        guard FileManager.default.fileExists(atPath: backupRoot.path) else { return [] }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let dirs = contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard !dirs.isEmpty else { return [] }

        var entries: [BackupEntry] = []
        for dir in dirs {
            if let entry = BackupEntry(url: dir) {
                entries.append(entry)
            } else {
                // Fallback: use directory name as identifier
                let dirSize = FileSystemUtils.directorySize(url: dir)
                let res = try? dir.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                let age = res.flatMap(ScanPolicy.effectiveAgeDate(from:))
                entries.append(BackupEntry(
                    url: dir,
                    deviceName: dir.lastPathComponent,
                    iosVersion: "Unknown",
                    serialNumber: dir.lastPathComponent,
                    backupDate: age,
                    sizeBytes: dirSize
                ))
            }
        }

        // Group by serial number
        var grouped: [String: [BackupEntry]] = [:]
        for entry in entries {
            grouped[entry.serialNumber, default: []].append(entry)
        }

        // Thresholds live in ScanPolicy (R1.5).
        let staleSiblingAge = ScanPolicy.deviceBackupStaleAgeSeconds
        let staleSingleAge = ScanPolicy.deviceBackupSingleStaleAgeSeconds
        var findings: [ScanFinding] = []

        for (_, group) in grouped {
            // Skip devices with no dated backup at all — age is unknowable.
            guard group.contains(where: { $0.backupDate != nil }) else { continue }

            let sorted = group.sorted { lhs, rhs in
                let lDate = lhs.backupDate ?? .distantPast
                let rDate = rhs.backupDate ?? .distantPast
                return lDate > rDate
            }

            if sorted.count == 1, let single = sorted.first {
                // Single backup — flag only if > 180 days old
                if let date = single.backupDate,
                   Date().timeIntervalSince(date) >= staleSingleAge {
                    let ageStr = Self.formatAge(from: date)
                    findings.append(ScanFinding(
                        category: category,
                        riskLevel: riskLevel,
                        reason: "Only backup is \(ageStr) old — consider making a fresh backup before deleting. Device: \(single.deviceName) (\(single.iosVersion))",
                        path: single.url.path,
                        sizeBytes: single.sizeBytes,
                        lastUsed: single.backupDate,
                        confidence: confidence
                    ))
                }
                continue
            }

            // Multiple backups — flag all except the most recent
            for entry in sorted.dropFirst() {
                guard let date = entry.backupDate,
                      Date().timeIntervalSince(date) >= staleSiblingAge else { continue }
                let dateStr = Self.formatDate(date)
                findings.append(ScanFinding(
                    category: category,
                    riskLevel: riskLevel,
                    reason: "\(entry.deviceName) (\(entry.iosVersion)) — backup from \(dateStr)",
                    path: entry.url.path,
                    sizeBytes: entry.sizeBytes,
                    lastUsed: entry.backupDate,
                    confidence: confidence
                ))
            }
        }

        return findings.isEmpty ? nil : findings
    }

    // MARK: - Helpers

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func formatAge(from date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / (24 * 60 * 60))
        if days > 365 {
            return "\(days / 365)y \(days % 365)d"
        }
        return "\(days)d"
    }
}

// MARK: - BackupEntry

private struct BackupEntry {
    let url: URL
    let deviceName: String
    let iosVersion: String
    let serialNumber: String
    let backupDate: Date?
    let sizeBytes: Int64

    init(url: URL, deviceName: String, iosVersion: String, serialNumber: String, backupDate: Date?, sizeBytes: Int64) {
        self.url = url
        self.deviceName = deviceName
        self.iosVersion = iosVersion
        self.serialNumber = serialNumber
        self.backupDate = backupDate
        self.sizeBytes = sizeBytes
    }

    init?(url: URL) {
        let plistURL = url.appending(path: "Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        self.url = url
        self.deviceName = plist["Display Name"] as? String ?? url.lastPathComponent
        self.iosVersion = plist["Product Version"] as? String ?? "Unknown"
        self.serialNumber = plist["Serial Number"] as? String ?? url.lastPathComponent

        if let backupDate = plist["Last Backup Date"] as? Date {
            self.backupDate = backupDate
        } else {
            let res = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            self.backupDate = res.flatMap(ScanPolicy.effectiveAgeDate(from:))
        }

        self.sizeBytes = FileSystemUtils.directorySize(url: url)
    }
}
