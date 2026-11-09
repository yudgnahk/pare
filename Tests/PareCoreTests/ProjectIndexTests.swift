import XCTest
@testable import PareCore

final class ProjectIndexTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/u")

    private final class FakeProbe: ProjectMarkerProbing, @unchecked Sendable {
        private let lock = NSLock()
        private let git: Set<String>
        private let markers: Set<String>
        private var counts: [String: Int] = [:]

        init(git: [String] = [], markers: [String] = []) {
            self.git = Set(git)
            self.markers = Set(markers)
        }

        func probe(directory: String) -> (hasGit: Bool, hasMarker: Bool) {
            lock.lock()
            counts[directory, default: 0] += 1
            lock.unlock()
            return (git.contains(directory), markers.contains(directory))
        }

        var maxCount: Int { lock.lock(); defer { lock.unlock() }; return counts.values.max() ?? 0 }
        var probed: Set<String> { lock.lock(); defer { lock.unlock() }; return Set(counts.keys) }
    }

    private func index(
        _ folders: [String], roots: [String] = ["/Users/u/Code"], probe: FakeProbe
    ) -> ProjectIndex {
        ProjectIndex.build(
            folderPaths: folders,
            registeredRoots: roots.map { URL(fileURLWithPath: $0) },
            homeDirectory: home,
            probe: probe
        )
    }

    func testMonorepoRollsUpToGitRoot() {
        let probe = FakeProbe(git: ["/Users/u/Code/root"], markers: ["/Users/u/Code/root/apps/web", "/Users/u/Code/root/packages/ui"])
        let folders = ["/Users/u/Code/root/apps/web/.next", "/Users/u/Code/root/packages/ui/dist"]
        let idx = index(folders, probe: probe)
        let refs = Set(folders.compactMap { idx.project(containing: $0) })
        XCTAssertEqual(refs, [ProjectRef(root: "/Users/u/Code/root", name: "root")])
    }

    func testNestedSubmoduleGitWins() {
        let probe = FakeProbe(git: ["/Users/u/Code/root", "/Users/u/Code/root/vendor/lib"])
        let idx = index(["/Users/u/Code/root/vendor/lib/build"], probe: probe)
        XCTAssertEqual(idx.project(containing: "/Users/u/Code/root/vendor/lib/build")?.root, "/Users/u/Code/root/vendor/lib")
    }

    func testWorktreeGitFileCounts() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("pidx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let wt = base.appendingPathComponent("wt")
        let artifact = wt.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
        try "gitdir: /elsewhere".write(to: wt.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let idx = ProjectIndex.build(
            folderPaths: [artifact.path], registeredRoots: [base], homeDirectory: home
        )
        XCTAssertEqual(idx.project(containing: artifact.path)?.name, "wt")
    }

    func testContainerRootYieldsOneProjectPerChild() {
        let probe = FakeProbe(git: ["/Users/u/Code/a"], markers: ["/Users/u/Code/b"])
        let folders = ["/Users/u/Code/a/dist", "/Users/u/Code/b/target"]
        let idx = index(folders, probe: probe)
        XCTAssertEqual(idx.project(containing: folders[0])?.name, "a")
        XCTAssertEqual(idx.project(containing: folders[1])?.name, "b")
    }

    func testNearestMarkerWinsWithoutGit() {
        let probe = FakeProbe(markers: ["/Users/u/Code/p", "/Users/u/Code/p/sub"])
        let idx = index(["/Users/u/Code/p/sub/dist"], probe: probe)
        XCTAssertEqual(idx.project(containing: "/Users/u/Code/p/sub/dist")?.root, "/Users/u/Code/p/sub")
    }

    func testNoMarkerIsNotAProject() {
        let idx = index(["/Users/u/Code/plain/dist"], probe: FakeProbe())
        XCTAssertNil(idx.project(containing: "/Users/u/Code/plain/dist"))
    }

    func testOutsideEveryRootIsNotAProjectAndNotProbed() {
        let probe = FakeProbe(git: ["/Users/u/Other/x"])
        let idx = index(["/Users/u/Other/x/dist"], probe: probe)
        XCTAssertNil(idx.project(containing: "/Users/u/Other/x/dist"))
        XCTAssertTrue(probe.probed.isEmpty)
    }

    func testHomeGitNeverMakesAProject() {
        let probe = FakeProbe(git: ["/Users/u"])
        let idx = index(["/Users/u/Code/a/dist", "/Users/u/Loose/dist"], roots: ["/Users/u", "/Users/u/Code"], probe: probe)
        XCTAssertNil(idx.project(containing: "/Users/u/Code/a/dist"))
        XCTAssertNil(idx.project(containing: "/Users/u/Loose/dist"))
        XCTAssertFalse(probe.probed.contains("/Users/u"))
    }

    func testDeepestRegisteredRootBoundsTheWalk() {
        let probe = FakeProbe(git: ["/Users/u/Code"])
        let idx = index(["/Users/u/Code/team/a/dist"], roots: ["/Users/u/Code", "/Users/u/Code/team"], probe: probe)
        XCTAssertNil(idx.project(containing: "/Users/u/Code/team/a/dist"))
        XCTAssertFalse(probe.probed.contains("/Users/u/Code"))
    }

    func testWalkIsCappedByMaxAncestors() {
        let deep = "/Users/u/Code/p/" + (1...10).map { "d\($0)" }.joined(separator: "/")
        let idx = index([deep + "/dist"], probe: FakeProbe(git: ["/Users/u/Code/p"]))
        XCTAssertNil(idx.project(containing: deep + "/dist"))
    }

    func testNodeModulesInteriorIsNotProbed() {
        let probe = FakeProbe(git: ["/Users/u/Code/a"], markers: ["/Users/u/Code/a/node_modules/foo"])
        let idx = index(["/Users/u/Code/a/node_modules/foo/dist"], probe: probe)
        XCTAssertEqual(idx.project(containing: "/Users/u/Code/a/node_modules/foo/dist")?.root, "/Users/u/Code/a")
        XCTAssertFalse(probe.probed.contains("/Users/u/Code/a/node_modules/foo"))
    }

    func testEachDirectoryIsProbedAtMostOnce() {
        let probe = FakeProbe(git: ["/Users/u/Code/root"])
        _ = index([
            "/Users/u/Code/root/apps/web/.next", "/Users/u/Code/root/apps/web/dist",
            "/Users/u/Code/root/apps/api/dist", "/Users/u/Code/root/packages/ui/dist",
        ], probe: probe)
        XCTAssertEqual(probe.maxCount, 1)
        XCTAssertFalse(probe.probed.isEmpty)
    }

    func testUnknownPathAndEmptyIndex() {
        XCTAssertNil(ProjectIndex.empty.project(containing: "/Users/u/Code/a/dist"))
    }

    // MARK: - FileSystemMarkerProbe

    func testFileSystemProbeReadsRealDirectories() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("pprobe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let fm = FileManager.default
        let gitDir = base.appendingPathComponent("g/.git")
        let pkg = base.appendingPathComponent("p")
        let empty = base.appendingPathComponent("e")
        try fm.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: pkg, withIntermediateDirectories: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        try "{}".write(to: pkg.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let probe = FileSystemMarkerProbe()
        XCTAssertTrue(probe.probe(directory: base.appendingPathComponent("g").path).hasGit)
        XCTAssertFalse(probe.probe(directory: base.appendingPathComponent("g").path).hasMarker)
        XCTAssertTrue(probe.probe(directory: pkg.path).hasMarker)
        XCTAssertFalse(probe.probe(directory: pkg.path).hasGit)
        XCTAssertEqual(probe.probe(directory: empty.path).hasGit, false)
        XCTAssertEqual(probe.probe(directory: base.appendingPathComponent("missing").path).hasMarker, false)
    }

    // MARK: - Resolver and grouping integration

    private func resolver(_ idx: ProjectIndex) -> OwnerResolver {
        OwnerResolver(
            homeDirectory: home, installedApps: .empty, projects: idx,
            catalog: AppCatalog(version: 1, entries: [])
        )
    }

    func testResolverReturnsProjectOwnerAndLeavesToolsAlone() {
        let probe = FakeProbe(git: ["/Users/u/Code/a"])
        let folders = ["/Users/u/Code/a/node_modules", "/Users/u/Code/a/.gradle", "/Users/u/.npm/_cacache", "/Users/u/.gradle/caches"]
        let r = resolver(index(folders, probe: probe))

        let owner = r.owner(forFolderPath: folders[0])
        XCTAssertEqual(owner.kind, .project)
        XCTAssertEqual(owner.key, "project:/Users/u/Code/a")
        XCTAssertEqual(owner.displayName, "a")
        XCTAssertEqual(owner.projectRoot, "/Users/u/Code/a")
        XCTAssertEqual(r.owner(forFolderPath: folders[1]).key, "project:/Users/u/Code/a")
        XCTAssertEqual(r.owner(forFolderPath: folders[2]).key, "tool:npm")
        XCTAssertEqual(r.owner(forFolderPath: folders[3]).key, "tool:gradle")
    }

    func testResolverFallsThroughWhenNoProject() {
        let r = resolver(index(["/Users/u/Code/plain/node_modules"], probe: FakeProbe()))
        XCTAssertEqual(r.owner(forFolderPath: "/Users/u/Code/plain/node_modules"), .other)
    }

    func testGroupingPutsProjectFoldersInProjectSection() {
        let probe = FakeProbe(git: ["/Users/u/Code/a"])
        let findings = [
            ScanFinding(category: .projectArtifacts, riskLevel: .safe, reason: "t", path: "/Users/u/Code/a/.next",
                        sizeBytes: 100, lastUsed: nil, confidence: 1, isSizeComplete: true),
        ]
        let aggregate = FolderRollup.buildAggregate(from: findings)
        let paths = aggregate.recordsByFolderId.values.map(\.folderPath)
        let r = resolver(index(paths, probe: probe))
        let result = OwnerGrouping.build(aggregate: aggregate, resolver: r)
        let section = result.sections.first { $0.kind == .project }
        XCTAssertEqual(section?.groups.map(\.owner.key), ["project:/Users/u/Code/a"])
        XCTAssertEqual(section?.groups.first?.rows.first?.label.hasPrefix("/"), false)
    }
}
