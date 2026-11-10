import XCTest
@testable import PareCore

/// Discovery keeps only outermost project folders, at any depth (maintainer decision, 2026-10-13).
final class ProjectRootOutermostTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "pare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - deduplicate

    func testDeduplicateKeepsOnlyOutermostRoots() {
        let cases: [(name: String, hits: [String], expected: Set<String>)] = [
            ("nested more than 3 levels deep",
             ["/u/code/package.json", "/u/code/a/b/c/d/package.json"],
             ["/u/code"]),
            ("nested 8 levels deep",
             ["/u/code/go.mod", "/u/code/a/b/c/d/e/f/g/h/go.mod"],
             ["/u/code"]),
            ("chain of three keeps only the outermost",
             ["/u/code/Package.swift", "/u/code/a/Package.swift", "/u/code/a/b/c/d/Package.swift"],
             ["/u/code"]),
            ("name sharing a prefix is not nested",
             ["/a/proj/package.json", "/a/proj-2/package.json"],
             ["/a/proj", "/a/proj-2"]),
            ("siblings stay independent",
             ["/u/x/package.json", "/u/y/package.json"],
             ["/u/x", "/u/y"]),
            ("hit inside node_modules is dropped, project kept",
             ["/u/app/package.json", "/u/app/node_modules/lib/package.json",
              "/u/app/node_modules/lib/node_modules/dep/package.json"],
             ["/u/app"]),
            ("hit inside node_modules alone leaves nothing",
             ["/u/app/node_modules/lib/package.json"],
             []),
            ("path components compare case-insensitively like the rest of ScanPolicy",
             ["/u/Code/package.json", "/u/code/a/b/c/d/package.json"],
             ["/u/Code"]),
        ]
        for testCase in cases {
            let hits = testCase.hits.map { URL(fileURLWithPath: $0) }
            let paths = Set(ProjectRootDiscovery.deduplicate(hits).map(\.path))
            XCTAssertEqual(paths, testCase.expected, testCase.name)
        }
    }

    func testExcludedOuterRootDoesNotSwallowRootsInside() {
        let hits = ["/u/stray/package.json", "/u/stray/a/b/c/d/app/package.json",
                    "/u/stray/a/b/c/d/app/web/package.json"].map { URL(fileURLWithPath: $0) }

        let paths = Set(ProjectRootDiscovery.deduplicate(hits, userExcluded: ["/u/stray"]).map(\.path))

        XCTAssertEqual(paths, ["/u/stray", "/u/stray/a/b/c/d/app"], "app is kept, web is inside app")
    }

    // MARK: - Store cleanup on discovery

    func testDiscoveryDropsNestedConfirmedRootsFromStore() async throws {
        let outer = try makeDirectory("Projects/outer")
        let inner = try makeDirectory("Projects/outer/a/b/c/d/inner")
        let lookalike = try makeDirectory("Projects/outer-2")
        let deepExcluded = try makeDirectory("Projects/outer/x/y/z/w/optedOut")
        let storeURL = try writeStore(confirmed: [outer, inner, lookalike], excluded: [deepExcluded])

        let discovery = makeDiscovery(storeURL: storeURL, hits: [outer])
        await discovery.discoverIfNeeded()

        let saved = try readStore(storeURL)
        XCTAssertEqual(saved.confirmed, [outer.path, lookalike.path].sorted())
        XCTAssertEqual(saved.excluded, [deepExcluded.path], "the user's exclusion is kept")
    }

    func testExcludedOuterRootKeepsRootsInsideAfterDiscovery() async throws {
        let stray = try makeDirectory("Projects/stray")
        let oldInner = try makeDirectory("Projects/stray/a/b/c/d/oldApp")
        let newInner = try makeDirectory("Projects/stray/a/b/c/d/newApp")
        let storeURL = try writeStore(confirmed: [oldInner], excluded: [stray])

        let discovery = makeDiscovery(storeURL: storeURL, hits: [stray, newInner])
        await discovery.discoverIfNeeded()

        let saved = try readStore(storeURL)
        XCTAssertEqual(saved.confirmed, [newInner.path, oldInner.path].sorted())
        XCTAssertEqual(saved.excluded, [stray.path])
    }

    func testManualOuterRootDoesNotSwallowDiscoveredRoots() async throws {
        let projects = try makeDirectory("Projects")
        let inner = try makeDirectory("Projects/a/b/c/d/e/f/g/app")
        let storeURL = try writeStore(confirmed: [inner], manual: [projects])

        let discovery = makeDiscovery(storeURL: storeURL, hits: [inner])
        await discovery.discoverIfNeeded()

        let saved = try readStore(storeURL)
        XCTAssertEqual(saved.confirmed, [inner.path])
        XCTAssertEqual(saved.manual, [projects.path])
        let active = Set(await discovery.confirmedRoots().map(\.path))
        XCTAssertEqual(active, [inner.path, projects.path])
    }

    // MARK: - Helpers

    private func makeDiscovery(storeURL: URL, hits: [URL]) -> ProjectRootDiscovery {
        let urls = hits.map { $0.appending(path: "package.json") }
        let search = SearchStub(urls: urls)
        return ProjectRootDiscovery(storeURL: storeURL, spotlightSearch: { await search.run() })
    }

    private func makeDirectory(_ relative: String) throws -> URL {
        let url = tmp.appending(path: relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeStore(confirmed: [URL], excluded: [URL] = [], manual: [URL] = []) throws -> URL {
        let url = tmp.appending(path: "store/project-roots.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = ProjectRootsStore(
            confirmed: confirmed.map(\.path),
            excluded: excluded.map(\.path),
            manual: manual.map(\.path),
            lastDiscoveredAt: nil
        )
        try JSONEncoder().encode(store).write(to: url)
        return url
    }

    private func readStore(_ url: URL) throws -> ProjectRootsStore {
        try JSONDecoder().decode(ProjectRootsStore.self, from: Data(contentsOf: url))
    }
}
