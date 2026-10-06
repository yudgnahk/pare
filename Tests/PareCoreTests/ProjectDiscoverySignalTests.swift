import XCTest
@testable import PareCore

/// Spotlight signal files that identify project roots, and how a hit maps back to its root.
final class ProjectDiscoverySignalTests: XCTestCase {

    func testSignalNamesCoverNodeFlutterAndPHPButNotGit() {
        let signals = Set(ScanPolicy.projectDiscoverySignalNames)
        for name in ["package.json", "pubspec.yaml", "composer.json", "Package.resolved", "build.gradle.kts"] {
            XCTAssertTrue(signals.contains(name), name)
        }
        XCTAssertFalse(signals.contains(".git"), "Spotlight never indexes .git, so it only costs query time")
    }

    func testRootMarkersMirrorSignalNames() {
        let markers = Set(ScanPolicy.projectRootMarkerFileNames)
        let expected = Set(ScanPolicy.projectDiscoverySignalNames).subtracting(["Package.resolved"]).union([".git"])
        XCTAssertTrue(markers.isSuperset(of: expected), "missing: \(expected.subtracting(markers))")
        XCTAssertFalse(markers.contains("Package.resolved"), "a lockfile alone must not mark a project root")
    }

    func testProjectRootForSignalHit() {
        let cases: [(hit: String, root: String)] = [
            ("/Users/u/Projects/app/Package.resolved", "/Users/u/Projects/app"),
            ("/Users/u/Projects/app/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
             "/Users/u/Projects/app"),
            ("/Users/u/Projects/app/App.xcworkspace/xcshareddata/swiftpm/Package.resolved", "/Users/u/Projects/app"),
            ("/Users/u/Projects/web/package.json", "/Users/u/Projects/web"),
        ]
        for testCase in cases {
            XCTAssertEqual(
                ProjectRootDiscovery.projectRoot(forSignalHit: URL(fileURLWithPath: testCase.hit)).path,
                testCase.root,
                testCase.hit
            )
        }
    }

    func testDeduplicateMapsNewSignalsToRoots() {
        let hits = [
            "/Users/u/Projects/web/package.json",
            "/Users/u/Projects/web/apps/site/package.json",
            "/Users/u/Projects/flutter_app/pubspec.yaml",
            "/Users/u/Projects/shop/composer.json",
            "/Users/u/Projects/ios/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        ].map { URL(fileURLWithPath: $0) }

        let roots = Set(ProjectRootDiscovery.deduplicate(hits).map(\.path))

        XCTAssertEqual(roots, [
            "/Users/u/Projects/web",
            "/Users/u/Projects/flutter_app",
            "/Users/u/Projects/shop",
            "/Users/u/Projects/ios",
        ])
    }

    func testDeduplicateDropsDependencyStoreAndSDKHits() {
        let hits = [
            "/Users/u/Projects/web/node_modules/react/package.json",
            "/Users/u/Library/pnpm/store/v3/files/00/abc-index/package.json",
            "/Users/u/fvm/versions/3.41.0/packages/flutter_tools/pubspec.yaml",
        ].map { URL(fileURLWithPath: $0) }

        XCTAssertEqual(ProjectRootDiscovery.deduplicate(hits), [])
    }

    func testDiscoverMergesRootsFromNewSignals() async throws {
        let tmp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let web = tmp.appending(path: "Projects/web")
        let flutter = tmp.appending(path: "Projects/flutter_app")
        for dir in [web, flutter] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let search = SearchStub(urls: [
            web.appending(path: "package.json"),
            flutter.appending(path: "pubspec.yaml"),
        ])
        let discovery = ProjectRootDiscovery(
            storeURL: tmp.appending(path: "store/project-roots.json"),
            spotlightSearch: { await search.run() }
        )

        _ = await discovery.discover()

        let confirmed = Set(await discovery.confirmedRoots().map(\.path))
        XCTAssertEqual(confirmed, [web.path, flutter.path])
    }
}
