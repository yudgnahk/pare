import XCTest
@testable import PareCore

/// Docker's VM holding host RAM: explained from its settings, never cleaned, never counted as reclaimable.
final class DockerMemoryRuleTests: XCTestCase {

    private static let home = URL(fileURLWithPath: "/Users/u")
    private static let environment = ScanEnvironment(homeDirectory: home)
    private static let storePath = "/Users/u/Library/Group Containers/group.com.docker/settings-store.json"
    private static let legacyPath = "/Users/u/Library/Group Containers/group.com.docker/settings.json"
    private static let gib: UInt64 = 1024 * 1024 * 1024
    private static let gb: Int64 = 1024 * 1024 * 1024
    private static let defaults = DockerDesktopSettingsParserTests.ownerFile

    private func scan(
        files: [String: String],
        hostGiB: UInt64 = 16,
        swap: Int64? = 2 * DockerMemoryRuleTests.gb
    ) async -> (findings: [ScanFinding], swapCalls: Int) {
        let counter = Counter()
        let rule = DockerMemoryRule(
            readFile: { files[$0.path].map { Data($0.utf8) } },
            hostMemoryBytes: { hostGiB * Self.gib },
            swapUsedBytes: {
                counter.increment()
                return swap
            }
        )
        let findings = await rule.customScan(environment: Self.environment) ?? []
        return (findings, counter.value)
    }

    private func store(_ json: String) -> [String: String] { [Self.storePath: json] }

    // MARK: - Gate

