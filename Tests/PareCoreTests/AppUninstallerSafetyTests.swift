import XCTest
@testable import PareCore

final class AppUninstallerSafetyTests: XCTestCase {

    // MARK: - Fixtures

    private var root: URL!
    private var home: URL { root.appendingPathComponent("home") }
    private var systemLibrary: URL { root.appendingPathComponent("system-library") }
    private var trashDir: URL { root.appendingPathComponent("trash") }
    private var library: URL { home.appendingPathComponent("Library") }

    private let chromeID = "com.google.Chrome"

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppUninstallerSafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private struct StubRunningApps: RunningAppsProviding {
        let apps: [RunningApp]
        func runningApps() -> [RunningApp] { apps }
    }

    private actor StubUnloader: LaunchAgentUnloading {
        let outcome: LaunchAgentUnloadOutcome
        private(set) var unloaded: [String] = []
        init(outcome: LaunchAgentUnloadOutcome) { self.outcome = outcome }
        func unload(plistAt url: URL) async -> LaunchAgentUnloadOutcome {
            unloaded.append(url.lastPathComponent)
            return outcome
        }
    }

    private actor CallLog {
        private(set) var calls: [[String]] = []
        func append(_ call: [String]) { calls.append(call) }
    }

    private func makeApp(bundleID: String? = "com.google.Chrome", name: String = "Google Chrome") throws -> InstalledApp {
        let appURL = root.appendingPathComponent("Applications/\(name).app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        return InstalledApp(
            name: name,
            bundleID: bundleID,
            version: "1.0",
            buildVersion: "1",
            path: appURL.path,
            sizeBytes: 10,
            installDate: nil,
            lastUsed: nil,
            isMAS: false,
            isSystemApp: false
        )
    }

