import XCTest
@testable import PareCore

final class Phase7RuleTests: XCTestCase {

    // MARK: - DockerStorageRule

    func testDockerStorageRuleReturnsEmptyWhenNoDockerPresent() async {
        let rule = DockerStorageRule()
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/tmp/nonexistent_home_\(UUID().uuidString)"))
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings, "customScan should always return a non-nil array")
        XCTAssertTrue(findings!.isEmpty, "No findings when Docker paths do not exist")
    }

    /// VM disk under …/data/vms must never appear as a scan finding (not Top Files / not reclaimable).
    func testDockerStorageRuleDoesNotReportVMDisk() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dockerRawDir = tmp.appending(path: "Library/Containers/com.docker.docker/Data/vms/0/data")
        try FileManager.default.createDirectory(at: dockerRawDir, withIntermediateDirectories: true)
        let dockerRaw = dockerRawDir.appending(path: "Docker.raw")
        try Data(repeating: 0xAB, count: 1024 * 100).write(to: dockerRaw)

        let rule = DockerStorageRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)!

        XCTAssertTrue(findings.filter { $0.riskLevel == .advanced }.isEmpty)
        XCTAssertFalse(findings.contains { $0.path.contains("Docker.raw") || $0.path.contains("/vms/") })
    }

    /// Sparse files still size by allocated bytes (utility), independent of scan findings.
    func testFileSystemUtilsUsesAllocatedSizeForSparseFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let sparse = tmp.appending(path: "sparse.bin")
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let logicalBytes: Int64 = 1_099_511_627_776 // 1 TiB logical
        let fd = open(sparse.path, O_RDWR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(ftruncate(fd, off_t(logicalBytes)), 0)
        var marker = [UInt8](repeating: 0xAB, count: 4096)
        XCTAssertEqual(pwrite(fd, &marker, marker.count, 0), marker.count)

        let logical = FileSystemUtils.logicalFileSize(url: sparse)
        let allocated = FileSystemUtils.fileSize(url: sparse)
        XCTAssertEqual(logical, logicalBytes)
        XCTAssertGreaterThan(allocated, 0)
        XCTAssertLessThan(allocated, 100 * 1024 * 1024)
    }

    func testDockerStorageRuleDetectsLogPathsAsSafe() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let logDir = tmp.appending(path: "Library/Containers/com.docker.docker/Data/log")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // Create a log file old enough to pass the age gate.
        let logFile = logDir.appending(path: "docker.log")
        try Data(repeating: 0x00, count: 512).write(to: logFile)
        let oldDate = Date().addingTimeInterval(-(4 * 24 * 60 * 60))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: logFile.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: logDir.path)

        let rule = DockerStorageRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        let safeFindings = findings!.filter { $0.riskLevel == .safe && $0.path.contains("log") }
        XCTAssertEqual(safeFindings.count, 1, "Docker log directory should be flagged as safe")
    }

    // MARK: - MobileSyncBackupsRule

    func testMobileSyncBackupsRuleReturnsEmptyWhenNoBackupDir() async {
        let rule = MobileSyncBackupsRule()
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/tmp/nonexistent_home_\(UUID().uuidString)"))
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty)
    }

    func testMobileSyncBackupsRuleMostRecentNotFlagged() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let backupRoot = tmp.appending(path: "Library/Application Support/MobileSync/Backup")
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        // Two backups from the same device
        let serial = "FAKE_SERIAL_123"
        let olderBackup = backupRoot.appending(path: "old-backup-uuid")
        try FileManager.default.createDirectory(at: olderBackup, withIntermediateDirectories: true)
        let olderPlist: [String: Any] = [
            "Display Name": "Kelvin's iPhone 15",
            "Product Name": "iPhone 15",
            "Product Version": "17.0",
            "Serial Number": serial,
            "Last Backup Date": Date().addingTimeInterval(-90 * 24 * 60 * 60), // 90 days ago
        ]
        try PropertyListSerialization.data(fromPropertyList: olderPlist, format: .xml, options: 0)
            .write(to: olderBackup.appending(path: "Info.plist"))

        let newerBackup = backupRoot.appending(path: "new-backup-uuid")
        try FileManager.default.createDirectory(at: newerBackup, withIntermediateDirectories: true)
        let newerPlist: [String: Any] = [
            "Display Name": "Kelvin's iPhone 15",
            "Product Name": "iPhone 15",
            "Product Version": "17.1",
            "Serial Number": serial,
            "Last Backup Date": Date().addingTimeInterval(-5 * 24 * 60 * 60), // 5 days ago
        ]
        try PropertyListSerialization.data(fromPropertyList: newerPlist, format: .xml, options: 0)
            .write(to: newerBackup.appending(path: "Info.plist"))

        let rule = MobileSyncBackupsRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        XCTAssertEqual(findings!.count, 1, "Only the older backup should be flagged")
        XCTAssertTrue(findings![0].path.contains("old-backup-uuid"))
        XCTAssertEqual(findings![0].riskLevel, .review)
    }

    func testMobileSyncBackupsRuleSameVersionNotFlagged() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let backupRoot = tmp.appending(path: "Library/Application Support/MobileSync/Backup")
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let serial = "FAKE_SERIAL_456"
        for i in 0..<2 {
            let backup = backupRoot.appending(path: "backup-\(i)")
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Display Name": "Kelvin's iPad",
                "Product Name": "iPad Pro",
                "Product Version": "17.0",
                "Serial Number": serial,
                "Last Backup Date": Date().addingTimeInterval(-5 * 24 * 60 * 60), // same age
            ]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: backup.appending(path: "Info.plist"))
        }

        let rule = MobileSyncBackupsRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        // With only 5 days old, neither should be flagged (30-day gate)
        XCTAssertNil(findings, "Backups younger than 30 days should not be flagged")
    }

    func testMobileSyncBackupsRuleMissingInfoPlistFallback() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let backupRoot = tmp.appending(path: "Library/Application Support/MobileSync/Backup")
        let backupDir = backupRoot.appending(path: "unknown-device-uuid")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let rule = MobileSyncBackupsRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        // No Info.plist → entry created with fallback, but no other backups to compare against
        // and age is < 180 days → should be nil (no findings)
        XCTAssertNil(findings)
    }

    func testMobileSyncBackupsRuleSingleOldBackup() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let backupRoot = tmp.appending(path: "Library/Application Support/MobileSync/Backup")
        let backupDir = backupRoot.appending(path: "old-device-uuid")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Display Name": "Old iPhone",
            "Product Name": "iPhone 12",
            "Product Version": "15.0",
            "Serial Number": "OLD_SERIAL",
            "Last Backup Date": Date().addingTimeInterval(-200 * 24 * 60 * 60), // 200 days ago
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: backupDir.appending(path: "Info.plist"))

        let rule = MobileSyncBackupsRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        XCTAssertEqual(findings!.count, 1, "Single backup > 180 days should be flagged")
        XCTAssertEqual(findings![0].riskLevel, .review)
        XCTAssertTrue(findings![0].reason.contains("Only backup"))
        XCTAssertTrue(findings![0].reason.contains("Old iPhone"))
    }

    // MARK: - BrowserReviewDataRule

    func testBrowserReviewDataRuleReturnsEmptyWhenNoBrowsersPresent() async {
        let rule = BrowserReviewDataRule()
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/tmp/nonexistent_home_\(UUID().uuidString)"))
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty)
    }

    func testBrowserReviewDataRuleSafariPaths() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create Safari history.db old enough to pass the age gate.
        let safariDir = tmp.appending(path: "Library/Safari")
        try FileManager.default.createDirectory(at: safariDir, withIntermediateDirectories: true)
        let historyDB = safariDir.appending(path: "History.db")
        try Data(repeating: 0x00, count: 2048).write(to: historyDB)
        let oldDate = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: historyDB.path)

        let rule = BrowserReviewDataRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        let safariFindings = findings!.filter { $0.path.contains("History.db") }
        XCTAssertEqual(safariFindings.count, 1)
        XCTAssertEqual(safariFindings[0].riskLevel, .review)
        XCTAssertEqual(safariFindings[0].category, .browserCaches)
        XCTAssertTrue(safariFindings[0].reason.contains("Safari browsing history"))
    }

    func testBrowserReviewDataRuleAgeGate() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create a Safari History.db that is too new (< 30 days).
        let safariDir = tmp.appending(path: "Library/Safari")
        try FileManager.default.createDirectory(at: safariDir, withIntermediateDirectories: true)
        let historyDB = safariDir.appending(path: "History.db")
        try Data(repeating: 0x00, count: 2048).write(to: historyDB)
        // No backdating — file is freshly created (too new).

        let rule = BrowserReviewDataRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty, "Freshly created History.db should not be flagged")
    }

    func testBrowserReviewDataRuleOnlyInstalledBrowsers() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Only create Chrome data, no other browsers.
        let chromeDir = tmp.appending(path: "Library/Application Support/Google/Chrome/Default")
        try FileManager.default.createDirectory(at: chromeDir, withIntermediateDirectories: true)
        let historyFile = chromeDir.appending(path: "History")
        try Data(repeating: 0x00, count: 1024).write(to: historyFile)
        let oldDate = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: historyFile.path)

        let rule = BrowserReviewDataRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        let chromeFindings = findings!.filter { $0.path.contains("Chrome") }
        XCTAssertEqual(chromeFindings.count, 1, "Only Chrome should have findings")
        XCTAssertFalse(findings!.contains { $0.path.contains("Brave") }, "Brave should not appear")
        XCTAssertFalse(findings!.contains { $0.path.contains("Edge") }, "Edge should not appear")
    }

    func testBrowserReviewDataRuleDistinctFromBrowserCachesRule() {
        let cachesRule = BrowserCachesRule()
        let reviewRule = BrowserReviewDataRule()
        XCTAssertNotEqual(cachesRule.id, reviewRule.id, "Rules should have different IDs")
        XCTAssertEqual(reviewRule.riskLevel, .review, "BrowserReviewDataRule should be .review")
    }

    // MARK: - Docker never-delete policy

    func testIsDockerNeverDeletePathCoversVMDiskOnly() {
        let raw = URL(fileURLWithPath:
            "/Users/u/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        let vmsData = URL(fileURLWithPath:
            "/Users/u/Library/Containers/com.docker.docker/Data/vms/0/data")
        let logs = URL(fileURLWithPath:
            "/Users/u/Library/Containers/com.docker.docker/Data/log/host/docker.log")
        let cache = URL(fileURLWithPath: "/Users/u/Library/Caches/something")

        XCTAssertTrue(ScanPolicy.isDockerNeverDeletePath(raw))
        XCTAssertTrue(ScanPolicy.isDockerNeverDeletePath(vmsData))
        XCTAssertFalse(ScanPolicy.isDockerNeverDeletePath(logs), "Daemon logs remain cleanable")
        XCTAssertFalse(ScanPolicy.isDockerNeverDeletePath(cache))
    }

    func testDockerSystemPruneArgumentsNeverIncludeVolumes() {
        let args = MaintenanceRunner.dockerSystemPruneArguments
        XCTAssertEqual(args, ["system", "prune", "-f"])
        XCTAssertFalse(args.contains("--volumes"))
        XCTAssertFalse(args.contains("-v"))
    }

    func testDockerReviewMarkersDoNotIncludeVMsTree() {
        for marker in ScanPolicy.developerDockerReviewPathMarkers {
            XCTAssertFalse(marker.contains("/vms"),
                           "Review markers must not include VM disk tree: \(marker)")
        }
    }
}
