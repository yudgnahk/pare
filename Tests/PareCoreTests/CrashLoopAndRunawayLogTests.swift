import XCTest
@testable import PareCore

/// Explain-only diagnostics: crash loops and runaway logs are reported, never cleaned.
final class CrashLoopAndRunawayLogTests: XCTestCase {

    private var home: URL!
    private let now = Date()
    private let mb: Int64 = 1024 * 1024

    override func setUpWithError() throws {
        // Directory listings report `/private/var/…`; `resolvingSymlinksInPath()` would strip `/private` instead.
        home = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Crash loops

    func testCrashLoopGroupsReportsByAppName() async throws {
        let modern = home.appending(path: "Library/Logs/DiagnosticReports")
        let legacy = home.appending(path: "Library/DiagnosticReports")
        var fooBytes: Int64 = 0
        for index in 0..<12 {
            let dir = index.isMultiple(of: 2) ? modern : legacy
            let url = try writeIPS(in: dir, file: "Foo-2026-10-05-1011\(10 + index).ips", appName: "Foo",
                                   at: now.addingTimeInterval(-Double(index) * 3600))
            fooBytes += try size(url)
        }
        for index in 0..<3 {
            try writeIPS(in: modern, file: "Bar-2026-10-05-1011\(10 + index).ips", appName: "Bar",
                         at: now.addingTimeInterval(-Double(index) * 60))
        }

        let findings = await CrashLoopRule(now: { self.now }).customScan(environment: environment()) ?? []

        XCTAssertEqual(findings.count, 1, "\(findings.map(\.reason))")
        let finding = try XCTUnwrap(findings.first)
        XCTAssertTrue(finding.reason.contains("Foo crashed 12×"), finding.reason)
        XCTAssertEqual(finding.riskLevel, .advanced)
        XCTAssertEqual(finding.category, .logsAndCrashReports)
        XCTAssertEqual(finding.sizeBytes, fooBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finding.path), "grouping path must not alias a real report")
    }

    func testCrashLoopFallsBackToFilenamePrefixWithoutHeader() async throws {
        let dir = home.appending(path: "Library/Logs/DiagnosticReports")
        for index in 0..<10 {
            let url = dir.appending(path: "Baz Helper_2026-10-05-1011\(10 + index)_host.ips")
            try writeFile(url, contents: "not a json header\n")
            try setModified(url, now.addingTimeInterval(-Double(index) * 60))
        }

        let findings = await CrashLoopRule(now: { self.now }).customScan(environment: environment()) ?? []

        XCTAssertEqual(findings.map(\.reason).filter { $0.contains("Baz Helper crashed 10×") }.count, 1,
                       "\(findings.map(\.reason))")
    }

