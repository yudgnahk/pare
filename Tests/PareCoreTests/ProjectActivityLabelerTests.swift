import XCTest
@testable import PareCore

/// Project activity labels: what counts as active, the copy, and the time budgets.
final class ProjectActivityLabelerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let home = URL(fileURLWithPath: "/nonexistent/pare-activity/home")

    private func edit(daysAgo days: Double) -> ProjectActivityLabel {
        ProjectActivityLabel(newestEditDate: now.addingTimeInterval(-days * 86_400))
    }

    func testActiveWithinThreeDaysIdleAfterAndUnknownIsActive() {
        let cases: [(name: String, label: ProjectActivityLabel, active: Bool)] = [
            ("edited an hour ago", ProjectActivityLabel(newestEditDate: now.addingTimeInterval(-3_600)), true),
            ("edited 2 days ago", edit(daysAgo: 2), true),
            ("edited exactly 3 days ago", edit(daysAgo: 3), true),
            ("edited 5 days ago", edit(daysAgo: 5), false),
            ("clock skew, edited in the future", edit(daysAgo: -1), true),
            ("unknown", ProjectActivityLabel(newestEditDate: nil), true),
        ]
        for testCase in cases {
            XCTAssertEqual(testCase.label.isActive(now: now), testCase.active, testCase.name)
        }
    }

    func testTextNamesTodayAndIdleDaysAndStaysSilentWhenUnknown() {
        let cases: [(name: String, label: ProjectActivityLabel, text: String?)] = [
            ("an hour ago", ProjectActivityLabel(newestEditDate: now.addingTimeInterval(-3_600)), "Active today"),
            ("1 day", edit(daysAgo: 1.2), "Idle 1 day"),
            ("5 days", edit(daysAgo: 5.5), "Idle 5 days"),
            ("future", edit(daysAgo: -1), "Active today"),
            ("unknown", ProjectActivityLabel(newestEditDate: nil), nil),
        ]
        for testCase in cases {
            XCTAssertEqual(testCase.label.text(now: now), testCase.text, testCase.name)
        }
    }

    func testEveryRootGetsALabelFromTheProbe() {
        let edited = now.addingTimeInterval(-86_400 * 5)
        let labels = ProjectActivityLabeler.labels(
            forRoots: ["/p/a", "/p/b", "/p/a"], homeDirectory: home, now: { Date(timeIntervalSince1970: 1_800_000_000) },
            probe: { root, _ in root.path == "/p/a" ? edited : nil }
        )

        XCTAssertEqual(labels, [
            "/p/a": ProjectActivityLabel(newestEditDate: edited),
            "/p/b": ProjectActivityLabel(newestEditDate: nil),
        ])
    }

    func testProbeGetsAtMostThePerProjectBudget() {
        let seen = DeadlineLog()
        _ = ProjectActivityLabeler.labels(
            forRoots: ["/p/a"], homeDirectory: home, now: { Date(timeIntervalSince1970: 1_800_000_000) },
            probe: { _, deadline in seen.append(deadline); return nil }
        )

        XCTAssertEqual(seen.values, [Date(timeIntervalSince1970: 1_800_000_000 + ProjectActivityLabeler.perProjectSeconds)])
    }

    func testRootsReachedAfterTheOverallBudgetAreUnknownWithoutProbing() {
        let clock = FakeClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let probed = DeadlineLog()
        let edited = Date(timeIntervalSince1970: 1_700_000_000)

        let labels = ProjectActivityLabeler.labels(
            forRoots: ["/p/a", "/p/b", "/p/c"], homeDirectory: home,
            now: { clock.now() }, perProjectSeconds: 2, totalSeconds: 3,
            probe: { _, deadline in
                probed.append(deadline)
                clock.advance(2)
                return edited
            }
        )

        XCTAssertEqual(probed.values.count, 2)
        XCTAssertEqual(labels["/p/a"]?.newestEditDate, edited)
        XCTAssertEqual(labels["/p/b"]?.newestEditDate, edited)
        XCTAssertEqual(labels["/p/c"], ProjectActivityLabel(newestEditDate: nil))
        XCTAssertEqual(probed.values.last, Date(timeIntervalSince1970: 1_800_000_003), "deadline is capped by the overall budget")
    }

    func testDefaultProbeTreatsAMissingFolderAsUnknown() {
        let labels = ProjectActivityLabeler.labels(forRoots: ["/nonexistent/pare-activity/proj"], homeDirectory: home)

        XCTAssertEqual(labels["/nonexistent/pare-activity/proj"], ProjectActivityLabel(newestEditDate: nil))
    }
}

private final class DeadlineLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Date] = []

    func append(_ date: Date) { lock.lock(); storage.append(date); lock.unlock() }
    var values: [Date] { lock.lock(); defer { lock.unlock() }; return storage }
}

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) { current = start }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock() }
}
