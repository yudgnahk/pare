import XCTest
@testable import PareCore

/// Guards that keep the slowest rules from walking far more than they report on.
final class ScanWorkGuardTests: XCTestCase {

    private var tmp: URL!
    private var suiteName: String!

    override func setUpWithError() throws {
        tmp = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_guard_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        suiteName = "pare.tests.scan-guard.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Project discovery

    func testHomeBundlesAndToolchainsAreNeverProjectRoots() {
        let home = URL(fileURLWithPath: "/Users/u")
        let cases: [(path: String, excluded: Bool)] = [
            ("/Users/u", true),
            ("/Users", true),
            ("/", true),
            ("/Users/u/Downloads/Slack.app/Contents/Resources/app", true),
            ("/Volumes/Ext/Tools/Cursor.APP/Contents/Resources/app/extensions/git", true),
            ("/Users/u/Projects/x/Electron Framework.framework/Resources", true),
            ("/Users/u/.nvm/versions/node/v20.0.0/lib", true),
            ("/Users/u/.rustup/toolchains/stable/lib/rustlib/src/rust", true),
            ("/Users/u/.vscode/extensions/ms-python.python-2024.1.0", true),
            ("/Users/u/.cache/node/corepack/v1/pnpm/9.0.0", true),
            ("/Users/u/Projects/ios/Pods/Alamofire", true),
            ("/Users/u/Projects/pkg/.build/checkouts/swift-nio", true),
            // Projects inside home, and names that only look like bundles or toolchains.
            ("/Users/u/Projects/app", false),
            ("/Users/u/Projects/my.application", false),
            ("/Users/u/Projects/appkit-demo.apps", false),
            ("/Users/u/Projects/nvm-tools", false),
            ("/Users/other", false),
        ]
        for testCase in cases {
            XCTAssertEqual(
                ScanPolicy.isExcludedFromProjectDiscovery(URL(fileURLWithPath: testCase.path), home: home),
                testCase.excluded,
                testCase.path
            )
        }
    }

    func testDeduplicateDropsPackageJsonShippedInsideAnApp() {
        let hits = [
            "/Applications/Utilities/Thing.app/Contents/Resources/app/package.json",
            "/Users/u/Downloads/Slack.app/Contents/Resources/app/package.json",
            "/Users/u/Projects/web/package.json",
        ].map { URL(fileURLWithPath: $0) }

        XCTAssertEqual(ProjectRootDiscovery.deduplicate(hits).map(\.path), ["/Users/u/Projects/web"])
    }

    // MARK: - ProjectArtifactsRule

    func testHomeAsRootIsNotWalkedButItsProjectsStillAre() async throws {
        let home = tmp.appending(path: "home")
        _ = try makeArtifact(home.appending(path: ".cache"))
        let projectCache = try makeArtifact(home.appending(path: "Projects/web/.cache"))
        let rule = makeProjectRule(manualRoots: [home, home.appending(path: "Projects/web")])

        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: home)) ?? []

