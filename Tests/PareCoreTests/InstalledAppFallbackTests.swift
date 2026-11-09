import XCTest
@testable import PareCore

/// LaunchServices is never real here: every lookup goes through a fake locator.
final class InstalledAppFallbackTests: XCTestCase {

    private final class FakeLocator: AppCopyLocating, @unchecked Sendable {
        private let lock = NSLock()
        private let known: [String: [URL]]
        private let delay: TimeInterval
        private var asked: [String] = []

        init(known: [String: [URL]] = [:], delay: TimeInterval = 0) {
            self.known = known
            self.delay = delay
        }

        var queries: [String] { lock.lock(); defer { lock.unlock() }; return asked }

        func appURLs(forBundleID bundleID: String) -> [URL] {
            lock.lock(); asked.append(bundleID); lock.unlock()
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            return known[bundleID] ?? []
        }
    }

    func testBudgetStopsFurtherLookupsOnceSpent() {
        let locator = FakeLocator(delay: 0.05)
        let index = InstalledAppIndex(namesByBundleID: [:], fallbackLocator: locator, fallbackBudgetSeconds: 0.01)

        XCTAssertNil(index.name(forBundleID: "com.acme.first"))
        XCTAssertNil(index.name(forBundleID: "com.acme.second"))
        XCTAssertNil(index.name(forBundleID: "com.acme.third"))

        XCTAssertEqual(locator.queries, ["com.acme.first"])
    }

    func testLookupsContinueWhileBudgetRemains() {
        let locator = FakeLocator()
        let index = InstalledAppIndex(namesByBundleID: [:], fallbackLocator: locator, fallbackBudgetSeconds: 60)

        _ = index.name(forBundleID: "com.acme.first")
        _ = index.name(forBundleID: "com.acme.second")

        XCTAssertEqual(locator.queries, ["com.acme.first", "com.acme.second"])
    }

    func testTrashCopyIsIgnored() {
        let trashed = URL(fileURLWithPath: "/Users/u/.Trash/Gone.app")
        let locator = FakeLocator(known: ["com.acme.gone": [trashed]])
        let index = InstalledAppIndex(namesByBundleID: [:], fallbackLocator: locator)

        XCTAssertNil(index.name(forBundleID: "com.acme.gone"))
    }

    func testLiveCopyWinsOverATrashCopy() {
        let trashed = URL(fileURLWithPath: "/Users/u/.Trash/Both.app")
        let live = URL(fileURLWithPath: "/nonexistent/pare/Applications/Both.app")
        let locator = FakeLocator(known: ["com.acme.both": [trashed, live]])
        let index = InstalledAppIndex(namesByBundleID: [:], fallbackLocator: locator)

        XCTAssertEqual(index.name(forBundleID: "com.acme.both"), "Both")
    }

    func testVolumeTrashesFolderIsIgnoredToo() {
        let trashed = URL(fileURLWithPath: "/Volumes/Data/.Trashes/501/Gone.app")
        let locator = FakeLocator(known: ["com.acme.gone": [trashed]])

        XCTAssertNil(InstalledAppIndex(namesByBundleID: [:], fallbackLocator: locator).name(forBundleID: "com.acme.gone"))
    }

    func testIndexThatLoadedNothingNeverAsksTheLocator() {
        let locator = FakeLocator(known: ["com.acme.x": [URL(fileURLWithPath: "/Applications/X.app")]])
        let index = InstalledAppIndex.load(
            roots: [URL(fileURLWithPath: "/definitely/not/here")],
            locator: locator,
            deadline: Date(timeIntervalSinceNow: 5)
        )

        XCTAssertNil(index.name(forBundleID: "com.acme.x"))
        XCTAssertEqual(locator.queries, [])
    }

    func testEmptyIndexConstantNeverFallsBack() {
        XCTAssertNil(InstalledAppIndex.empty.name(forBundleID: "com.acme.x"))
    }
}
