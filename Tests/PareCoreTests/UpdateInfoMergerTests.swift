import XCTest
@testable import PareCore

final class UpdateInfoMergerTests: XCTestCase {

    private func app(
        _ name: String,
        bundleID: String?,
        path: String? = nil,
        updateInfo: UpdateInfo? = nil
    ) -> InstalledApp {
        InstalledApp(
            name: name,
            bundleID: bundleID,
            version: "1.0",
            buildVersion: "1",
            path: path ?? "/Applications/\(name).app",
            sizeBytes: 0,
            installDate: nil,
            lastUsed: nil,
            isMAS: false,
            isSystemApp: false,
            updateInfo: updateInfo
        )
    }

    private func info(for bundleID: String) -> UpdateInfo {
        UpdateInfo(
            bundleID: bundleID,
            installedVersion: "1.0",
            availableVersion: "2.0",
            channel: .sparkle
        )
    }

    func testSnapshotCapturesOnlyAppsWithUpdateInfo() {
        let apps = [
            app("Slack", bundleID: "com.slack", updateInfo: info(for: "com.slack")),
            app("Notes", bundleID: "com.notes"),
        ]
        let snapshot = UpdateInfoMerger.Snapshot(apps: apps)
        XCTAssertEqual(snapshot.byBundleID.keys.sorted(), ["com.slack"])
        XCTAssertEqual(snapshot.byPath.keys.sorted(), ["/Applications/Slack.app"])
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertTrue(UpdateInfoMerger.Snapshot(apps: [app("Notes", bundleID: "com.notes")]).isEmpty)
    }

    func testMergeCarriesInfoByBundleIDThenPathFallback() {
        let previous = UpdateInfoMerger.Snapshot(apps: [
            app("Slack", bundleID: "com.slack", updateInfo: info(for: "com.slack")),
            app("NoBundle", bundleID: nil, path: "/Applications/NoBundle.app", updateInfo: info(for: "unknown")),
        ])
        let rescanned = [
            // Same bundle id, moved path — must match via bundle ID.
            app("Slack", bundleID: "com.slack", path: "/Users/x/Applications/Slack.app"),
            // No bundle id — must match via path.
            app("NoBundle", bundleID: nil, path: "/Applications/NoBundle.app"),
            app("Fresh", bundleID: "com.fresh"),
        ]
        let merged = UpdateInfoMerger.merge(scanned: rescanned, previous: previous)
        XCTAssertEqual(merged[0].updateInfo?.bundleID, "com.slack")
        XCTAssertEqual(merged[1].updateInfo?.bundleID, "unknown")
        XCTAssertNil(merged[2].updateInfo)
    }

    func testMergeClearsJustUpdatedApp() {
        let slack = app("Slack", bundleID: "com.slack", updateInfo: info(for: "com.slack"))
        let previous = UpdateInfoMerger.Snapshot(apps: [slack])
        let merged = UpdateInfoMerger.merge(
            scanned: [app("Slack", bundleID: "com.slack")],
            previous: previous,
            clearing: slack
        )
        XCTAssertNil(merged[0].updateInfo)
    }

    func testSnapshotToleratesDuplicateBundleIDs() {
        let a = app("Slack", bundleID: "com.slack", path: "/Applications/Slack.app", updateInfo: info(for: "com.slack"))
        let b = app("Slack Copy", bundleID: "com.slack", path: "/Applications/Slack Copy.app", updateInfo: info(for: "com.slack"))
        // Must not crash; first entry wins.
        let snapshot = UpdateInfoMerger.Snapshot(apps: [a, b])
        XCTAssertEqual(snapshot.byBundleID.count, 1)
        XCTAssertEqual(snapshot.byPath.count, 2)
    }
}
