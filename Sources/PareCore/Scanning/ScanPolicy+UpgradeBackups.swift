import Foundation

// MARK: - Upgrade / migration backups

extension ScanPolicy {

    /// Backups younger than this may still be the user's rollback plan.
    public static let upgradeBackupMinAgeSeconds: TimeInterval = 30 * 24 * 60 * 60

    /// Whole name tokens marking a backup; any token starting with `migrat` also counts.
    static let upgradeBackupNameTokens: Set<String> = ["backup", "backups", "bak", "upgrade", "upgrades", "schema"]

    /// Finder bookkeeping files that say nothing about whether the app is still writing.
    static let upgradeBackupIgnoredSiblingNames: Set<String> = [".DS_Store", ".localized", "Icon\r"]

    /// Dot directories holding credentials or repositories, whose backups are never offered.
    public static let upgradeBackupExcludedDotDirectories: Set<String> = [
        ".ssh", ".gnupg", ".aws", ".kube", ".docker", ".password-store", ".git", ".trash",
    ]

    /// `Application Support` folders that hold user data or device backups (plus every `com.apple.*`).
    public static let upgradeBackupExcludedApplicationSupportFolders: Set<String> = [
        "MobileSync", "AddressBook", "CallHistoryDB", "CallHistoryTransactions", "Knowledge",
        "FileProvider", "CloudDocs", "iCloud",
    ]

    private static let upgradeBackupVersionOrTimestamp: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<![0-9])[0-9]+\.[0-9]+(\.[0-9]+)?|[0-9]{4}-[0-9]{2}-[0-9]{2}|(?<![0-9])([0-9]{8}|[0-9]{10}|[0-9]{13}|[0-9]{14})(?![0-9])"#
    )

    /// A backup token (whole token, so `backupper` does not count) plus a version or timestamp.
    public static func hasUpgradeBackupSignal(_ name: String) -> Bool {
        let tokens = nameTokens(name)
        guard tokens.contains(where: isUpgradeBackupToken) else { return false }
        let range = NSRange(name.startIndex..., in: name)
        return upgradeBackupVersionOrTimestamp?.firstMatch(in: name, range: range) != nil
    }

    /// The store a backup belongs to: its name without backup tokens and numbers.
    public static func upgradeBackupStoreKey(_ name: String) -> String {
        nameTokens(name)
            .filter { !isUpgradeBackupToken($0) && !$0.allSatisfy(\.isNumber) }
            .joined(separator: ".")
    }

    /// Inside a dot directory sitting directly in a home folder, or `Library/Application Support/<app>/`,
    /// and clear of every protected, credential, user-data, iCloud Drive and search-index location.
    public static func isUpgradeBackupLocation(_ url: URL) -> Bool {
        if isSearchIndexSensitivePath(url) || isDockerNeverDeletePath(url) { return false }
        let lower = url.path.lowercased()
        if sensitiveDataMarkers.contains(where: { lower.contains($0) })
            || appStateSensitiveMarkers.contains(where: { lower.contains($0) })
            || protectedPathMarkers.contains(where: { $0 != "/library/application support/" && lower.contains($0) }) {
            return false
        }
        let parents = Array(url.standardizedFileURL.pathComponents.dropLast())
        if parents.contains("Mobile Documents") { return false }
        if let index = parents.indices.dropFirst().first(where: { parents[$0] == "Application Support" && parents[$0 - 1] == "Library" }) {
            guard index + 1 < parents.count else { return false }
            let app = parents[index + 1]
            return !app.lowercased().hasPrefix("com.apple.") && !upgradeBackupExcludedApplicationSupportFolders.contains(app)
        }
        let dotDirectories = parents.filter { $0.hasPrefix(".") && $0 != "." && $0 != ".." }
        guard !dotDirectories.contains(where: { upgradeBackupExcludedDotDirectories.contains($0.lowercased()) }) else {
            return false
        }
        // A dot directory counts only directly in a home folder (one holding `Library`), not any `.x` anywhere.
        return parents.indices.contains { index in
            let name = parents[index]
            guard index > 0, name.hasPrefix("."), name != ".", name != ".." else { return false }
            let home = NSString.path(withComponents: Array(parents[..<index]))
            return FileManager.default.fileExists(atPath: home + "/Library")
        }
    }

    /// Scan- and cleanup-time gate: backup name, allowed location, older than the age gate, a live
    /// sibling written after it, and a newer backup of the same store (the newest is always kept).
    public static func isReclaimableUpgradeBackup(_ url: URL, now: Date = Date()) -> Bool {
        let name = url.lastPathComponent
        guard hasUpgradeBackupSignal(name), isUpgradeBackupLocation(url),
              let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey, .creationDateKey]),
              values.isSymbolicLink != true,
              let ageDate = effectiveAgeDate(from: values),
              now.timeIntervalSince(ageDate) >= upgradeBackupMinAgeSeconds,
              let backupWritten = [values.contentModificationDate, values.creationDate].compactMap({ $0 }).max(),
              let siblings = try? FileManager.default.contentsOfDirectory(
                  at: url.deletingLastPathComponent(),
                  includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isDirectoryKey]
              ) else { return false }

        let store = upgradeBackupStoreKey(name)
        var hasNewerLiveSibling = false
        var hasNewerBackup = false
        for sibling in siblings {
            let siblingName = sibling.lastPathComponent
            guard siblingName != name, !upgradeBackupIgnoredSiblingNames.contains(siblingName) else { continue }
            if hasUpgradeBackupSignal(siblingName) {
                guard upgradeBackupStoreKey(siblingName) == store, let written = latestWrite(sibling) else { continue }
                hasNewerBackup = hasNewerBackup || written > backupWritten || (written == backupWritten && siblingName > name)
            } else if let written = liveWrite(sibling), written > backupWritten {
                hasNewerLiveSibling = true
            }
        }
        return hasNewerLiveSibling && hasNewerBackup
    }

    // MARK: - Private

    private static func isUpgradeBackupToken(_ token: String) -> Bool {
        upgradeBackupNameTokens.contains(token) || token.hasPrefix("migrat")
    }

    /// Lowercased runs of letters or of digits; everything else separates tokens.
    private static func nameTokens(_ name: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsDigit = false
        for character in name.lowercased() {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { tokens.append(current) }
                current = ""
                continue
            }
            if !current.isEmpty, character.isNumber != currentIsDigit {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            currentIsDigit = character.isNumber
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func latestWrite(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return [values?.contentModificationDate, values?.creationDate].compactMap { $0 }.max()
    }

    /// A live entry's last write: its own mtime, or for a directory the newest of it and its direct children.
    private static func liveWrite(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
        var newest = values?.contentModificationDate
        guard values?.isDirectory == true,
              let children = try? FileManager.default.contentsOfDirectory(
                  at: url, includingPropertiesForKeys: [.contentModificationDateKey]
              ) else { return newest }
        for child in children {
            guard let date = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            newest = max(newest ?? date, date)
        }
        return newest
    }
}