    @discardableResult
    private func makeFile(_ url: URL, contents: String = "x") throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @discardableResult
    private func makeDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try makeFile(url.appendingPathComponent("data.bin"))
        return url
    }

    private func makeUninstaller(
        unloader: any LaunchAgentUnloading = StubUnloader(outcome: .notLoaded),
        running: [RunningApp] = [],
        exclusions: ExclusionList? = .empty
    ) -> AppUninstaller {
        let trashDir = self.trashDir
        return AppUninstaller(
            home: home,
            systemLibrary: systemLibrary,
            launchAgents: unloader,
            runningApps: StubRunningApps(apps: running),
            exclusions: { exclusions },
            trashItem: { url in
                let destination = trashDir.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            },
            transactionStore: CleanupTransactionStore(directory: root.appendingPathComponent("transactions"))
        )
    }

    private func names(_ leftovers: [AppLeftover]) -> Set<String> {
        Set(leftovers.map { URL(fileURLWithPath: $0.path).lastPathComponent })
    }

    // MARK: - Name matching

    func testBundleIDNameMatchRespectsDotBoundaries() {
        let cases: [(String, BundleIDNameMatch)] = [
            ("com.google.Chrome.plist", .exact),
            ("com.google.Chrome", .exact),
            ("COM.GOOGLE.CHROME.PLIST", .exact),
            ("com.google.Chrome.canary.plist", .derived),
            ("com.google.Chromebook.plist", .none),
            ("com.google.Chrome-helper.plist", .none),
            ("org.com.google.Chrome.plist", .none),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(ScanPolicy.bundleIDNameMatch(name, bundleID: chromeID), expected, name)
        }
    }

    func testGroupContainerMatchesWholeComponentsOnly() {
        let cases: [(String, Bool)] = [
            ("ABCDE12345.com.foo", true),
            ("group.com.foo.shared", true),
            ("com.foo", true),
            ("ABCDE12345.com.foobar", false),
            ("ABCDE12345.xcom.foo", false),
            ("com", false),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(ScanPolicy.groupContainerNameMatches(name, bundleID: "com.foo"), expected, name)
        }
    }

    func testMoreSpecificInstalledAppClaimsItsOwnFiles() {
        let canary = "com.google.Chrome.canary.plist"
        XCTAssertTrue(ScanPolicy.isLeftoverClaimedByOtherApp(
            canary, bundleID: chromeID, otherBundleIDs: ["com.google.Chrome.canary"], isGroupContainer: false
        ))
        XCTAssertFalse(ScanPolicy.isLeftoverClaimedByOtherApp(
            canary, bundleID: chromeID, otherBundleIDs: ["com.google"], isGroupContainer: false
        ))
        XCTAssertFalse(ScanPolicy.isLeftoverClaimedByOtherApp(
            canary, bundleID: chromeID, otherBundleIDs: [], isGroupContainer: false
        ))
        XCTAssertTrue(ScanPolicy.isLeftoverClaimedByOtherApp(
            "ABCDE12345.com.foo.pro", bundleID: "com.foo", otherBundleIDs: ["com.foo.pro"], isGroupContainer: true
        ))
    }

    func testBundleIDsThatCouldEscapeLibraryAreRejected() {
        XCTAssertTrue(ScanPolicy.isUsableLeftoverBundleID("com.foo-bar.app_1"))
        XCTAssertFalse(ScanPolicy.isUsableLeftoverBundleID(""))
        XCTAssertFalse(ScanPolicy.isUsableLeftoverBundleID(".."))
        XCTAssertFalse(ScanPolicy.isUsableLeftoverBundleID("com.foo/../../Documents"))
        XCTAssertFalse(ScanPolicy.isUsableLeftoverBundleID("../Documents"))
    }

    func testLeftoverLocationIsDirectChildOfKnownLibraryFolder() {
        XCTAssertTrue(ScanPolicy.isAppLeftoverLocation(library.appendingPathComponent("Preferences/a.plist").path, home: home))
        XCTAssertTrue(ScanPolicy.isAppLeftoverLocation(library.appendingPathComponent("Group Containers/T.com.foo").path, home: home))
        XCTAssertFalse(ScanPolicy.isAppLeftoverLocation(library.appendingPathComponent("Preferences/sub/a.plist").path, home: home))
        XCTAssertFalse(ScanPolicy.isAppLeftoverLocation(home.appendingPathComponent("Documents/a").path, home: home))
        XCTAssertFalse(ScanPolicy.isAppLeftoverLocation(library.appendingPathComponent("Caches/../../Documents").path, home: home))
        XCTAssertFalse(ScanPolicy.isAppLeftoverLocation(systemLibrary.appendingPathComponent("LaunchDaemons/a.plist").path, home: home))
    }

    // MARK: - Discovery

    func testChromeUninstallDoesNotOfferCanaryOrLookalikes() throws {
        let prefs = library.appendingPathComponent("Preferences")
        try makeFile(prefs.appendingPathComponent("com.google.Chrome.plist"))
        try makeFile(prefs.appendingPathComponent("com.google.Chrome.canary.plist"))
        try makeFile(prefs.appendingPathComponent("com.google.Chromebook.plist"))
        try makeFile(library.appendingPathComponent("LaunchAgents/com.google.Chrome.canary.agent.plist"))
        let app = try makeApp()

        let withCanaryInstalled = makeUninstaller().findLeftovers(for: app, otherBundleIDs: ["com.google.Chrome.canary"])
        XCTAssertEqual(names(withCanaryInstalled), ["com.google.Chrome.plist"])

        let withoutCanary = makeUninstaller().findLeftovers(for: app)
        let canary = try XCTUnwrap(withoutCanary.first { $0.path.hasSuffix("com.google.Chrome.canary.plist") })
        XCTAssertFalse(canary.isSelectedByDefault, "a derived name may be another app's own bundle ID")
        XCTAssertFalse(names(withoutCanary).contains("com.google.Chromebook.plist"))
        let exact = try XCTUnwrap(withoutCanary.first { $0.path.hasSuffix("com.google.Chrome.plist") })
        XCTAssertTrue(exact.isSelectedByDefault)
    }

    func testLaunchItemsAreUnselectedAndSystemOnesReportOnly() throws {
        try makeFile(library.appendingPathComponent("LaunchAgents/com.google.Chrome.plist"))
        try makeFile(systemLibrary.appendingPathComponent("LaunchDaemons/com.google.Chrome.helper.plist"))
        try makeFile(systemLibrary.appendingPathComponent("LaunchAgents/com.google.Chrome.plist"))

        let leftovers = makeUninstaller().findLeftovers(for: try makeApp())

        XCTAssertEqual(leftovers.count, 3)
        XCTAssertTrue(leftovers.allSatisfy { !$0.isSelectedByDefault })
        let system = leftovers.filter { $0.path.hasPrefix(systemLibrary.path) }
        XCTAssertEqual(system.count, 2)
        XCTAssertTrue(system.allSatisfy(\.isReportOnly))
        XCTAssertEqual(leftovers.filter { !$0.isReportOnly }.map(\.category), [.launchAgents])
    }

    func testGroupContainersMatchOnBoundaryAndStartUnselected() throws {
        let groups = library.appendingPathComponent("Group Containers")
        try makeDirectory(groups.appendingPathComponent("ABCDE12345.com.foo"))
        try makeDirectory(groups.appendingPathComponent("ABCDE12345.com.foobar"))

        let leftovers = makeUninstaller().findLeftovers(for: try makeApp(bundleID: "com.foo", name: "Foo"))

        XCTAssertEqual(names(leftovers), ["ABCDE12345.com.foo"])
        XCTAssertTrue(leftovers[0].isGroupContainer)
        XCTAssertFalse(leftovers[0].isSelectedByDefault)
    }

    func testSymlinkedLeftoversAreNeverOffered() throws {
        let target = try makeDirectory(home.appendingPathComponent("Documents/Precious"))
        let support = library.appendingPathComponent("Application Support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: support.appendingPathComponent(chromeID), withDestinationURL: target
        )
        try makeDirectory(library.appendingPathComponent("Caches/\(chromeID)"))

        let leftovers = makeUninstaller().findLeftovers(for: try makeApp())

        XCTAssertEqual(leftovers.map(\.category), [.caches])
    }

    func testExcludedLeftoversAreReportOnly() throws {
        let caches = try makeDirectory(library.appendingPathComponent("Caches/\(chromeID)"))
        let exclusions = ExclusionList(entries: [ExclusionEntry(path: caches.path, matchType: .prefix)])

        let leftovers = makeUninstaller(exclusions: exclusions).findLeftovers(for: try makeApp())

        let cache = try XCTUnwrap(leftovers.first)
        XCTAssertTrue(cache.isReportOnly)
        XCTAssertFalse(cache.isSelectedByDefault)
    }

    // MARK: - Uninstall

    func testUninstallTrashesOnlyVerifiedLeftoversAndRecordsUndo() async throws {
        let app = try makeApp()
        let cache = try makeDirectory(library.appendingPathComponent("Caches/\(chromeID)"))
        let excluded = try makeFile(library.appendingPathComponent("Preferences/\(chromeID).plist"))
        let outside = try makeFile(home.appendingPathComponent("Documents/\(chromeID)"))
        let linkTarget = try makeDirectory(home.appendingPathComponent("Documents/Target"))
        let link = library.appendingPathComponent("Application Support/\(chromeID)")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: linkTarget)
        let daemon = try makeFile(systemLibrary.appendingPathComponent("LaunchDaemons/\(chromeID).plist"))

        let uninstaller = makeUninstaller(
            exclusions: ExclusionList(entries: [ExclusionEntry(path: excluded.path, matchType: .exact)])
        )
        let result = try await uninstaller.uninstall(app: app, leftovers: [
            AppLeftover(path: cache.path, sizeBytes: 1, category: .caches),
            AppLeftover(path: excluded.path, sizeBytes: 1, category: .preferences),
            AppLeftover(path: outside.path, sizeBytes: 1, category: .support),
            AppLeftover(path: link.path, sizeBytes: 1, category: .support),
            AppLeftover(path: daemon.path, sizeBytes: 1, category: .launchDaemons, reportOnlyReason: "system"),
        ])

        XCTAssertEqual(result.trashed, [app.path, cache.path])
        XCTAssertEqual(Set(result.skipped.map(\.path)), [excluded.path, outside.path, link.path, daemon.path])
        for kept in [excluded, outside, daemon, linkTarget] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), kept.path)
        }
        XCTAssertTrue(ScanPolicy.isSymbolicLink(atPath: link.path))

        let store = CleanupTransactionStore(directory: root.appendingPathComponent("transactions"))
        let transaction = try XCTUnwrap(try store.load(id: XCTUnwrap(result.transactionID)))
        XCTAssertEqual(transaction.items.map(\.originalPath), [app.path, cache.path])
        XCTAssertTrue(transaction.items.allSatisfy { $0.trashedPath != nil })
    }

    func testUninstallRefusesWhileAppRuns() async throws {
        let app = try makeApp()
        let uninstaller = makeUninstaller(running: [RunningApp(bundleIdentifier: "COM.GOOGLE.CHROME", name: "Chrome")])

        do {
            _ = try await uninstaller.uninstall(app: app, leftovers: [])
            XCTFail("expected appRunning")
        } catch let error as AppUninstallError {
            XCTAssertEqual(error, .appRunning("Google Chrome"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    func testUninstallRefusesWhenExclusionsUnreadable() async throws {
        let app = try makeApp()
        do {
            _ = try await makeUninstaller(exclusions: nil).uninstall(app: app, leftovers: [])
            XCTFail("expected exclusionsUnreadable")
        } catch let error as AppUninstallError {
            XCTAssertEqual(error, .exclusionsUnreadable)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    func testUserLaunchAgentIsKeptWhenBootoutFails() async throws {
        let agent = try makeFile(library.appendingPathComponent("LaunchAgents/\(chromeID).plist"))
        let unloader = StubUnloader(outcome: .failed("launchctl did not respond"))

        let result = try await makeUninstaller(unloader: unloader).uninstall(
            app: try makeApp(),
            leftovers: [AppLeftover(path: agent.path, sizeBytes: 1, category: .launchAgents)]
        )

        XCTAssertFalse(result.trashed.contains(agent.path))
        XCTAssertEqual(result.skipped.map(\.path), [agent.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent.path))
        let unloaded = await unloader.unloaded
        XCTAssertEqual(unloaded, ["\(chromeID).plist"])
    }

    func testUserLaunchAgentIsTrashedAfterBootout() async throws {
        let agent = try makeFile(library.appendingPathComponent("LaunchAgents/\(chromeID).plist"))
        let unloader = StubUnloader(outcome: .unloaded)

        let result = try await makeUninstaller(unloader: unloader).uninstall(
            app: try makeApp(),
            leftovers: [AppLeftover(path: agent.path, sizeBytes: 1, category: .launchAgents)]
        )

        XCTAssertTrue(result.trashed.contains(agent.path))
        let unloaded = await unloader.unloaded
        XCTAssertEqual(unloaded, ["\(chromeID).plist"])
    }

    // MARK: - launchctl

    private func makeAgentPlist(label: String?) throws -> URL {
        let url = library.appendingPathComponent("LaunchAgents/agent.plist")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var plist: [String: Any] = ["ProgramArguments": ["/bin/true"]]
        if let label { plist["Label"] = label }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
        return url
    }

    private func unloader(log: CallLog, print: Int32?, bootout: Int32?) -> LaunchctlAgentUnloader {
        LaunchctlAgentUnloader(uid: 501) { arguments in
            await log.append(arguments)
            return arguments.first == "print" ? print : bootout
        }
    }

    func testLaunchctlBootsOutLoadedAgent() async throws {
        let log = CallLog()
        let outcome = await unloader(log: log, print: 0, bootout: 0).unload(plistAt: try makeAgentPlist(label: "com.foo.agent"))

        XCTAssertEqual(outcome, .unloaded)
        let calls = await log.calls
        XCTAssertEqual(calls, [["print", "gui/501/com.foo.agent"], ["bootout", "gui/501/com.foo.agent"]])
    }

    func testLaunchctlSkipsBootoutForUnloadedAgent() async throws {
        let log = CallLog()
        let outcome = await unloader(log: log, print: 113, bootout: 0).unload(plistAt: try makeAgentPlist(label: "com.foo.agent"))

        XCTAssertEqual(outcome, .notLoaded)
        let calls = await log.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testLaunchctlFailuresBlockTrash() async throws {
        let plist = try makeAgentPlist(label: "com.foo.agent")
        let cases: [(print: Int32?, bootout: Int32?)] = [(nil, 0), (5, 0), (0, nil), (0, 5)]
        for (print, bootout) in cases {
            let outcome = await unloader(log: CallLog(), print: print, bootout: bootout).unload(plistAt: plist)
            guard case .failed = outcome else {
                return XCTFail("print \(String(describing: print)) bootout \(String(describing: bootout)) gave \(outcome)")
            }
        }
    }

    func testLaunchctlRefusesPlistWithoutLabel() async throws {
        let log = CallLog()
        let outcome = await unloader(log: log, print: 0, bootout: 0).unload(plistAt: try makeAgentPlist(label: nil))

        guard case .failed = outcome else { return XCTFail("expected failure, got \(outcome)") }
        let calls = await log.calls
        XCTAssertTrue(calls.isEmpty)
    }
}
