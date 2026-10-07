import XCTest
@testable import PareCore

/// Cache activity is display-only: hot, warm or cold from the newest mtime, never a change to risk or selection.
final class CacheActivityTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 86_400
    private var root: URL!

    override func setUpWithError() throws {
        root = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_activity_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Classifier

    func testClassifierBoundaries() {
        let hot = Double(CacheActivityClassifier.defaultHotDays) * day
        let cold = Double(CacheActivityClassifier.defaultColdDays) * day
        let cases: [(name: String, date: Date?, activity: CacheActivity)] = [
            ("nil date", nil, .warm),
            ("future date", now.addingTimeInterval(3_600), .hot),
            ("just now", now, .hot),
            ("exactly N days", now.addingTimeInterval(-hot), .hot),
            ("just past N days", now.addingTimeInterval(-hot - 1), .warm),
            ("just under M days", now.addingTimeInterval(-cold + 1), .warm),
            ("exactly M days", now.addingTimeInterval(-cold), .cold),
            ("long ago", now.addingTimeInterval(-400 * day), .cold),
        ]
        for testCase in cases {
            XCTAssertEqual(CacheActivityClassifier.classify(newestEntryDate: testCase.date, now: now),
                           testCase.activity, testCase.name)
        }
    }

    func testLabelText() {
        let cases: [(label: CacheActivityLabel, text: String)] = [
            (CacheActivityLabel(activity: .hot, newestEntryDate: now), "In active use"),
            (CacheActivityLabel(activity: .warm, newestEntryDate: now.addingTimeInterval(-10 * day)), "Last used 10 days ago"),
            (CacheActivityLabel(activity: .warm, newestEntryDate: now.addingTimeInterval(-1 * day)), "Last used 1 day ago"),
            (CacheActivityLabel(activity: .cold, newestEntryDate: now.addingTimeInterval(-45 * day)), "Not used in 45 days"),
            (CacheActivityLabel(activity: .warm, newestEntryDate: nil), "Last use unknown"),
        ]
        for testCase in cases {
            XCTAssertEqual(testCase.label.text(now: now), testCase.text)
        }
    }

    // MARK: - Sampler

    func testSamplerFindsNewestEntryWithinDepth() throws {
        let cache = try makeTree()

        let sample = CacheActivitySampler.sample(cache, deadline: Date().addingTimeInterval(10))

        XCTAssertTrue(sample.isComplete)
        let newest = try XCTUnwrap(sample.newest)
        XCTAssertEqual(newest.timeIntervalSince1970, Date().addingTimeInterval(-5 * day).timeIntervalSince1970, accuracy: 60,
                       "the level-3 file written today is beyond the depth limit")
    }

    func testSamplerStopsAtEntryCap() throws {
        let cache = try makeTree()

        let sample = CacheActivitySampler.sample(cache, maxEntries: 2, deadline: Date().addingTimeInterval(10))

        XCTAssertFalse(sample.isComplete)
        XCTAssertEqual(sample.sampledEntries, 2)
    }

    func testSamplerStopsAtDeadline() throws {
        let cache = try makeTree()

        let sample = CacheActivitySampler.sample(cache, deadline: Date().addingTimeInterval(-1))

        XCTAssertFalse(sample.isComplete)
        XCTAssertEqual(sample.sampledEntries, 0)
    }

    // MARK: - Labeler

    func testLabelerLeavesRiskAndFindingsUntouched() throws {
        let cache = try makeTree()
        let findings = [
            finding(cache.path, risk: .safe, category: .userCaches),
            finding(root.appending(path: "other").path, risk: .review, category: .developerPackageCaches),
            finding(root.appending(path: "vm").path, risk: .advanced, category: .developerPackageCaches),
            finding(root.appending(path: "logs").path, risk: .safe, category: .logsAndCrashReports),
        ]
        let before = findings.map { "\($0.path)|\($0.riskLevel)|\($0.reason)|\($0.sizeBytes)" }

        let labels = CacheActivityLabeler.labels(for: findings)

        XCTAssertEqual(findings.map { "\($0.path)|\($0.riskLevel)|\($0.reason)|\($0.sizeBytes)" }, before)
        XCTAssertEqual(Set(labels.keys), [findings[0].path, findings[1].path], "advanced and non-cache findings get no label")
        XCTAssertEqual(labels[cache.path]?.activity, .warm, "newest sampled entry is 5 days old")
    }

    // MARK: - Helpers

    /// `cache/a.bin` (40 days old), `cache/sub/b.bin` (5 days old), `cache/sub/deep/c.bin` (today, beyond depth 2).
    private func makeTree() throws -> URL {
        let cache = root.appending(path: "cache")
        let deep = cache.appending(path: "sub/deep")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let files: [(URL, Double)] = [
            (cache.appending(path: "a.bin"), 40),
            (cache.appending(path: "sub/b.bin"), 5),
            (deep.appending(path: "c.bin"), 0),
        ]
        for (url, daysAgo) in files {
            try Data(repeating: 0x41, count: 64).write(to: url)
            try setModified(url, daysAgo: daysAgo)
        }
        // Directory mtimes would otherwise read "today".
        for dir in [deep, cache.appending(path: "sub"), cache] {
            try setModified(dir, daysAgo: 40)
        }
        return URL(fileURLWithPath: cache.path)
    }

    private func setModified(_ url: URL, daysAgo: Double) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-daysAgo * day)], ofItemAtPath: url.path
        )
    }

    private func finding(_ path: String, risk: RiskLevel, category: ScanCategory) -> ScanFinding {
        ScanFinding(category: category, riskLevel: risk, reason: "test", path: path,
                    sizeBytes: 1_000, lastUsed: nil, confidence: 1.0)
    }
}
