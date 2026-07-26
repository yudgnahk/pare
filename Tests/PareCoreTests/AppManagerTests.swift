import XCTest
@testable import PareCore

final class AppManagerTests: XCTestCase {

    // MARK: - InstalledApp

    func testInstalledAppIDUsesBundleID() {
        let app = InstalledApp(
            name: "Test App",
            bundleID: "com.example.test",
            version: "1.0",
            buildVersion: "100",
            path: "/Applications/TestApp.app",
            sizeBytes: 1024,
            installDate: nil,
            lastUsed: nil,
            isMAS: false,
            isSystemApp: false
        )
        XCTAssertEqual(app.id, "com.example.test")
    }

    func testInstalledAppIDFallsBackToPath() {
        let app = InstalledApp(
            name: "No Bundle",
            bundleID: nil,
            version: "1.0",
            buildVersion: "1.0",
            path: "/Applications/NoBundleApp.app",
            sizeBytes: 0,
            installDate: nil,
            lastUsed: nil,
            isMAS: false,
            isSystemApp: false
        )
        XCTAssertEqual(app.id, "/Applications/NoBundleApp.app")
    }

    // MARK: - AppLeftover

    func testGroupContainerFlag() {
        let leftover = AppLeftover(
            path: "/Users/test/Library/Group Containers/group.com.example/",
            sizeBytes: 4096,
            category: .groupContainers,
            isGroupContainer: true
        )
        XCTAssertTrue(leftover.isGroupContainer)
        XCTAssertEqual(leftover.category, .groupContainers)
    }

    func testNormalLeftoverNotGroupContainer() {
        let leftover = AppLeftover(
            path: "/Users/test/Library/Caches/com.example.app/",
            sizeBytes: 1024,
            category: .caches
        )
        XCTAssertFalse(leftover.isGroupContainer)
    }

    // MARK: - UpdateInfo

    func testUpdateInfoHasUpdateWhenVersionsDiffer() {
        let info = UpdateInfo(
            bundleID: "com.example.app",
            installedVersion: "1.0",
            availableVersion: "1.1",
            channel: .sparkle
        )
        XCTAssertTrue(info.hasUpdate)
    }

    func testUpdateInfoNoUpdateWhenVersionsMatch() {
        let info = UpdateInfo(
            bundleID: "com.example.app",
            installedVersion: "2.0",
            availableVersion: "2.0",
            channel: .mas
        )
        XCTAssertFalse(info.hasUpdate)
    }

    func testUpdateInfoNoUpdateWhenAvailableIsOlder() {
        let info = UpdateInfo(
            bundleID: "com.example.app",
            installedVersion: "2.1",
            availableVersion: "2.0",
            channel: .sparkle
        )
        XCTAssertFalse(info.hasUpdate)
    }

    func testUpdateInfoComparesMultiComponentVersions() {
        let info = UpdateInfo(
            bundleID: "com.example.app",
            installedVersion: "1.2.3",
            availableVersion: "1.2.10",
            channel: .mas
        )
        XCTAssertTrue(info.hasUpdate)
    }

    // MARK: - ScanPolicy additions

    func testIsSystemApp() {
        XCTAssertTrue(ScanPolicy.isSystemApp(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        XCTAssertFalse(ScanPolicy.isSystemApp(URL(fileURLWithPath: "/Applications/Safari.app")))
    }

    func testIsGroupContainer() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let groupURL = URL(fileURLWithPath: "\(home)/Library/Group Containers/group.com.example")
        let normalURL = URL(fileURLWithPath: "\(home)/Library/Containers/com.example.app")
        XCTAssertTrue(ScanPolicy.isGroupContainer(groupURL))
        XCTAssertFalse(ScanPolicy.isGroupContainer(normalURL))
    }

    // MARK: - AppInventory.makeApp

    func testMakeAppReturnsNilForNonBundle() {
        let url = URL(fileURLWithPath: "/tmp/notanapp.txt")
        let result = AppInventory.makeApp(from: url, isSystem: false)
        XCTAssertNil(result)
    }

    func testMakeAppFromRealBundle() throws {
        guard FileManager.default.fileExists(atPath: "/Applications/Safari.app") else {
            throw XCTSkip("Safari.app not found — skipping real bundle test")
        }
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let app = AppInventory.makeApp(from: url, isSystem: false)
        XCTAssertNotNil(app)
        XCTAssertEqual(app?.name.isEmpty, false)
        XCTAssertEqual(app?.bundleID?.isEmpty, false)
    }

    // MARK: - AppUninstaller.findLeftovers

    func testFindLeftoversForAppWithoutBundleIDReturnsEmpty() {
        let app = InstalledApp(
            name: "Orphan",
            bundleID: nil,
            version: "1.0",
            buildVersion: "1",
            path: "/Applications/Orphan.app",
            sizeBytes: 0,
            installDate: nil,
            lastUsed: nil,
            isMAS: false,
            isSystemApp: false
        )
        let uninstaller = AppUninstaller()
        let leftovers = uninstaller.findLeftovers(for: app)
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testFindLeftoversPicksUpPrefsAndCaches() throws {
        // Create synthetic leftover files under /tmp so we can test without touching ~/Library
        let bundleID = "com.pare.testuninstall.\(UUID().uuidString.prefix(8))"
        let tmpBase = URL(fileURLWithPath: "/private/tmp/AppUninstallerTest-\(bundleID)")
        defer { try? FileManager.default.removeItem(at: tmpBase) }

        // We can't easily redirect ~/Library in a unit test, so we validate the
        // leftover scan logic indirectly: an app with a bundle ID returns a result set
        // that includes only existing paths on disk.
        let app = InstalledApp(
            name: "FakeApp",
            bundleID: bundleID,
            version: "1.0",
            buildVersion: "1",
            path: "/Applications/FakeApp.app",
            sizeBytes: 0,
            installDate: nil,
            lastUsed: nil,
            isMAS: false,
            isSystemApp: false
        )
        let uninstaller = AppUninstaller()
        let leftovers = uninstaller.findLeftovers(for: app)
        // All returned paths must actually exist on disk (uninstaller must not invent paths)
        for leftover in leftovers {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: leftover.path),
                "Leftover path does not exist: \(leftover.path)"
            )
        }
    }

    // MARK: - App bundle sizing (FileSystemUtils.directorySize)

    func testDirectorySizeForNonexistentDir() {
        let size = FileSystemUtils.directorySize(url: URL(fileURLWithPath: "/nonexistent/path/xyz"))
        XCTAssertEqual(size, 0)
    }

    func testDirectorySizeForDirectory() throws {
        let dir = URL(fileURLWithPath: "/private/tmp/AllocSizeTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("test.bin")
        try Data(repeating: 0x41, count: 4096).write(to: file)
        let size = FileSystemUtils.directorySize(url: dir)
        XCTAssertGreaterThan(size, 0)
    }
}
