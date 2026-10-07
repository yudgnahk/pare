import XCTest
@testable import PareCore

/// Explain-only diagnostics: space Pare can see but must never delete — it only says what to do instead.
final class DiagnosticsFindingsTests: XCTestCase {

    private static let megabyte: Int64 = 1024 * 1024

    /// node holds two deleted files (one via two fds), postgres shares one of them plus a tiny file,
    /// WindowServer maps one deleted region.
    private static let lsofOutput = """
    p100
    cnode
    f12
    D0x1000010
    i555
    s52428800
    n/Users/u/app/logs/big.log
    f13
    D0x1000010
    i555
    s52428800
    n/Users/u/app/logs/big.log
    p101
    cnode
    f9
    D0x1000010
    i556
    s20971520
    n/Users/u/app/tmp/blob
    p200
    cpostgres
    f4
    D0x1000010
    i555
    s52428800
    n/Users/u/app/logs/big.log
    f5
    D0x1000010
    i700
    s1024
    n/Users/u/tiny
    p300
    cWindowServer
    ftxt
    D0x1000011
    i900
    s16777216
    n/private/var/folders/x/shm-region
    """

    // MARK: - Deleted-but-open files

    func testDeletedOpenFilesAreSummedPerHolderAndDedupedByInode() throws {
        let findings = DeletedOpenFilesRule.findings(fromLsofOutput: Self.lsofOutput)

        XCTAssertEqual(findings.map(\.sizeBytes), [70 * Self.megabyte, 16 * Self.megabyte])
        let node = try XCTUnwrap(findings.first)
        XCTAssertEqual(node.path, "/Users/u/app/logs/big.log", "largest deleted file names the finding")
        XCTAssertTrue(node.reason.contains("restart node"), node.reason)
        XCTAssertTrue(node.reason.contains("also held by postgres"), node.reason)
        XCTAssertEqual(findings.last?.path, "/private/var/folders/x/shm-region")
        XCTAssertFalse(findings.contains { $0.reason.contains("restart postgres") }, "postgres keeps only 1 KB of its own")
    }

    func testDeletedOpenFindingsAreExplainOnlyDiagnostics() throws {
        let finding = try XCTUnwrap(DeletedOpenFilesRule.findings(fromLsofOutput: Self.lsofOutput).first)

        XCTAssertEqual(finding.category, .diagnostics)
        XCTAssertEqual(finding.riskLevel, .advanced)
        XCTAssertEqual(finding.annotations, [.explainOnly(action: "Restart node to reclaim the space")])
    }

