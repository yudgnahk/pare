import XCTest
@testable import PareCore

/// Package-manager and toolchain trees must never become project roots, either from a fresh
/// Spotlight pass or from roots persisted before they were excluded.
final class ProjectDiscoveryExclusionTests: XCTestCase {

    // MARK: - ScanPolicy.isExcludedFromProjectDiscovery

    func testExcludedFromProjectDiscovery() {
        let cases: [(path: String, excluded: Bool)] = [
            ("/Users/u/go/pkg/mod/github.com/acme/lib@v1.2.3", true),
            ("/Users/u/.pub-cache/hosted/pub.dev/http-1.2.0", true),
            ("/Users/u/.cargo/registry/src/index.crates.io-6f17d22bba15001f/serde-1.0.0", true),
            ("/Users/u/.cargo/git/checkouts/tokio-abc/1a2b3c", true),
            ("/Users/u/fvm/versions/3.41.0/packages/flutter", true),
            ("/Users/u/actions-runner/_work/_tool/go/1.22.0/x64/src", true),
            ("/Users/u/.Trash/old-project", true),
            ("/Volumes/Ext/.Trashes/501/old-project", true),
            ("/Users/u/Library/Developer/Xcode", true),
            ("/Users/u/Projects/app/node_modules/lib", true),
            // Component matching, not substring matching.
            ("/Users/u/Projects/gomod-tools", false),
            ("/Users/u/Projects/x/pkg/module", false),
            ("/Users/u/Projects/cargo-registry-ui", false),
            ("/Users/u/Projects/my.pub-cache-viewer", false),
            ("/Users/u/Projects/.Trash-tools", false),
            ("/Users/u/Projects/go/pkg/modules", false),
            // Case-sensitive, matching the old substring behaviour.
            ("/Users/u/Projects/acme/library", false),
            ("/Users/u/Projects/fvm/Versions/demo", false),
        ]
        for testCase in cases {
            XCTAssertEqual(
                ScanPolicy.isExcludedFromProjectDiscovery(URL(fileURLWithPath: testCase.path)),
                testCase.excluded,
                testCase.path
            )
        }
    }

    // MARK: - ProjectRootDiscovery.deduplicate

    func testDeduplicateDropsPackageManagerAndToolchainHits() {
        let hits = [
            "/Users/u/go/pkg/mod/github.com/acme/lib@v1.2.3/go.mod",
            "/Users/u/.pub-cache/hosted/pub.dev/http-1.2.0/pubspec.yaml",
            "/Users/u/.cargo/registry/src/index.crates.io-6f17d22bba15001f/serde-1.0.0/Cargo.toml",
            "/Users/u/.cargo/git/checkouts/tokio-abc/1a2b3c/Cargo.toml",
            "/Users/u/fvm/versions/3.41.0/packages/flutter/pubspec.yaml",
            "/Users/u/actions-runner/_work/_tool/go/1.22.0/x64/src/go.mod",
            "/Users/u/.Trash/old-project/.git",
        ].map { URL(fileURLWithPath: $0) }

        XCTAssertEqual(ProjectRootDiscovery.deduplicate(hits), [])
    }

    func testDeduplicateKeepsLookalikeProjectNames() {
        let expected = [
            "/Users/u/Projects/gomod-tools",
            "/Users/u/Projects/x/pkg/module",
            "/Users/u/Projects/cargo-registry-ui",
            "/Users/u/Projects/my.pub-cache-viewer",
            "/Users/u/Projects/acme/library",
        ]
        let hits = [
            "/Users/u/Projects/gomod-tools/go.mod",
            "/Users/u/Projects/x/pkg/module/go.mod",
            "/Users/u/Projects/cargo-registry-ui/Cargo.toml",
            "/Users/u/Projects/my.pub-cache-viewer/pubspec.yaml",
            "/Users/u/Projects/acme/library/go.mod",
        ].map { URL(fileURLWithPath: $0) }

        let paths = Set(ProjectRootDiscovery.deduplicate(hits).map(\.path))

        XCTAssertEqual(paths, Set(expected))
    }

    // MARK: - Pruning persisted roots

    func testPersistedExcludedTreesArePrunedButManualRootsKept() async throws {
        let tmp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try makeDirectory(tmp, "Projects/app")
        let goModule = try makeDirectory(tmp, "go/pkg/mod/github.com/acme/lib@v1.2.3")
        let excludedGoModule = try makeDirectory(tmp, "go/pkg/mod/github.com/acme/other@v0.1.0")
        let optedOut = try makeDirectory(tmp, "Projects/old")
        let manualGoModule = try makeDirectory(tmp, "go/pkg/mod/github.com/acme/pinned@v2.0.0")
        let storeURL = tmp.appending(path: "store/project-roots.json")
        try writeStore(
            ProjectRootsStore(
                confirmed: [project.path, goModule.path],
                excluded: [optedOut.path, excludedGoModule.path],
                manual: [manualGoModule.path],
                lastDiscoveredAt: Date()
            ),
            to: storeURL
        )

        let discovery = ProjectRootDiscovery(storeURL: storeURL, spotlightSearch: { await SearchStub().run() })

        let confirmed = Set(await discovery.confirmedRoots().map(\.path))
        XCTAssertEqual(confirmed, [project.path, manualGoModule.path])
        let discovered = await discovery.allDiscoveredRoots
        XCTAssertEqual(discovered.map(\.url.path), [project.path, optedOut.path])

        await discovery.discoverIfNeeded()

        let saved = try JSONDecoder().decode(ProjectRootsStore.self, from: Data(contentsOf: storeURL))
        XCTAssertEqual(saved.confirmed, [project.path])
        XCTAssertEqual(saved.excluded, [optedOut.path])
        XCTAssertEqual(saved.manual, [manualGoModule.path])
    }

    func testStoreWithoutExcludedTreesIsNotRewritten() async throws {
        let tmp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let project = try makeDirectory(tmp, "Projects/app")
        let storeURL = tmp.appending(path: "store/project-roots.json")
        let original = Data("{\"confirmed\":[\"\(project.path)\"],\"excluded\":[],\"manual\":[],\"lastDiscoveredAt\":0}".utf8)
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try original.write(to: storeURL)

        // The stored timestamp (0) is a minute before `now`, so no refresh is due.
        let discovery = ProjectRootDiscovery(
            storeURL: storeURL,
            spotlightSearch: { await SearchStub().run() },
            now: { Date(timeIntervalSinceReferenceDate: 60) }
        )
        await discovery.discoverIfNeeded()

        XCTAssertEqual(try Data(contentsOf: storeURL), original)
    }

    // MARK: - Helpers

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeDirectory(_ base: URL, _ relative: String) throws -> URL {
        let url = base.appending(path: relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeStore(_ store: ProjectRootsStore, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(store).write(to: url)
    }
}