    func testReportsSpreadOverTimeAreNotALoop() async throws {
        let dir = home.appending(path: "Library/Logs/DiagnosticReports")
        for index in 0..<12 {
            try writeIPS(in: dir, file: "Foo-\(index).ips", appName: "Foo",
                         at: now.addingTimeInterval(-Double(index) * 86400))
        }

        let findings = await CrashLoopRule(now: { self.now }).customScan(environment: environment()) ?? []

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.reason))")
    }

    func testCrashLoopBytesAreNotCountedTwice() async throws {
        let dir = home.appending(path: "Library/Logs/DiagnosticReports")
        for index in 0..<10 {
            // Old enough for the deletable rule's age gate, still a loop inside one 2-day window.
            let url = try writeIPS(in: dir, file: "Foo-\(index).ips", appName: "Foo",
                                   at: now.addingTimeInterval(-3 * 86400 - Double(index) * 60))
            try setModified(url, now.addingTimeInterval(-3 * 86400))
        }
        let runner = ScanRunner(environment: environment(), traversal: FileSystemTraversal())

        let report = await runner.run(rules: [LogsAndCrashReportsRule(), CrashLoopRule(now: { self.now })])

        let deletable = report.findings.filter { $0.riskLevel == .safe }
        XCTAssertEqual(report.findings.filter { $0.riskLevel == .advanced }.count, 1)
        XCTAssertEqual(deletable.count, 10, "existing deletable findings unchanged")
        XCTAssertEqual(report.totalReclaimableBytes, deletable.reduce(0) { $0 + $1.sizeBytes })
    }

    // MARK: - Runaway logs

    func testRunawayLogOutsideLibraryLogsIsReported() async throws {
        let appSupportLog = try makeSparseLog("Library/Application Support/Daemon/daemon.log", bytes: 250 * mb)
        let dotDirLog = try makeSparseLog(".agentd/logs/stdout.out", bytes: 300 * mb)

        let findings = await RunawayLogsRule(now: { self.now }).customScan(environment: environment()) ?? []

        XCTAssertEqual(Set(findings.map(\.path)), [appSupportLog.path, dotDirLog.path])
        for finding in findings {
            XCTAssertEqual(finding.riskLevel, .advanced)
            XCTAssertEqual(finding.category, .logsAndCrashReports)
            XCTAssertTrue(finding.reason.contains("Pare won't delete live logs"), finding.reason)
        }
    }

    func testRunawayLogsIgnoreSmallRotatedLibraryAndDeepFiles() async throws {
        try makeSparseLog("Library/Logs/App/app.log", bytes: 250 * mb)
        try makeSparseLog("Library/Application Support/Daemon/old.log", bytes: 250 * mb,
                          modified: now.addingTimeInterval(-3 * 86400))
        try makeSparseLog("Library/Application Support/Daemon/small.log", bytes: 10 * mb)
        try makeSparseLog("Library/Application Support/Daemon/data.bin", bytes: 250 * mb)
        try makeSparseLog("Library/Application Support/A/b/c/d/e/deep.log", bytes: 250 * mb)

        let findings = await RunawayLogsRule(now: { self.now }).customScan(environment: environment()) ?? []

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    func testRunawayLogsAreExcludedFromReclaimableTotals() async throws {
        try makeSparseLog("Library/Application Support/Daemon/daemon.log", bytes: 250 * mb)
        let runner = ScanRunner(environment: environment(), traversal: FileSystemTraversal())

        let report = await runner.run(rules: [RunawayLogsRule(now: { self.now })])

        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.totalReclaimableBytes, 0)
    }

    // MARK: - Helpers

    private func environment() -> ScanEnvironment {
        ScanEnvironment(
            homeDirectory: home,
            tempDirectory: home.appending(path: "tmp"),
            systemApplicationDirectories: []
        )
    }

    /// Writes a crash report with the real two-part layout: a one-line JSON header, then the JSON body.
    @discardableResult
    private func writeIPS(in dir: URL, file: String, appName: String, at date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        let header = """
        {"app_name":"\(appName)","timestamp":"\(formatter.string(from: date))","app_version":"1.0",\
        "slice_uuid":"7d1d4e8a-0000-0000-0000-000000000000","build_version":"1","platform":1,\
        "bundleID":"com.example.\(appName.lowercased())","share_with_app_devs":0,"is_first_party":0,\
        "bug_type":"309","os_version":"macOS 26.0 (25A354)","roots_installed":0,"name":"\(appName)",\
        "incident_id":"\(UUID().uuidString)"}
        """
        let body = #"{"uptime":1000,"procName":"\#(appName)","exception":{"type":"EXC_CRASH","signal":"SIGABRT"}}"#
        let url = dir.appending(path: file)
        try writeFile(url, contents: header + "\n" + body + "\n")
        try setModified(url, date)
        return URL(fileURLWithPath: url.path)
    }

    private func writeFile(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    /// A sparse file: logical size `bytes`, almost nothing allocated on disk.
    @discardableResult
    private func makeSparseLog(_ relative: String, bytes: Int64, modified: Date? = nil) throws -> URL {
        let url = home.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.close()
        if let modified {
            try setModified(url, modified)
        }
        return URL(fileURLWithPath: url.path)
    }

    private func setModified(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func size(_ url: URL) throws -> Int64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
