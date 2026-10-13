import XCTest
@testable import PareCore

/// Discovery refreshes on a TTL (or when marked stale) instead of running only once per install.
final class ProjectRootDiscoveryRefreshTests: XCTestCase {

    private var tmp: URL!
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "pare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testDiscoverIfNeededRunsByLastDiscoveryAge() async {
        let hour: TimeInterval = 3600
        let cases: [(name: String, last: Date?, expectedRuns: Int)] = [
            ("never discovered", nil, 1),
            ("one hour old", now.addingTimeInterval(-hour), 0),
            ("just under the interval", now.addingTimeInterval(-ProjectRootDiscovery.refreshInterval + 1), 0),
            ("exactly the interval", now.addingTimeInterval(-ProjectRootDiscovery.refreshInterval), 1),
            ("25 hours old", now.addingTimeInterval(-25 * hour), 1),
            ("clock moved backwards", now.addingTimeInterval(hour), 1),
        ]
        for testCase in cases {
            let search = SearchStub()
            let discovery = makeDiscovery(lastDiscoveredAt: testCase.last, search: search)

            let ran = await discovery.discoverIfNeeded()
            _ = await discovery.discoverIfNeeded()

            XCTAssertEqual(search.calls, testCase.expectedRuns, testCase.name)
            XCTAssertEqual(ran, testCase.expectedRuns == 1, testCase.name)
        }
    }

    func testMarkStaleForcesTheNextDiscovery() async {
        let search = SearchStub()
        let discovery = makeDiscovery(lastDiscoveredAt: now.addingTimeInterval(-60), search: search)

        await discovery.markStale()
        let ran = await discovery.discoverIfNeeded()
        _ = await discovery.discoverIfNeeded()

        XCTAssertTrue(ran)
        XCTAssertEqual(search.calls, 1, "stale flag clears after one refresh")
    }

    func testConcurrentCallersShareOneSearch() async {
        let search = SearchStub(delayNanoseconds: 200_000_000)
        let discovery = makeDiscovery(lastDiscoveredAt: nil, search: search)

        async let first = discovery.discoverIfNeeded()
        async let second = discovery.discoverIfNeeded()
        let results = await [first, second]

        XCTAssertEqual(search.calls, 1)
        XCTAssertEqual(results, [true, true], "both callers saw discovery run during their scan")
    }

    func testTimedOutDiscoveryStillAdvancesTheTimestamp() async {
        let search = SearchStub(timedOut: true)
        let discovery = makeDiscovery(lastDiscoveredAt: nil, search: search)

        _ = await discovery.discoverIfNeeded()
        let timedOut = await discovery.lastDiscoveryTimedOut
        let date = await discovery.discoveryDate
        _ = await discovery.discoverIfNeeded()

        XCTAssertTrue(timedOut)
        XCTAssertEqual(date, now)
        XCTAssertEqual(search.calls, 1, "a timed-out search must not re-run on every scan")
    }

    func testRediscoveryKeepsExclusionsAndConfirmsNewRoots() async throws {
        let optedOut = tmp.appending(path: "Projects/old")
        let fresh = tmp.appending(path: "Projects/new")
        for dir in [optedOut, fresh] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let search = SearchStub(urls: [
            optedOut.appending(path: "Package.swift"),
            fresh.appending(path: "Package.swift"),
        ])
        let discovery = makeDiscovery(
            lastDiscoveredAt: now.addingTimeInterval(-25 * 3600),
            excluded: [optedOut.path],
            search: search
        )

        _ = await discovery.discoverIfNeeded()

        let confirmed = await discovery.confirmedRoots().map(\.path)
        XCTAssertEqual(confirmed, [fresh.path])
        let all = await discovery.allDiscoveredRoots
        XCTAssertEqual(all.map(\.url.path), [fresh.path, optedOut.path])
        XCTAssertEqual(all.map(\.confirmed), [true, false])
    }

    // MARK: Helpers

    private func makeDiscovery(
        lastDiscoveredAt: Date?,
        excluded: [String] = [],
        search: SearchStub
    ) -> ProjectRootDiscovery {
        let storeURL = tmp.appending(path: "store-\(UUID().uuidString)/project-roots.json")
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = ProjectRootsStore(confirmed: [], excluded: excluded, manual: [], lastDiscoveredAt: lastDiscoveredAt)
        try? JSONEncoder().encode(store).write(to: storeURL)
        let fixedNow = now
        return ProjectRootDiscovery(
            storeURL: storeURL,
            spotlightSearch: { await search.run() },
            now: { fixedNow }
        )
    }
}

/// Counts Spotlight searches and returns canned hits, optionally after a delay.
final class SearchStub: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let urls: [URL]
    private let timedOut: Bool
    private let delayNanoseconds: UInt64

    init(urls: [URL] = [], timedOut: Bool = false, delayNanoseconds: UInt64 = 0) {
        self.urls = urls
        self.timedOut = timedOut
        self.delayNanoseconds = delayNanoseconds
    }

    var calls: Int { lock.withLock { count } }

    func run() async -> SpotlightSearchResult {
        recordCall()
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return SpotlightSearchResult(urls: urls, timedOut: timedOut)
    }

    private func recordCall() {
        lock.withLock { count += 1 }
    }
}
