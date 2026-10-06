import XCTest
@testable import PareCore

/// A launch agent whose binary is missing may only point at a moved app or an unmounted volume,
/// so orphaned agents are reported and never cleaned.
final class OrphanedLaunchAgentsSafetyTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        // Canonical `/private/var/…` spelling, as directory listings report it. Not under /tmp:
        // that is a low-impact marker and would mask the persona-marker removal.
        home = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testOrphanedAgentIsAdvanced() async throws {
        let plist = try makeOrphanedAgent("com.example.gone")

        let findings = await OrphanedLaunchAgentsRule().customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []

        let finding = try XCTUnwrap(findings.first { $0.path == plist.path })
        XCTAssertEqual(finding.riskLevel, .advanced)
        XCTAssertTrue(finding.reason.contains("/Applications/Gone.app/Contents/MacOS/Gone"), finding.reason)
        XCTAssertTrue(finding.reason.contains("may have moved or live on an unmounted volume"), finding.reason)
    }

    func testOrphanedAgentsNotInReclaimableTotal() async throws {
        _ = try makeOrphanedAgent("com.example.gone")

        let report = await ScanRunner(environment: ScanEnvironment(homeDirectory: home))
            .run(rules: [OrphanedLaunchAgentsRule()])

        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.totalReclaimableBytes, 0)
    }

    /// Even mislabelled `.review`, a LaunchAgents plist no longer passes any cleanup allow-list.
    func testCleanupBlocksLaunchAgentPlist() async throws {
        let plist = try makeOrphanedAgent("com.example.gone")
        let engine = CleanupEngine(
            store: CleanupTransactionStore(directory: home.appending(path: "store")),
            projectRootsProvider: { [] }
        )
        let finding = ScanFinding(
            category: .launchAgents,
            riskLevel: .review,
            reason: "mislabelled",
            path: plist.path,
            sizeBytes: 256,
            lastUsed: Date().addingTimeInterval(-60 * 24 * 60 * 60),
            confidence: 1.0
        )

        let result = try await engine.clean(findings: [finding], profileName: "test", dryRun: true)

        XCTAssertTrue(result.succeeded.isEmpty)
        guard case .some(.unsafePath(_)) = result.skipped.first?.error else {
            return XCTFail("expected .unsafePath, got \(result.skipped)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: plist.path))
    }

    // MARK: - Helpers

    /// A 60-day-old plist in `<home>/Library/LaunchAgents` pointing at a binary that does not exist.
    private func makeOrphanedAgent(_ label: String) throws -> URL {
        let agents = home.appending(path: "Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plist = agents.appending(path: "\(label).plist")
        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/Applications/Gone.app/Contents/MacOS/Gone", "--agent"],
        ]
        try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0).write(to: plist)
        let old = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old, .creationDate: old], ofItemAtPath: plist.path)
        return URL(fileURLWithPath: plist.path)
    }
}
