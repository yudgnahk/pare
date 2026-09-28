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
        for _ in 0..<200 where vm.isLoading {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
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
        let storeDir = FileManager.default.temporaryDirectory
            .appending(path: "DiskAnalyzerViewModelTests-store-\(UUID().uuidString)")
        let fixtureDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/Pare-DiskAnalyzerViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let tempFile = fixtureDirectory.appending(path: "trashable.bin")
        try Data("test".utf8).write(to: tempFile)
        defer {
            try? FileManager.default.removeItem(at: storeDir)
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }

        let store = CleanupTransactionStore(directory: storeDir)
        let engine = CleanupEngine(store: store, exclusionsProvider: { .empty }, now: { .distantFuture })
        let coordinator = CleanupCoordinator(engine: engine)
        let finding = makeFinding(path: tempFile.path, sizeBytes: 4)
        let vm = makeViewModel(findings: [finding], coordinator: coordinator)

        vm.addToReview(DiskEntry(
            id: tempFile.path, url: tempFile, name: "trashable.bin", isDirectory: false,
            isPackage: false, sizeBytes: 4, itemCount: 1, modified: nil, kind: .other
        ))
        XCTAssertEqual(vm.reviewTrayCount, 1)

        vm.confirmReviewCleanup()

        for _ in 0..<50 where coordinator.isCleaning {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(coordinator.state, .done(bytesFreed: 4, skippedCount: 0))
        XCTAssertTrue((try? store.loadAll())?.isEmpty == false)
    }
}
