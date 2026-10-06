import XCTest
@testable import PareCore

final class ProjectArtifactsRuleBudgetTests: XCTestCase {

    private var tmp: URL!
    private var suiteName: String!

    override func setUpWithError() throws {
        // Directory listings report `/private/var/…`; `resolvingSymlinksInPath()` would strip `/private` instead.
        tmp = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        suiteName = "pare.tests.project-budget.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    // Call order: deadline, root 1 listing, root 1 sizing, root 2 listing — the 4th call is past 2.5 s.
    func testClockPastBudgetAfterFirstRootKeepsItsFindingsAndReportsNotice() async throws {
        let first = try makeArtifact("one/.cache")
        _ = try makeArtifact("two/.cache")
        let rule = makeRule(
            manualRoots: [tmp.appending(path: "one"), tmp.appending(path: "two")],
            timeBudget: 2.5,
            clock: TickingClock(step: 1)
        )

        let scanned = try await rule.customScanResult(environment: ScanEnvironment.current())
        let result = try XCTUnwrap(scanned)

        XCTAssertEqual(result.findings.map(\.path), [first.path])
        let message = try XCTUnwrap(result.incompleteMessage)
        XCTAssertTrue(message.contains("1 of 2"), message)
    }

    func testZeroBudgetReportsNoticeInsteadOfSilentEmpty() async throws {
        _ = try makeArtifact("one/.cache")
        let rule = makeRule(manualRoots: [tmp.appending(path: "one")], timeBudget: 0, clock: TickingClock(step: 0))

        let scanned = try await rule.customScanResult(environment: ScanEnvironment.current())
        let result = try XCTUnwrap(scanned)

        XCTAssertTrue(result.findings.isEmpty)
        let message = try XCTUnwrap(result.incompleteMessage)
        XCTAssertTrue(message.contains("0 of 1"), message)
    }

    func testCompleteWalkReportsNoNotice() async throws {
        _ = try makeArtifact("one/.cache")
        let rule = makeRule(manualRoots: [tmp.appending(path: "one")])

        let scanned = try await rule.customScanResult(environment: ScanEnvironment.current())
        let result = try XCTUnwrap(scanned)

        XCTAssertEqual(result.findings.count, 1)
        XCTAssertNil(result.incompleteMessage)
    }

    func testNestedRootIsWalkedOnce() async throws {
        let cache = try makeArtifact("outer/inner/.cache")
        let rule = makeRule(manualRoots: [tmp.appending(path: "outer"), tmp.appending(path: "outer/inner")])

        let scanned = try await rule.customScanResult(environment: ScanEnvironment.current())
        let result = try XCTUnwrap(scanned)

        XCTAssertEqual(result.findings.filter { $0.path == cache.path }.count, 1)
    }

    func testNestedRootInAliasSpellingIsWalkedOnce() async throws {
        let cache = try makeArtifact("outer/inner/.cache")
        let aliasInner = URL(fileURLWithPath: String(tmp.path.dropFirst("/private".count)) + "/outer/inner")
        XCTAssertTrue(tmp.path.hasPrefix("/private/"), "precondition: canonical temp spelling")
        let rule = makeRule(manualRoots: [tmp.appending(path: "outer"), aliasInner])

        let scanned = try await rule.customScanResult(environment: ScanEnvironment.current())
        let result = try XCTUnwrap(scanned)

        XCTAssertEqual(result.findings.filter { $0.path == cache.path }.count, 1)
        XCTAssertEqual(result.findings.count, 1)
    }

    func testNestedRootUnderHiddenFolderIsStillWalked() async throws {
        let cache = try makeArtifact("outer/.hidden/proj/.cache")
        let rule = makeRule(manualRoots: [tmp.appending(path: "outer"), tmp.appending(path: "outer/.hidden/proj")])

        let scanned = try await rule.customScanResult(environment: ScanEnvironment.current())
        let result = try XCTUnwrap(scanned)

        XCTAssertEqual(result.findings.map(\.path), [cache.path])
    }

    func testSpotlightTimeoutDuringThisScanAddsDiscoveryNotice() async throws {
        let storeURL = tmp.appending(path: "store/project-roots.json")
        let discovery = ProjectRootDiscovery(storeURL: storeURL) {
            SpotlightSearchResult(urls: [], timedOut: true)
        }
        let rule = ProjectArtifactsRule(discovery: discovery, pathStore: emptyPathStore())

        let scanned = try await rule.customScanResult(environment: ScanEnvironment.current())
        let result = try XCTUnwrap(scanned)

        XCTAssertTrue(result.findings.isEmpty)
        let message = try XCTUnwrap(result.incompleteMessage)
        XCTAssertTrue(message.contains("Project discovery timed out"), message)
        let timedOut = await discovery.lastDiscoveryTimedOut
        XCTAssertTrue(timedOut)
    }

    func testSpotlightFinishingInTimeAddsNoNotice() async throws {
        let storeURL = tmp.appending(path: "store/project-roots.json")
        let discovery = ProjectRootDiscovery(storeURL: storeURL) {
            SpotlightSearchResult(urls: [], timedOut: false)
        }
        let rule = ProjectArtifactsRule(discovery: discovery, pathStore: emptyPathStore())

        let scanned = try await rule.customScanResult(environment: ScanEnvironment.current())
        let result = try XCTUnwrap(scanned)

        XCTAssertNil(result.incompleteMessage)
    }

    // MARK: Helpers

    private func makeArtifact(_ relativePath: String) throws -> URL {
        let dir = tmp.appending(path: relativePath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 1024).write(to: dir.appending(path: "content.bin"))
        let old = Date().addingTimeInterval(-10 * 86400)
        try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: dir.path)
        return dir
    }

    private func emptyPathStore() -> ProjectScanPathStore {
        ProjectScanPathStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    private func makeRule(
        manualRoots: [URL],
        timeBudget: TimeInterval = ProjectArtifactsRule.defaultTimeBudget,
        clock: TickingClock? = nil
    ) -> ProjectArtifactsRule {
        let storeURL = tmp.appending(path: "store-\(UUID().uuidString)/project-roots.json")
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = ProjectRootsStore(confirmed: [], excluded: [], manual: manualRoots.map(\.path), lastDiscoveredAt: Date())
        try? JSONEncoder().encode(store).write(to: storeURL)
        let discovery = ProjectRootDiscovery(storeURL: storeURL)
        guard let clock else {
            return ProjectArtifactsRule(discovery: discovery, pathStore: emptyPathStore(), timeBudget: timeBudget)
        }
        return ProjectArtifactsRule(
            discovery: discovery,
            pathStore: emptyPathStore(),
            timeBudget: timeBudget,
            now: { clock.now() }
        )
    }
}

/// Returns `start`, then advances by `step` on every call.
private final class TickingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSinceReferenceDate: 0)
    private let step: TimeInterval

    init(step: TimeInterval) {
        self.step = step
    }

    func now() -> Date {
        lock.withLock {
            defer { current = current.addingTimeInterval(step) }
            return current
        }
    }
}
