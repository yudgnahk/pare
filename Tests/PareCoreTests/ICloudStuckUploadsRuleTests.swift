import XCTest
@testable import PareCore

/// iCloud uploads stuck on a full quota: explained, never cleaned, never counted as reclaimable.
final class ICloudStuckUploadsRuleTests: XCTestCase {

    private static let home = URL(fileURLWithPath: "/Users/u")
    private static let environment = ScanEnvironment(homeDirectory: home)
    private static let fullQuota = "0 bytes of quota remaining in personal account"

    private func scan(quota: String?, status: String?) async -> (findings: [ScanFinding], calls: [[String]]) {
        let brctl = ScriptedBrctl(quota: quota, status: status)
        let findings = await ICloudStuckUploadsRule(brctl: brctl.run).customScan(environment: Self.environment) ?? []
        return (findings, brctl.calls)
    }

    // MARK: - Rule

    func testOneExplainOnlyFindingWhenUploadsAreStuck() async throws {
        let result = await scan(quota: Self.fullQuota, status: ICloudUploadStatusParserTests.status)

        XCTAssertEqual(result.calls, [["quota"], ["status"]])
        let finding = try XCTUnwrap(result.findings.first)
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(finding.category, .diagnostics)
        XCTAssertEqual(finding.riskLevel, .advanced)
        XCTAssertEqual(finding.sizeBytes, 0, "pending upload is not disk space Pare can reclaim")
        XCTAssertEqual(finding.path, "/Users/u/Library/Application Support/CloudDocs")

        let size = ByteCountFormatter.string(fromByteCount: 2_840 + 1_733_643 + 9_830_000_000, countStyle: .file)
        XCTAssertEqual(
            finding.reason,
            "Desktop and Documents aren't backed up: iCloud hasn't uploaded \(size) (3 items) for at least 56 days — "
                + "iCloud storage is full"
        )
        XCTAssertEqual(finding.annotations, [.explainOnly(action: ICloudStuckUploadsRule.action)])
    }

    func testFindingNeverNamesFilesOrSubfolders() async throws {
        let findings = await scan(quota: Self.fullQuota, status: ICloudUploadStatusParserTests.status).findings
        let finding = try XCTUnwrap(findings.first)
        let text = [finding.reason, finding.path, ICloudStuckUploadsRule.action].joined(separator: "\n")

        for leaked in ["Secret Project", "Inner", "M{27}o.txt", "S{31}7.png", "P{14}d.app"] {
            XCTAssertFalse(text.contains(leaked), leaked)
        }
    }