    func testNoSettingsFileIsSilentAndSwapIsNeverQueried() async {
        let result = await scan(files: [:])
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.swapCalls, 0)
    }

    func testUnparseableFileIsSilentAndSwapIsNeverQueried() async {
        let result = await scan(files: store("not json"))
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.swapCalls, 0)
    }

    func testConfigThatCannotFireNeverQueriesSwap() async {
        let result = await scan(files: store(#"{"MemoryMiB":4096,"UseResourceSaver":false}"#))
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.swapCalls, 0)
    }

    func testDefaultConfigOnBigHostIsSilent() async {
        let result = await scan(files: store(Self.defaults), hostGiB: 32, swap: 5 * Self.gb)
        XCTAssertTrue(result.findings.isEmpty, "32 GB hosts are not squeezed by Docker's default half")
    }

    func testDefaultConfigOnSmallHostWithSwapFiresCaseB() async throws {
        let result = await scan(files: store(Self.defaults), hostGiB: 16, swap: 2 * Self.gb)

        let finding = try XCTUnwrap(result.findings.first)
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(finding.category, .diagnostics)
        XCTAssertEqual(finding.riskLevel, .advanced)
        XCTAssertEqual(finding.sizeBytes, 0)
        XCTAssertNil(finding.lastUsed)
        XCTAssertEqual(finding.path, Self.storePath)
        XCTAssertEqual(finding.reason, "Docker can take up to 8 GB of RAM — no memory limit set")
        XCTAssertEqual(finding.annotations, [
            .explainOnly(
                action: "Docker Desktop → Settings → Resources: set Memory limit to 4 GB. Opening Docker Desktop starts its VM."
            ),
            .noteAction(.openDockerDesktop),
        ])
    }

    func testSwapAtOrBelowTheMinimumOrUnknownIsSilent() async {
        for swap in [SwapUsageRule.minimumReportedSwapBytes, nil] {
            let result = await scan(files: store(Self.defaults), swap: swap)
            XCTAssertTrue(result.findings.isEmpty, String(describing: swap))
            XCTAssertEqual(result.swapCalls, 1)
        }
    }

    func testResourceSaverOffWithoutLimitFiresOnBigHost() async throws {
        let result = await scan(files: store(#"{"UseResourceSaver":false}"#), hostGiB: 32)

        let finding = try XCTUnwrap(result.findings.first)
        XCTAssertEqual(finding.reason, "Docker can hold 16 GB of RAM while idle — Resource Saver is off, no memory limit")
        guard case .explainOnly(let tip)? = finding.annotations.first else { return XCTFail("missing tip") }
        XCTAssertTrue(tip.contains("set Memory limit to 8 GB"), tip)
        XCTAssertTrue(tip.contains(", turn on Resource Saver"), tip)
    }

    func testKubernetesWording() async throws {
        let result = await scan(files: store(#"{"KubernetesEnabled":true}"#), hostGiB: 32)

        let finding = try XCTUnwrap(result.findings.first)
        XCTAssertEqual(finding.reason, "Kubernetes keeps Docker holding up to 16 GB of RAM — no memory limit")
        guard case .explainOnly(let tip)? = finding.annotations.first else { return XCTFail("missing tip") }
        XCTAssertTrue(tip.contains("turn off Kubernetes if unused"), tip)
    }

    func testMemoryLimitIsNamedWhenSet() async throws {
        let result = await scan(files: store(#"{"MemoryMiB":8192,"UseResourceSaver":false}"#), hostGiB: 16)

        let finding = try XCTUnwrap(result.findings.first)
        XCTAssertEqual(finding.reason, "Docker can hold 8 GB of RAM while idle — Resource Saver is off, memory limit 8 GB")
    }

    func testLimitBoundaryOnSmallHostWithResourceSaverOff() async {
        let fires = await scan(files: store(#"{"MemoryMiB":7936,"UseResourceSaver":false}"#))
        let silent = await scan(files: store(#"{"MemoryMiB":7935,"UseResourceSaver":false}"#))
        XCTAssertEqual(fires.findings.count, 1)
        XCTAssertTrue(silent.findings.isEmpty)
    }

    func testExplicitLimitWithResourceSaverOnIsSilentEvenOnSmallHost() async {
        let result = await scan(files: store(#"{"MemoryMiB":8192,"UseResourceSaver":true}"#))
        XCTAssertTrue(result.findings.isEmpty, "case B needs the limit unset")
    }

    func testLegacySettingsUsedOnlyWhenStoreIsAbsent() async throws {
        let legacy = #"{"memoryMiB":4096,"useResourceSaver":false}"#
        let onlyLegacy = await scan(files: [Self.legacyPath: Self.defaults.replacingOccurrences(of: "{", with: "{\"useResourceSaver\":false,")])
        XCTAssertEqual(onlyLegacy.findings.first?.path, Self.legacyPath)

        let both = await scan(files: [Self.storePath: Self.defaults, Self.legacyPath: legacy])
        XCTAssertEqual(both.findings.first?.path, Self.storePath, "the store wins; legacy is never merged")
    }

    // MARK: - Presentation and policy

    func testHeadlineStaysShort() async throws {
        let files = [
            store(Self.defaults),
            store(#"{"UseResourceSaver":false}"#),
            store(#"{"KubernetesEnabled":true}"#),
            store(#"{"MemoryMiB":8192,"UseResourceSaver":false}"#),
        ]
        for settings in files {
            let big = await scan(files: settings, hostGiB: 32).findings
            let small = await scan(files: settings).findings
            let findings = big + small
            XCTAssertFalse(findings.isEmpty)
            for note in DiagnosticNote.notes(from: findings) {
                XCTAssertLessThan(note.headline.count, 60, note.headline)
                XCTAssertEqual(note.button, .openDockerDesktop)
            }
        }
    }

    func testCleanupRefusesFindingAndTotalsExcludeIt() async throws {
        let rule = DockerMemoryRule(
            readFile: { _ in Data(Self.defaults.utf8) },
            hostMemoryBytes: { 16 * Self.gib },
            swapUsedBytes: { 2 * Self.gb }
        )
        let report = await ScanRunner(environment: Self.environment).run(rules: [rule])
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.totalReclaimableBytes, 0)

        let storeDir = FileManager.default.temporaryDirectory.appending(path: "pare_dockermem_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let engine = CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: storeDir),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            trashItem: { url in
                XCTFail("Docker settings must never reach the Trash: \(url.path)")
                return nil
            }
        )

        let result = try await engine.clean(findings: report.findings, profileName: "test")

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.skipped.count, 1)
    }

    func testRegisteredInDeveloperAndUnifiedScanButNotBaseline() {
        let id = "docker-vm-memory"
        XCTAssertEqual(DockerMemoryRule().id, id)
        XCTAssertTrue(RuleCatalog.developer.contains { $0.id == id })
        XCTAssertTrue(RuleCatalog.all.contains { $0.id == id })
        XCTAssertFalse(RuleCatalog.baseline.contains { $0.id == id })
    }

    func testDockerDesktopLinkIsTheRegisteredDashboardScheme() {
        XCTAssertEqual(DockerDesktopLinks.dashboard.map(\.absoluteString), ["docker-desktop://dashboard/open"])
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