    func testLsofEscapedNamesAreDecoded() {
        // Real `env -i lsof +L1 -Fn` output for a deleted file named `Tiếng Việt\x41.log`.
        let cases: [(raw: String, decoded: String)] = [
            (#"/private/tmp/q/Ti\xe1\xba\xbfng Vi\xe1\xbb\x87t\\x41.log"#, #"/private/tmp/q/Tiếng Việt\x41.log"#),
            ("/Users/u/Library/Caches/plain.db", "/Users/u/Library/Caches/plain.db"),
            (#"/tmp/a\tb"#, "/tmp/a\tb"),
            (#"/tmp/bad\xff"#, #"/tmp/bad\xff"#),
            (#"/tmp/trailing\"#, #"/tmp/trailing\"#),
            (#"/tmp/short\x4"#, #"/tmp/short\x4"#),
        ]
        for testCase in cases {
            XCTAssertEqual(DeletedOpenFilesRule.unescapedLsofName(testCase.raw), testCase.decoded, testCase.raw)
        }

        let output = "p42\ncTool\nf3\nD0x1\ni9\ns\(20 * Self.megabyte)\n" + #"n/private/tmp/q/Ti\xe1\xba\xbfng.log"#
        XCTAssertEqual(DeletedOpenFilesRule.findings(fromLsofOutput: output).first?.path, "/private/tmp/q/Tiếng.log")
    }

    func testDeletedOpenParserToleratesEmptyAndGarbageOutput() {
        let cases = [
            "",
            "garbage\nmore garbage",
            "p1\ncX\nf3\nn/no/size/or/inode",
            "p1\ncX\nf3\nD0x1\ni5\nsnot-a-number\nn/bad/size",
            "f3\nD0x1\ni5\ns999999999\nn/no/process",
        ]
        for output in cases {
            XCTAssertEqual(DeletedOpenFilesRule.findings(fromLsofOutput: output).count, 0, output)
        }
    }

    func testDeletedOpenRuleReportsNothingWhenLsofUnavailable() async {
        let findings = await DeletedOpenFilesRule(listing: { nil }).customScan(environment: .current())

        XCTAssertEqual(findings?.count, 0)
    }

    // MARK: - Swap

    func testSwapUsageParsing() {
        let cases: [(output: String, used: Int64?)] = [
            ("vm.swapusage: total = 8192.00M  used = 6794.44M  free = 1397.56M  (encrypted)", Int64(6794.44 * 1_048_576)),
            ("total = 2048.00M  used = 0.00M  free = 2048.00M  (encrypted)", 0),
            ("vm.swapusage: total = 4.00G  used = 1.50G  free = 2.50G", Int64(1.5 * 1_073_741_824)),
            ("vm.swapusage: total = 512.00K  used = 256.00K  free = 256.00K", 256 * 1024),
            ("vm.swapusage: total = 8192,00M  used = 4908,88M  free = 3283,12M  (encrypted)", Int64(4908.88 * 1_048_576)),
            ("", nil),
            ("garbage", nil),
            ("vm.swapusage: total = 8192.00M  used = lots  free = 0M", nil),
        ]
        for testCase in cases {
            XCTAssertEqual(SwapUsageRule.usedBytes(fromSysctlOutput: testCase.output), testCase.used, testCase.output)
        }
    }

    func testSwapFindingOnlyAboveThreshold() async throws {
        let threshold = SwapUsageRule.minimumReportedSwapBytes
        let below = "vm.swapusage: total = 8192.00M  used = \(threshold / Self.megabyte - 1).00M  free = 1.00M"
        let above = "vm.swapusage: total = 8192.00M  used = \(threshold / Self.megabyte + 1).00M  free = 1.00M"

        let none = await SwapUsageRule(listing: { below }).customScan(environment: .current()) ?? []
        let some = await SwapUsageRule(listing: { above }).customScan(environment: .current()) ?? []
        let unavailable = await SwapUsageRule(listing: { nil }).customScan(environment: .current()) ?? []

        XCTAssertTrue(none.isEmpty)
        XCTAssertTrue(unavailable.isEmpty)
        let finding = try XCTUnwrap(some.first)
        XCTAssertEqual(some.count, 1)
        XCTAssertEqual(finding.path, SwapUsageRule.findingPath)
        XCTAssertEqual(finding.category, .diagnostics)
        XCTAssertEqual(finding.riskLevel, .advanced)
        XCTAssertTrue(finding.reason.contains("close memory-heavy apps or restart"), finding.reason)
        XCTAssertEqual(finding.annotations, [.explainOnly(action: "Close memory-heavy apps or restart to release swap")])
    }

    // MARK: - Never reclaimable, never cleanable

    func testDiagnosticsExcludedFromReclaimableTotals() async {
        let swap = "vm.swapusage: total = 8192.00M  used = 6794.44M  free = 1397.56M"
        let rules: [any ScanRule] = [
            DeletedOpenFilesRule(listing: { Self.lsofOutput }),
            SwapUsageRule(listing: { swap }),
        ]

        let report = await ScanRunner(environment: .current()).run(rules: rules)

        XCTAssertEqual(report.findings.count, 3)
        XCTAssertEqual(report.totalReclaimableBytes, 0)
    }

    func testCleanupEngineRefusesDiagnosticsEvenWhenMislabelled() async throws {
        let store = FileManager.default.temporaryDirectory.appending(path: "pare_diag_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store) }
        let engine = CleanupEngine(
            store: CleanupTransactionStore(directory: store),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            trashItem: { url in
                XCTFail("diagnostics must never reach the Trash: \(url.path)")
                return nil
            }
        )
        let detected = DeletedOpenFilesRule.findings(fromLsofOutput: Self.lsofOutput)
        let mislabelled = ScanFinding(
            category: .diagnostics,
            riskLevel: .safe,
            reason: "mislabelled",
            path: SwapUsageRule.findingPath,
            sizeBytes: 1,
            lastUsed: nil,
            confidence: 1
        )

        let result = try await engine.clean(findings: detected + [mislabelled], profileName: "test")

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.skipped.count, detected.count + 1)
        for item in result.skipped {
            guard case .advancedRiskBlocked = item.error else {
                XCTFail("expected .advancedRiskBlocked for \(item.path), got \(item.error)")
                continue
            }
        }
    }

    func testRulesAreRegisteredInUnifiedScan() {
        let ids = Set(RuleCatalog.all.map(\.id))

        XCTAssertTrue(ids.contains(DeletedOpenFilesRule().id))
        XCTAssertTrue(ids.contains(SwapUsageRule().id))
    }
}