        XCTAssertEqual(findings.map(\.path), [projectCache.path])
    }

    func testWalkSkipsAppBundles() async throws {
        let root = tmp.appending(path: "proj")
        _ = try makeArtifact(root.appending(path: "release/Thing.app/Contents/Resources/app/.cache"))
        try Data("{}".utf8).write(to: root.appending(path: "release/Thing.app/Contents/Resources/app/package.json"))
        let control = try makeArtifact(root.appending(path: "tools/.cache"))
        let rule = makeProjectRule(manualRoots: [root])

        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp.appending(path: "home"))) ?? []

        XCTAssertEqual(findings.map(\.path), [control.path])
    }

    func testRootInsideBundleUnderAnotherRootIsNotDroppedAsCovered() {
        let outer = URL(fileURLWithPath: "/Users/u/Projects/p")
        let insideBundle = URL(fileURLWithPath: "/Users/u/Projects/p/Thing.app/Contents/web")

        XCTAssertEqual(ProjectArtifactsRule.droppingCoveredRoots([outer, insideBundle]), [outer, insideBundle])
    }

    // MARK: - VersionSiblingsRule

    func testWideDirectoryIsCheckedForGroupsButNotDescended() async throws {
        let home = try makeHome()
        let wide = home.appending(path: ".tool/sessions")
        try FileManager.default.createDirectory(at: wide, withIntermediateDirectories: true)
        for index in 0...VersionSiblingsRule.fanOutLimit {
            try Data().write(to: wide.appending(path: "session-\(index).json"))
        }
        for version in ["1.0.0", "1.1.0", "1.2.0"] {
            try makeVersion(wide.appending(path: version))
            try makeVersion(wide.appending(path: "nested/versions/\(version)"))
        }

        let findings = await VersionSiblingsRule(runningExecutables: NoExecutables())
            .customScan(environment: ScanEnvironment(homeDirectory: home, systemApplicationDirectories: [])) ?? []

        XCTAssertEqual(findings.map(\.path), [wide.appending(path: "1.0.0").path])
    }

    func testCorepackVersionsAreLeftToCorepack() async throws {
        let home = try makeHome()
        for version in ["9.0.0", "9.1.0", "10.0.0"] {
            try makeVersion(home.appending(path: ".cache/node/corepack/v1/pnpm/\(version)"))
        }

        let findings = await VersionSiblingsRule(runningExecutables: NoExecutables())
            .customScan(environment: ScanEnvironment(homeDirectory: home, systemApplicationDirectories: [])) ?? []

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    // MARK: - Go module cache size

    func testRememberedModuleCacheSizeIsReusedUntilShapeChangesOrItExpires() throws {
        let module = tmp.appending(path: "go/pkg/mod")
        try FileManager.default.createDirectory(at: module.appending(path: "github.com/acme/lib@v1.0.0"), withIntermediateDirectories: true)
        let clock = MutableClock()
        let store = GoModuleCacheSizeStore(storeURL: tmp.appending(path: "store/sizes.json"), now: { clock.now })

        XCTAssertNil(store.size(for: module), "nothing remembered yet")
        store.remember(4096, for: module)
        XCTAssertEqual(store.size(for: module), 4096)

        // Survives a fresh process reading the same file.
        let reloaded = GoModuleCacheSizeStore(storeURL: tmp.appending(path: "store/sizes.json"), now: { clock.now })
        XCTAssertEqual(reloaded.size(for: module), 4096)

        clock.now = clock.now.addingTimeInterval(GoModuleCacheSizeStore.maxAge)
        XCTAssertNil(store.size(for: module), "expired")

        store.remember(8192, for: module)
        try FileManager.default.createDirectory(at: module.appending(path: "github.com/neworg"), withIntermediateDirectories: true)
        XCTAssertNil(store.size(for: module), "a new org changes github.com's modification time")
    }

    func testGoRuleServesRememberedModuleSizeWithoutRewalking() async throws {
        let home = tmp.appending(path: "home")
        let module = home.appending(path: "go/pkg/mod")
        let package = module.appending(path: "github.com/acme/lib@v1.0.0")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8192).write(to: package.appending(path: "a.go"))
        let store = GoModuleCacheSizeStore(storeURL: tmp.appending(path: "store/sizes.json"))
        let rule = GoCachesRule(locations: GoCacheLocations(query: { nil }), moduleSizes: store)

        let firstScan = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))
        let first = try XCTUnwrap(firstScan?.first)
        // Deeper than the fingerprint looks, so only a re-walk would notice it.
        try Data(repeating: 1, count: 1_048_576).write(to: package.appending(path: "b.go"))
        let secondScan = await rule.customScan(environment: ScanEnvironment(homeDirectory: home))
        let second = try XCTUnwrap(secondScan?.first)

        XCTAssertEqual(first.path, module.path)
        XCTAssertGreaterThan(first.sizeBytes, 0)
        XCTAssertEqual(second.sizeBytes, first.sizeBytes)
        XCTAssertEqual(second.annotations, [.workingSet(selfTrimDays: nil)])
        XCTAssertEqual(second.riskLevel, .advanced)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeArtifact(_ dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 1024).write(to: dir.appending(path: "content.bin"))
        let old = Date().addingTimeInterval(-10 * 86400)
        try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: dir.path)
        return dir
    }

    private func makeProjectRule(manualRoots: [URL]) -> ProjectArtifactsRule {
        let storeURL = tmp.appending(path: "store-\(UUID().uuidString)/project-roots.json")
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = ProjectRootsStore(confirmed: [], excluded: [], manual: manualRoots.map(\.path), lastDiscoveredAt: Date())
        try? JSONEncoder().encode(store).write(to: storeURL)
        let discovery = ProjectRootDiscovery(storeURL: storeURL, spotlightSearch: {
            SpotlightSearchResult(urls: [], timedOut: false)
        })
        return ProjectArtifactsRule(discovery: discovery, pathStore: ProjectScanPathStore(defaults: UserDefaults(suiteName: suiteName)!))
    }

    private func makeHome() throws -> URL {
        let home = tmp.appending(path: "home")
        // Dot-directory roots count only directly inside a folder that holds `Library`.
        try FileManager.default.createDirectory(at: home.appending(path: "Library"), withIntermediateDirectories: true)
        return home
    }

    private func makeVersion(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir.appending(path: "bin"), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 4096).write(to: dir.appending(path: "bin/tool"))
    }
}

private struct NoExecutables: RunningExecutablesProviding {
    func runningExecutablePaths() async -> [String]? { [] }
}

private final class MutableClock: @unchecked Sendable {
    var now = Date()
}
