import XCTest
@testable import PareCore

/// Folders of many tiny files whose disk blocks far exceed their content: explained, never cleaned.
final class TinyFileQueueRuleTests: XCTestCase {

    private static let day: TimeInterval = 24 * 60 * 60
    private static let thresholds = TinyFileQueueRule.Thresholds(
        minimumFileCount: 50, tinyFileBytes: 4096, minimumTinyFraction: 0.9,
        minimumAllocatedToLogicalRatio: 4, minimumAgeSeconds: 30 * day
    )

    private var home: URL!
    private var queue: URL { home.appending(path: "Library/Caches/com.example.agent/spool") }

    override func setUpWithError() throws {
        home = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_tiny_\(UUID().uuidString)/home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
    }

    func testReportsOldQueueOfTinyFilesAsExplainOnlyDiagnostic() async throws {
        try makeFiles(count: 60, bytes: 200, daysAgo: 40)

        let findings = await scan()

        let finding = try XCTUnwrap(findings.first, "\(findings)")
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(finding.path, queue.path)
        XCTAssertEqual(finding.category, .diagnostics)
        XCTAssertEqual(finding.riskLevel, .advanced)
        XCTAssertGreaterThanOrEqual(finding.sizeBytes, 60 * 200 * 4, "size is the allocated, not logical, size")
        XCTAssertTrue(finding.reason.hasPrefix("60 tiny files (avg 200 bytes) use "), finding.reason)
        XCTAssertTrue(finding.reason.contains("com.example.agent queue; clear it from the app or contact its support"), finding.reason)
        XCTAssertEqual(finding.annotations, [.explainOnly(action: "Clear it from com.example.agent or contact its support")])
    }

    func testSignalTable() async throws {
        let cases: [(name: String, count: Int, bytes: Int, daysAgo: Double, reported: Bool)] = [
            ("too few files", 40, 200, 40, false),
            ("too young", 60, 200, 5, false),
            ("not tiny", 60, 5000, 40, false),
            ("qualifies", 60, 200, 40, true),
        ]
        for testCase in cases {
            try? FileManager.default.removeItem(at: queue)
            try makeFiles(count: testCase.count, bytes: testCase.bytes, daysAgo: testCase.daysAgo)

            let findings = await scan()

            XCTAssertEqual(!findings.isEmpty, testCase.reported, testCase.name)
        }
    }

    func testEntryBudgetAndDeadlineBailOut() async throws {
        try makeFiles(count: 60, bytes: 200, daysAgo: 40)

        let overBudget = await scan(entryBudget: 10)
        XCTAssertTrue(overBudget.isEmpty, "the walk stops once its entry budget is spent")

        // A present-day clock, so the age gate would pass and only the deadline can reject the folder.
        let frozen = Date()
        let withinDeadline = await TinyFileQueueRule(thresholds: Self.thresholds, now: { frozen })
            .customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []
        XCTAssertEqual(withinDeadline.count, 1, "control: the same clock reports the folder when time remains")
        let pastDeadline = await TinyFileQueueRule(thresholds: Self.thresholds, perDirectoryBudgetSeconds: 0, now: { frozen })
            .customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []
        XCTAssertTrue(pastDeadline.isEmpty, "a directory not fully measured before its deadline is not reported")
    }

    func testCleanupRefusesTheQueueFinding() async throws {
        try makeFiles(count: 60, bytes: 200, daysAgo: 40)
        let findings = await scan()
        XCTAssertEqual(findings.count, 1)
        let engine = CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: home.deletingLastPathComponent().appending(path: "store")),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            trashItem: { url in
                XCTFail("a diagnostics finding must never reach the Trash: \(url.path)")
                return nil
            }
        )

        let result = try await engine.clean(findings: findings, profileName: "test")

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.path))
    }

    func testRegisteredInUnifiedScan() {
        XCTAssertTrue(RuleCatalog.all.contains { $0.id == TinyFileQueueRule().id })
    }

    // MARK: - Helpers

    private func scan(entryBudget: Int = TinyFileQueueRule.defaultEntryBudget) async -> [ScanFinding] {
        await TinyFileQueueRule(thresholds: Self.thresholds, entryBudget: entryBudget)
            .customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []
    }

    private func makeFiles(count: Int, bytes: Int, daysAgo: Double) throws {
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        let date = Date().addingTimeInterval(-daysAgo * Self.day)
        for index in 0..<count {
            let file = queue.appending(path: "msg-\(index).json")
            try Data(repeating: 0x41, count: bytes).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        }
    }
}
