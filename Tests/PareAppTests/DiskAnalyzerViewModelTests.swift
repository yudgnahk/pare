import Combine
import XCTest
import PareCore
@testable import PareApp

@MainActor
final class DiskAnalyzerViewModelTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "DiskAnalyzerViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeViewModel(
        findings: [ScanFinding] = [],
        coordinator: CleanupCoordinator = CleanupCoordinator()
    ) -> DiskAnalyzerViewModel {
        DiskAnalyzerViewModel(findingsProvider: { findings }, coordinator: coordinator)
    }

    private func makeFinding(path: String, sizeBytes: Int64 = 1_024, riskLevel: RiskLevel = .safe) -> ScanFinding {
        ScanFinding(
            category: .userCaches,
            riskLevel: riskLevel,
            reason: "test fixture",
            path: path,
            sizeBytes: sizeBytes,
            lastUsed: nil,
            confidence: 1.0
        )
    }

    private func waitUntilLoaded(_ vm: DiskAnalyzerViewModel) async {
        let loaded = expectation(description: "level loaded")
        let subscription = vm.$isLoading.first { !$0 }.sink { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 10)
        subscription.cancel()
    }

    // MARK: - Drill in/out updates crumbs

    func testDrillInAndOutUpdatesCrumbs() async throws {
        let subDir = tempRoot.appending(path: "Sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: subDir.appending(path: "file.txt"))

        let vm = makeViewModel()
        vm.open(root: tempRoot)
        await waitUntilLoaded(vm)

        XCTAssertEqual(vm.crumbs.count, 1)
        guard let subEntry = vm.visibleEntries.first(where: { $0.name == "Sub" }) else {
            return XCTFail("expected a Sub entry in the root level")
        }

        vm.open(subEntry)
        await waitUntilLoaded(vm)
        XCTAssertEqual(vm.crumbs.count, 2)
        XCTAssertEqual(vm.crumbs.last?.name, "Sub")

        vm.goUp()
        await waitUntilLoaded(vm)
        XCTAssertEqual(vm.crumbs.count, 1)
        XCTAssertEqual(vm.currentURL?.standardizedFileURL.path, tempRoot.standardizedFileURL.path)
    }

    // MARK: - Filter and sort pipeline

    func testFilterAndSortPipelineWiresIntoDiskTableQuery() async throws {
        try Data(repeating: 0, count: 10).write(to: tempRoot.appending(path: "alpha.txt"))
        try Data(repeating: 0, count: 10).write(to: tempRoot.appending(path: "beta.png"))
        try Data(repeating: 0, count: 10).write(to: tempRoot.appending(path: "gamma.zip"))
        try FileManager.default.createDirectory(
            at: tempRoot.appending(path: "delta"), withIntermediateDirectories: true
        )

        let vm = makeViewModel()
        vm.open(root: tempRoot)
        await waitUntilLoaded(vm)

        XCTAssertEqual(vm.visibleEntries.map(\.name), ["alpha.txt", "beta.png", "delta", "gamma.zip"])

        vm.search = "be"
        XCTAssertEqual(vm.visibleEntries.map(\.name), ["beta.png"])
        vm.search = ""

        vm.kindFilter = .image
        XCTAssertEqual(vm.visibleEntries.map(\.name), ["beta.png"])
    }

    // MARK: - Add-to-review dedup

    func testAddToReviewDedupsByPath() {
        let sub1 = tempRoot.appending(path: "CacheDir/sub1").path
        let sub2 = tempRoot.appending(path: "CacheDir/sub2").path
        let finding1 = makeFinding(path: sub1, sizeBytes: 100)
        let finding2 = makeFinding(path: sub2, sizeBytes: 200)
        let vm = makeViewModel(findings: [finding1, finding2])
        let cacheDirEntry = DiskEntry(
            id: tempRoot.appending(path: "CacheDir").path,
            url: tempRoot.appending(path: "CacheDir"),
            name: "CacheDir",
            isDirectory: true,
            isPackage: false,
            sizeBytes: 300,
            itemCount: 2,
            modified: nil,
            kind: .folder
        )

        vm.addToReview(cacheDirEntry)
        XCTAssertEqual(vm.reviewTrayCount, 2)
        XCTAssertEqual(vm.reviewTrayTotalBytes, 300)

        // Re-adding the same entry must not double-count its findings.
        vm.addToReview(cacheDirEntry)
        XCTAssertEqual(vm.reviewTrayCount, 2)
        XCTAssertEqual(vm.reviewTrayTotalBytes, 300)
    }

    func testReviewTrayDropsNestedFindingsAndKeepsParentTotal() {
        let parent = makeFinding(path: "/Users/k/Library/Caches/App", sizeBytes: 500)
        let child = makeFinding(path: "/Users/k/Library/Caches/App/nested", sizeBytes: 100)
        let vm = makeViewModel(findings: [child, parent])
        let entry = DiskEntry(
            id: "/Users/k/Library/Caches/App",
            url: URL(fileURLWithPath: "/Users/k/Library/Caches/App"),
            name: "App",
            isDirectory: true,
            isPackage: false,
            sizeBytes: 600,
            itemCount: 2,
            modified: nil,
            kind: .folder
        )

        vm.addToReview(entry)

        XCTAssertEqual(vm.reviewTrayCount, 1)
        XCTAssertEqual(vm.reviewTrayFindings.first?.path, parent.path)
        XCTAssertEqual(vm.reviewTrayTotalBytes, parent.sizeBytes)
    }

    func testRefreshClearsSelection() {
        let vm = makeViewModel()
        vm.selection = ["/Users/k/Library/Caches/a"]
        vm.open(root: tempRoot)
        vm.selection = ["/Users/k/Library/Caches/a"]

        vm.refresh()

        XCTAssertTrue(vm.selection.isEmpty)
    }

    func testRapidNavigationKeepsMostRecentDirectory() async throws {
        let first = tempRoot.appending(path: "first")
        let last = tempRoot.appending(path: "last")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: last, withIntermediateDirectories: true)
        for index in 0..<250 {
            try Data([0]).write(to: first.appending(path: "stale-\(index).txt"))
        }
        try Data([0]).write(to: last.appending(path: "current.txt"))

        let vm = makeViewModel()
        vm.open(root: first)
        vm.open(root: last)
        await waitUntilLoaded(vm)

        XCTAssertEqual(vm.currentURL?.standardizedFileURL, last.standardizedFileURL)
        XCTAssertEqual(vm.visibleEntries.map(\.name), ["current.txt"])
    }

    func testConfirmDropsTrayItemsMissingFromLatestScan() {
        let path = "/Users/k/Library/Caches/stale"
        let finding = makeFinding(path: path)
        var latestFindings = [finding]
        let coordinator = CleanupCoordinator(engine: CleanupEngine())
        let vm = DiskAnalyzerViewModel(findingsProvider: { latestFindings }, coordinator: coordinator)
        let entry = DiskEntry(
            id: path,
            url: URL(fileURLWithPath: path),
            name: "stale",
            isDirectory: true,
            isPackage: false,
            sizeBytes: finding.sizeBytes,
            itemCount: 1,
            modified: nil,
            kind: .folder
        )
        vm.addToReview(entry)
        vm.requestReviewCleanup()
        latestFindings = []

        vm.confirmReviewCleanup()

        XCTAssertEqual(vm.cleanupState, .idle)
        XCTAssertEqual(vm.reviewTrayCount, 0)
    }

    // MARK: - .notCandidate and .noScan never add

    func testNotCandidateAndNoScanNeverAddToTray() {
        let unrelated = makeFinding(path: "/Users/k/Downloads/thing")
        let entry = DiskEntry(
            id: "/Users/k/Desktop",
            url: URL(fileURLWithPath: "/Users/k/Desktop"),
            name: "Desktop",
            isDirectory: true,
            isPackage: false,
            sizeBytes: 10,
            itemCount: 1,
            modified: nil,
            kind: .folder
        )

        let noScanVM = makeViewModel(findings: [])
        let noScanResolution = noScanVM.addToReview(entry)
        guard case .noScan = noScanResolution else { return XCTFail("expected .noScan") }
        XCTAssertEqual(noScanVM.reviewTrayCount, 0)

        let notCandidateVM = makeViewModel(findings: [unrelated])
        let notCandidateResolution = notCandidateVM.addToReview(entry)
        guard case .notCandidate = notCandidateResolution else { return XCTFail("expected .notCandidate") }
        XCTAssertEqual(notCandidateVM.reviewTrayCount, 0)
    }

    // MARK: - Tray total

    func testReviewTrayTotalsBytesAndReviewRiskCount() {
        let safeFinding = makeFinding(path: "/tmp/a", sizeBytes: 1_000, riskLevel: .safe)
        let reviewFinding = makeFinding(path: "/tmp/b", sizeBytes: 2_000, riskLevel: .review)
        let vm = makeViewModel(findings: [safeFinding, reviewFinding])

        vm.addToReview(DiskEntry(
            id: "/tmp/a", url: URL(fileURLWithPath: "/tmp/a"), name: "a", isDirectory: false,
            isPackage: false, sizeBytes: 1_000, itemCount: 1, modified: nil, kind: .other
        ))
        vm.addToReview(DiskEntry(
            id: "/tmp/b", url: URL(fileURLWithPath: "/tmp/b"), name: "b", isDirectory: false,
            isPackage: false, sizeBytes: 2_000, itemCount: 1, modified: nil, kind: .other
        ))

        XCTAssertEqual(vm.reviewTrayCount, 2)
        XCTAssertEqual(vm.reviewTrayTotalBytes, 3_000)
        XCTAssertEqual(vm.reviewTrayReviewRiskCount, 1)
    }

    // MARK: - Confirm hands the coordinator the tray's findings

    func testConfirmHandsCoordinatorTheTrayFindings() async throws {
        let fixture = try HermeticCleanupFixture(name: "DiskAnalyzerViewModelTests")
        defer { fixture.remove() }
        let tempFile = try fixture.makeFile(named: "trashable.bin")
        let coordinator = CleanupCoordinator(engine: fixture.makeEngine())
        let finding = makeFinding(path: tempFile.path, sizeBytes: 4)
        let vm = makeViewModel(findings: [finding], coordinator: coordinator)

        vm.addToReview(DiskEntry(
            id: tempFile.path, url: tempFile, name: "trashable.bin", isDirectory: false,
            isPackage: false, sizeBytes: 4, itemCount: 1, modified: nil, kind: .other
        ))
        XCTAssertEqual(vm.reviewTrayCount, 1)

        vm.requestReviewCleanup()
        XCTAssertEqual(coordinator.pending, .diskReview)
        vm.confirmReviewCleanup()
        await waitForCleanupToFinish(coordinator)

        XCTAssertEqual(coordinator.state, .done(bytesFreed: 4, skippedCount: 0))
        XCTAssertTrue((try? fixture.store.loadAll())?.isEmpty == false)
    }

    // MARK: - Pending requests are screen-scoped

    /// A Smart Scan request must never be confirmed with the tray's findings.
    func testConfirmReviewCleanupIgnoresSmartScanSelectedRequest() {
        let path = "/Users/k/Library/Caches/tray"
        let finding = makeFinding(path: path)
        let coordinator = CleanupCoordinator(engine: CleanupEngine())
        let vm = makeViewModel(findings: [finding], coordinator: coordinator)
        vm.addToReview(DiskEntry(
            id: path, url: URL(fileURLWithPath: path), name: "tray", isDirectory: true,
            isPackage: false, sizeBytes: finding.sizeBytes, itemCount: 1, modified: nil, kind: .folder
        ))
        coordinator.request(.selected)

        XCTAssertNil(vm.pendingCleanup)
        vm.confirmReviewCleanup()
        vm.pendingCleanup = nil
        vm.cancelPendingCleanup()

        XCTAssertEqual(coordinator.pending, .selected)
        XCTAssertEqual(coordinator.state, .confirming)
        XCTAssertEqual(vm.reviewTrayCount, 1)
    }

    /// Escape nils the sheet binding before `onDismiss` runs; the state must still return to idle.
    func testEscapeDismissResetsDiskReviewRequestToIdle() {
        let path = "/Users/k/Library/Caches/tray"
        let finding = makeFinding(path: path)
        let coordinator = CleanupCoordinator(engine: CleanupEngine())
        let vm = makeViewModel(findings: [finding], coordinator: coordinator)
        vm.addToReview(DiskEntry(
            id: path, url: URL(fileURLWithPath: path), name: "tray", isDirectory: true,
            isPackage: false, sizeBytes: finding.sizeBytes, itemCount: 1, modified: nil, kind: .folder
        ))
        vm.requestReviewCleanup()
        XCTAssertEqual(vm.pendingCleanup, .diskReview)

        vm.pendingCleanup = nil
        vm.cancelPendingCleanup()

        XCTAssertNil(coordinator.pending)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(vm.reviewTrayCount, 1)
    }

    /// Any cleanup on the shared coordinator must drop cached levels so trashed items disappear.
    func testCleanupCompletionReloadsLevelWithoutTrashedItem() async throws {
        let fixture = try HermeticCleanupFixture(name: "DiskAnalyzerViewModelTests-reload")
        defer { fixture.remove() }
        let trashable = try fixture.makeFile(named: "trashable.bin")
        _ = try fixture.makeFile(named: "keeper.bin")
        let coordinator = CleanupCoordinator(engine: fixture.makeEngine())
        let vm = makeViewModel(findings: [makeFinding(path: trashable.path, sizeBytes: 4)], coordinator: coordinator)
        vm.open(root: fixture.cacheDirectory)
        await waitUntilLoaded(vm)
        let entry = try XCTUnwrap(vm.visibleEntries.first { $0.name == "trashable.bin" })

        let reloaded = expectation(description: "level reloaded without the trashed item")
        let subscription = vm.$level
            .compactMap { $0 }
            .first { level in !level.entries.contains { $0.name == "trashable.bin" } }
            .sink { _ in reloaded.fulfill() }
        vm.addToReview(entry)
        vm.requestReviewCleanup()
        vm.confirmReviewCleanup()
        await fulfillment(of: [reloaded], timeout: 10)
        subscription.cancel()

        XCTAssertEqual(vm.visibleEntries.map(\.name), ["keeper.bin"])
        XCTAssertEqual(vm.reviewTrayCount, 0)
    }

    /// Completion drops trashed and no-longer-scanned tray items and clears every cached level, not just the current one.
    func testCleanupCompletionPrunesTrayAndClearsLevelCache() async throws {
        let fixture = try HermeticCleanupFixture(name: "DiskAnalyzerViewModelTests-prune")
        defer { fixture.remove() }
        let files = try ["trashable.bin", "keeper.bin", "stale.bin"].map { try fixture.makeFile(named: $0) }
        let findings = files.map { makeFinding(path: $0.path, sizeBytes: 4) }
        var latestFindings = findings
        let coordinator = CleanupCoordinator(engine: fixture.makeEngine())
        let vm = DiskAnalyzerViewModel(findingsProvider: { latestFindings }, coordinator: coordinator)
        for file in files {
            vm.addToReview(DiskEntry(
                id: file.path, url: file, name: file.lastPathComponent, isDirectory: false,
                isPackage: false, sizeBytes: 4, itemCount: 1, modified: nil, kind: .other
            ))
        }
        XCTAssertEqual(vm.reviewTrayCount, 3)

        // Cache the folder's level, then go up so it stays cached but is no longer current.
        let folderName = fixture.cacheDirectory.lastPathComponent
        vm.open(root: fixture.cacheDirectory.deletingLastPathComponent())
        await waitUntilLoaded(vm)
        let folderEntry = try XCTUnwrap(vm.visibleEntries.first { $0.name == folderName })
        vm.open(folderEntry)
        await waitUntilLoaded(vm)
        vm.goUp()
        await waitUntilLoaded(vm)

        latestFindings = [findings[0], findings[1]]
        let reloaded = expectation(description: "parent level reloaded after cleanup")
        let subscription = vm.$level
            .compactMap { $0?.entries.first { $0.name == folderName }?.itemCount }
            .first { $0 == 2 }
            .sink { _ in reloaded.fulfill() }
        coordinator.confirm(.selected, findings: [findings[0]])
        await fulfillment(of: [reloaded], timeout: 10)
        subscription.cancel()

        XCTAssertEqual(vm.reviewTrayFindings.map(\.path), [files[1].path])
        let reloadedFolderEntry = try XCTUnwrap(vm.visibleEntries.first { $0.name == folderName })
        vm.open(reloadedFolderEntry)
        await waitUntilLoaded(vm)
        XCTAssertEqual(vm.visibleEntries.map(\.name).sorted(), ["keeper.bin", "stale.bin"])
    }
}
