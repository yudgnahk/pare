import XCTest
@testable import PareCore

/// Cleanup records the volume's real free space before and after, so the UI can show what the disk actually gained.
final class VerifiedReclaimTests: XCTestCase {

    private var root: URL!
    private let gb: Int64 = 1_000_000_000

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/private/tmp/VerifiedReclaim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - CleanupTransaction persistence

    func testTransactionRoundTripsFreeSpace() throws {
        let store = CleanupTransactionStore(directory: root.appending(path: "transactions"))
        let transaction = CleanupTransaction(
            profileName: "all", isDryRun: false, items: [item(bytes: 5)],
            freeBytesBefore: 100 * gb, freeBytesAfter: 101 * gb
        )

        try store.save(transaction)
        let loaded = try XCTUnwrap(try store.loadAll().first)

        XCTAssertEqual(loaded.freeBytesBefore, 100 * gb)
        XCTAssertEqual(loaded.freeBytesAfter, 101 * gb)
        XCTAssertEqual(loaded.measuredBytesFreed, gb)
    }

    func testRecordWithoutFreeSpaceFieldsStillDecodes() throws {
        let directory = root.appending(path: "transactions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        {
          "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "isDryRun" : false,
          "items" : [ { "originalPath" : "/Users/u/Library/Caches/x", "reason" : "cache",
                        "riskLevelRaw" : "safe", "sizeBytes" : 42, "trashedPath" : "/Users/u/.Trash/x" } ],
          "profileName" : "all",
          "timestamp" : "2026-09-01T10:00:00Z"
        }
        """
        try Data(legacy.utf8).write(to: directory.appending(path: "6F9619FF-8B86-D011-B42D-00C04FC964FF.json"))

        let loaded = try XCTUnwrap(try CleanupTransactionStore(directory: directory).loadAll().first)

        XCTAssertEqual(loaded.totalBytesFreed, 42)
        XCTAssertNil(loaded.freeBytesBefore)
        XCTAssertNil(loaded.freeBytesAfter)
        XCTAssertNil(loaded.measuredBytesFreed)
    }

    // MARK: - CleanupEngine

    func testEngineRecordsFreeSpaceBeforeAndAfter() async throws {
        let file = try makeCacheFile()
        let provider = StubFreeSpace([
            VolumeFreeSpace(importantUsageBytes: 100 * gb, availableBytes: 90 * gb),
            VolumeFreeSpace(importantUsageBytes: 100 * gb + 4096, availableBytes: 90 * gb + 4096),
        ])

        let result = try await makeEngine(provider).clean(findings: [finding(file)], profileName: "test")

        let transaction = try XCTUnwrap(result.transaction)
        XCTAssertEqual(transaction.freeBytesBefore, 100 * gb)
        XCTAssertEqual(transaction.freeBytesAfter, 100 * gb + 4096)
        XCTAssertEqual(transaction.measuredBytesFreed, 4096)
        XCTAssertEqual(provider.calls, 2)
    }

    func testEngineFallsBackToPlainAvailableCapacity() async throws {
        let file = try makeCacheFile()
        let provider = StubFreeSpace([
            VolumeFreeSpace(importantUsageBytes: nil, availableBytes: 50 * gb),
            VolumeFreeSpace(importantUsageBytes: 60 * gb, availableBytes: 50 * gb + 10),
        ])

        let result = try await makeEngine(provider).clean(findings: [finding(file)], profileName: "test")

        XCTAssertEqual(result.transaction?.measuredBytesFreed, 10, "both readings must use the same metric")
    }

    func testDryRunDoesNotMeasureFreeSpace() async throws {
        let file = try makeCacheFile()
        let provider = StubFreeSpace([VolumeFreeSpace(importantUsageBytes: gb, availableBytes: gb)])

        let result = try await makeEngine(provider).clean(findings: [finding(file)], profileName: "test", dryRun: true)

        XCTAssertNil(result.transaction?.freeBytesBefore)
        XCTAssertNil(result.transaction?.measuredBytesFreed)
        XCTAssertEqual(provider.calls, 0)
    }

    // MARK: - ReclaimSummary

    func testReclaimSummaryText() {
        let estimate = format(2 * gb)
        let cases: [(name: String, measured: Int64?, text: String)] = [
            ("not measured", nil, "Estimated \(estimate)"),
            ("gained", 1 * gb, "Estimated \(estimate) · Disk actually gained \(format(gb))"),
            ("zero", 0, "Estimated \(estimate) · Disk actually gained nothing"),
            ("negative", -300_000_000, "Estimated \(estimate) · Disk actually gained nothing (free space fell by \(format(300_000_000)))"),
            ("drift up", 3_000_000, "Estimated \(estimate) · Disk actually gained nothing"),
            ("drift down", -3_000_000, "Estimated \(estimate) · Disk actually gained nothing"),
        ]
        for testCase in cases {
            XCTAssertEqual(
                ReclaimSummary(estimatedBytes: 2 * gb, measuredBytes: testCase.measured).text,
                testCase.text,
                testCase.name
            )
        }
    }

    func testSmallCleanupInsideNoiseIsNotReportedAsGainingNothing() {
        let summary = ReclaimSummary(estimatedBytes: 30_000_000, measuredBytes: 30_000_000)

        XCTAssertEqual(summary.text, "Estimated \(format(30_000_000))")
        XCTAssertNil(summary.trashHint)
    }

    func testTrashHintOnlyWhenGainFallsWellShortOfEstimate() {
        let cases: [(name: String, estimated: Int64, measured: Int64?, hint: Bool)] = [
            ("not measured", 2 * gb, nil, false),
            ("close to estimate", 2 * gb, 2 * gb - 1_000_000, false),
            ("half exactly", 2 * gb, gb, false),
            ("far short", 2 * gb, 10_000_000, true),
            ("zero", 2 * gb, 0, true),
            ("negative", 2 * gb, -5, true),
            ("nothing estimated", 0, 0, false),
            ("tiny cleanup, drift above estimate", 4_096, 3_000_000, false),
            ("30 MB cleanup that fully landed", 30_000_000, 30_000_000, false),
        ]
        for testCase in cases {
            let summary = ReclaimSummary(estimatedBytes: testCase.estimated, measuredBytes: testCase.measured)
            XCTAssertEqual(summary.trashHint != nil, testCase.hint, testCase.name)
        }
        XCTAssertEqual(
            ReclaimSummary(estimatedBytes: 2 * gb, measuredBytes: 0).trashHint,
            "Items are in the Trash on the same disk — empty the Trash to free the space."
        )
    }

    func testSummaryFromTransaction() {
        let transaction = CleanupTransaction(
            profileName: "all", isDryRun: false, items: [item(bytes: 3 * gb)],
            freeBytesBefore: 10 * gb, freeBytesAfter: 10 * gb + 7
        )

        let summary = ReclaimSummary(transaction: transaction)

        XCTAssertEqual(summary, ReclaimSummary(estimatedBytes: 3 * gb, measuredBytes: 7))
    }

    // MARK: - Helpers

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func item(bytes: Int64) -> CleanupItem {
        CleanupItem(originalPath: "/Users/u/Library/Caches/x", trashedPath: "/Users/u/.Trash/x",
                    sizeBytes: bytes, reason: "cache", riskLevel: .safe)
    }

    /// Under `Library/Caches/` so the low-impact gate admits it.
    private func makeCacheFile() throws -> URL {
        let dir = root.appending(path: "Library/Caches/com.pare.test")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "cache.bin")
        try Data(repeating: 0x41, count: 4096).write(to: url)
        return url
    }

    private func finding(_ url: URL) -> ScanFinding {
        ScanFinding(category: .userCaches, riskLevel: .safe, reason: "Test", path: url.path,
                    sizeBytes: 4096, lastUsed: Date(), confidence: 1.0)
    }

    private func makeEngine(_ provider: StubFreeSpace) -> CleanupEngine {
        let trash = root.appending(path: "Trash")
        try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: root.appending(path: "transactions")),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            now: { .distantFuture },
            trashItem: { url in
                let destination = trash.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            },
            freeSpace: provider
        )
    }
}

/// Returns queued readings in order, repeating the last one, and counts calls.
private final class StubFreeSpace: VolumeFreeSpaceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [VolumeFreeSpace]
    private var count = 0

    init(_ readings: [VolumeFreeSpace]) {
        self.readings = readings
    }

    var calls: Int { lock.withLock { count } }

    func freeSpace(forVolumeContaining url: URL) -> VolumeFreeSpace? {
        lock.withLock {
            count += 1
            return readings.count > 1 ? readings.removeFirst() : readings.first
        }
    }
}