    func testStatusSkippedWhileQuotaRemains() async {
        let result = await scan(quota: "50 GB of quota remaining in personal account", status: ICloudUploadStatusParserTests.status)

        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.calls, [["quota"]], "brctl status is slow; only worth running when quota is nearly gone")
    }

    func testStatusRunsJustBelowTheGate() async {
        let gate = ICloudStuckUploadsRule.statusGateRemainingBytes
        let result = await scan(quota: "\(gate - 1) bytes of quota remaining in personal account", status: "")

        XCTAssertEqual(result.calls, [["quota"], ["status"]])
    }

    func testSilentWhenBrctlIsUnavailableOrUnreadable() async {
        let cases: [(quota: String?, status: String?, calls: [[String]])] = [
            (nil, ICloudUploadStatusParserTests.status, [["quota"]]),
            ("Not signed in", ICloudUploadStatusParserTests.status, [["quota"]]),
            (Self.fullQuota, nil, [["quota"], ["status"]]),
            (Self.fullQuota, "garbage", [["quota"], ["status"]]),
            (Self.fullQuota, ICloudUploadStatusParserTests.status.replacingOccurrences(of: "sz:", with: "size="), [["quota"], ["status"]]),
        ]
        for testCase in cases {
            let result = await scan(quota: testCase.quota, status: testCase.status)
            XCTAssertTrue(result.findings.isEmpty, String(describing: testCase.status?.prefix(20)))
            XCTAssertEqual(result.calls, testCase.calls)
        }
    }

    func testRecentBacklogIsNotReported() async {
        let threshold = ICloudStuckUploadsRule.minimumStuckHours
        let young = "    Under /Desktop\n" + ICloudUploadStatusParserTests.item(name: "a", bytes: 1_000, lastHours: "\(threshold - 1)h")
        let old = "    Under /Desktop\n" + ICloudUploadStatusParserTests.item(name: "a", bytes: 1_000, lastHours: "\(threshold)h")

        let youngFindings = await scan(quota: Self.fullQuota, status: young).findings
        let oldFindings = await scan(quota: Self.fullQuota, status: old).findings
        XCTAssertTrue(youngFindings.isEmpty)
        XCTAssertEqual(oldFindings.count, 1)
        XCTAssertEqual(threshold, 72, "the user chose 3 days: until the warning shows, files are silently not backed up")
    }

    func testSingleItemAndSingleFolderWording() async throws {
        let status = "    Under /Desktop\n" + ICloudUploadStatusParserTests.item(name: "a", bytes: 2_000_000, lastHours: "100h")
        let findings = await scan(quota: Self.fullQuota, status: status).findings
        let finding = try XCTUnwrap(findings.first)

        XCTAssertTrue(finding.reason.contains("(1 item) for at least 4 days"), finding.reason)
        XCTAssertTrue(finding.reason.hasPrefix("Desktop isn't backed up: "), finding.reason)
    }

    func testCleanupRefusesFindingAndTotalsExcludeIt() async throws {
        let brctl = ScriptedBrctl(quota: Self.fullQuota, status: ICloudUploadStatusParserTests.status)
        let report = await ScanRunner(environment: Self.environment).run(rules: [ICloudStuckUploadsRule(brctl: brctl.run)])
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.totalReclaimableBytes, 0)

        let store = FileManager.default.temporaryDirectory.appending(path: "pare_icloud_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store) }
        let engine = CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: store),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            trashItem: { url in
                XCTFail("iCloud sync state must never reach the Trash: \(url.path)")
                return nil
            }
        )

        let result = try await engine.clean(findings: report.findings, profileName: "test")

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.skipped.count, 1)
    }

    func testRegisteredInBaselineAndUnifiedScan() {
        let id = ICloudStuckUploadsRule().id
        XCTAssertTrue(RuleCatalog.baseline.contains { $0.id == id })
        XCTAssertTrue(RuleCatalog.all.contains { $0.id == id })
    }

    // MARK: - Never-clean policy

    func testICloudLocationsAreNeverClean() {
        let cases: [(path: String, neverClean: Bool)] = [
            ("/Users/u/Library/Application Support/CloudDocs", true),
            ("/Users/u/Library/Application Support/CloudDocs/session/db/client.db", true),
            ("/Users/u/library/application support/clouddocs", true),
            ("/Users/u/Library/Mobile Documents", true),
            ("/Users/u/Library/Mobile Documents/com~apple~CloudDocs/App.dmg", true),
            ("/Users/u/Library/Mobile Documents/iCloud~md~obsidian/Documents/x.md", true),
            ("/Users/u/Library/Application Support/CloudDocsHelper", false),
            ("/Users/u/Projects/CloudDocs", false),
            ("/Users/u/Documents/Mobile Documents", false),
        ]
        for testCase in cases {
            let url = URL(fileURLWithPath: testCase.path)
            XCTAssertEqual(ScanPolicy.isNeverCleanPath(url, customRoots: []), testCase.neverClean, testCase.path)
            if testCase.neverClean {
                XCTAssertFalse(ScanPolicy.isLowImpactPath(url), testCase.path)
            }
        }
    }

    func testFoldersHoldingICloudStateAreNeverTrashedWhole() {
        for path in ["/Users/u/Library/Application Support", "/Users/u/Library", "/Users/u"] {
            XCTAssertTrue(ScanPolicy.holdsNeverCleanLocation(URL(fileURLWithPath: path), home: Self.home, customRoots: []), path)
        }
        XCTAssertFalse(ScanPolicy.holdsNeverCleanLocation(
            URL(fileURLWithPath: "/Users/u/Library/Application Support/Slack"), home: Self.home, customRoots: []
        ))
    }

    func testCleanupRefusesICloudDriveFileEvenWhenMisTaggedSafe() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let finding = ScanFinding(
            category: .installerFiles,
            riskLevel: .safe,
            reason: "mis-tagged",
            path: "\(home)/Library/Mobile Documents/com~apple~CloudDocs/App.dmg",
            sizeBytes: 100_000_000,
            lastUsed: nil,
            confidence: 1
        )
        let store = FileManager.default.temporaryDirectory.appending(path: "pare_icloud_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store) }
        let engine = CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: store),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            trashItem: { url in
                XCTFail("an iCloud Drive file must never reach the Trash: \(url.path)")
                return nil
            }
        )

        let result = try await engine.clean(findings: [finding], profileName: "test")

        XCTAssertTrue(result.succeeded.isEmpty)
        guard case .some(.workingSetProtected(_)) = result.skipped.first?.error else {
            return XCTFail("expected .workingSetProtected, got \(result.skipped)")
        }
    }
}

/// Answers `brctl <args>` from canned output and records every call.
private final class ScriptedBrctl: @unchecked Sendable {
    private let quota: String?
    private let status: String?
    private let lock = NSLock()
    private var recorded: [[String]] = []

    init(quota: String?, status: String?) {
        self.quota = quota
        self.status = status
    }

    var calls: [[String]] { lock.withLock { recorded } }

    var run: ICloudStuckUploadsRule.Brctl {
        { [self] arguments in
            lock.withLock { recorded.append(arguments) }
            return arguments == ["quota"] ? quota : status
        }
    }
}
