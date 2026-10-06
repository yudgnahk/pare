import XCTest
@testable import PareCore

/// Hidden build caches (`.build`, `.dart_tool`, …) are reclaimable only next to the manifest that regenerates them.
final class HiddenProjectArtifactsTests: XCTestCase {

    private static let markerCases: [(name: String, marker: String)] = [
        (".build", "Package.swift"),
        (".dart_tool", "pubspec.yaml"),
        (".angular", "angular.json"),
        (".svelte-kit", "package.json"),
        (".vite", "package.json"),
        (".expo", "package.json"),
        (".serverless", "serverless.yml"),
        (".serverless", "serverless.yaml"),
        (".serverless", "serverless.ts"),
        (".serverless", "serverless.js"),
        (".serverless", "serverless.json"),
    ]

    private var tmp: URL!

    override func setUpWithError() throws {
        // Directory listings report `/private/var/…`; `resolvingSymlinksInPath()` would strip `/private` instead.
        tmp = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - ScanPolicy

    func testRequiredSiblingMarkerTruthTable() {
        for testCase in Self.markerCases {
            let url = URL(fileURLWithPath: "/p/app/\(testCase.name)")
            XCTAssertTrue(
                ScanPolicy.hasRequiredSiblingMarker(url, fileExists: { $0 == "/p/app/\(testCase.marker)" }),
                "\(testCase.name) next to \(testCase.marker)"
            )
            XCTAssertFalse(
                ScanPolicy.hasRequiredSiblingMarker(url, fileExists: { $0 == "/p/\(testCase.marker)" }),
                "\(testCase.name) needs the marker beside it, not in an ancestor"
            )
            XCTAssertFalse(
                ScanPolicy.hasRequiredSiblingMarker(url, fileExists: { _ in false }),
                "\(testCase.name) without a marker"
            )
        }
        XCTAssertTrue(ScanPolicy.hasRequiredSiblingMarker(URL(fileURLWithPath: "/p/app/.cache"), fileExists: { _ in false }),
                      "names without a marker requirement pass")
    }

    func testNewNamesAreArtifactsButNotGitGated() {
        for name in [".build", ".dart_tool", ".angular", ".svelte-kit", ".vite", ".expo", ".serverless"] {
            let url = URL(fileURLWithPath: "/p/app/\(name)")
            XCTAssertTrue(ScanPolicy.isProjectArtifact(url), name)
            XCTAssertFalse(ScanPolicy.requiresGitIgnoreEvidence(url), name)
        }
        for name in [".swiftpm", ".terraform", ".github", ".idea"] {
            XCTAssertFalse(ScanPolicy.isProjectArtifact(URL(fileURLWithPath: "/p/app/\(name)")), name)
        }
    }

    func testCleanupGateChecksSiblingMarkerBeforeRegisteredRoot() {
        let root = "/Users/u/Documents/pkg"
        let build = URL(fileURLWithPath: root + "/.build")

        XCTAssertFalse(ScanPolicy.isReclaimableProjectArtifact(
            build, registeredRootPaths: [root], fileExists: { _ in false }
        ))
        XCTAssertTrue(ScanPolicy.isReclaimableProjectArtifact(
            build, registeredRootPaths: [root], fileExists: { $0 == root + "/Package.swift" }
        ))
    }

    func testFolderRollupGroupsAtBuildSegment() {
        XCTAssertEqual(
            FolderRollup.rollupFolderPath(for: "/Users/u/Projects/app/.build/arm64-apple-macosx/debug/App.o"),
            "/Users/u/Projects/app/.build"
        )
        XCTAssertEqual(
            FolderRollup.rollupFolderPath(for: "/Users/u/Projects/app/.dart_tool"),
            "/Users/u/Projects/app/.dart_tool"
        )
    }

    // MARK: - Child-mtime age

    func testRebuiltBuildDirectoryAgesByNewestChild() throws {
        let build = try makeArtifact("app/.build", marker: "Package.swift")
        try Data().write(to: build.appending(path: "build.db"))  // rewritten "today"

        let values = try build.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey])
        let age = try XCTUnwrap(ScanPolicy.projectArtifactAgeDate(for: build, values: values))

        XCTAssertLessThan(Date().timeIntervalSince(age), 60 * 60, "a fresh child makes the cache fresh")
    }

    func testOtherNamesKeepDirectoryEffectiveAge() throws {
        let cache = try makeArtifact("app/.cache", marker: nil)
        try Data().write(to: cache.appending(path: "fresh.bin"))
        let old = Date().addingTimeInterval(-10 * 86400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: cache.path)

        let values = try cache.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey])

        XCTAssertEqual(ScanPolicy.projectArtifactAgeDate(for: cache, values: values), ScanPolicy.effectiveAgeDate(from: values))
    }

    // MARK: - ProjectArtifactsRule

    func testEachNameIsReportedOnlyWithItsMarker() async throws {
        for (index, testCase) in Self.markerCases.enumerated() {
            let with = try makeArtifact("with\(index)/\(testCase.name)", marker: testCase.marker)
            let without = try makeArtifact("without\(index)/\(testCase.name)", marker: nil)

            let paths = Set(await scan().map(\.path))

            XCTAssertTrue(paths.contains(with.path), "\(testCase.name) next to \(testCase.marker)")
            XCTAssertFalse(paths.contains(without.path), "\(testCase.name) without a marker")
        }
    }

    func testSwiftPackageBuildIsSafeWithoutGit() async throws {
        let build = try makeArtifact("pkg/.build", marker: "Package.swift")

        let findings = await scan(gitStatus: .notInRepository)

        let finding = try XCTUnwrap(findings.first { $0.path == build.path })
        XCTAssertEqual(finding.riskLevel, .safe)
    }

    func testNestedPackageBuildIsFound() async throws {
        let build = try makeArtifact("mono/Packages/Foo/.build", marker: "Package.swift")

        let paths = await scan().map(\.path)

        XCTAssertTrue(paths.contains(build.path))
    }

    func testUnsupportedHiddenFoldersAreNeverReported() async throws {
        for name in [".swiftpm", ".terraform", ".github", ".idea"] {
            _ = try makeArtifact("app/\(name)", marker: "Package.swift")
        }
        try Data().write(to: tmp.appending(path: "app/main.tf"))

        let findings = await scan()

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    func testBuildRebuiltTodayIsNotReported() async throws {
        let build = try makeArtifact("pkg/.build", marker: "Package.swift")
        try Data().write(to: build.appending(path: "build.db"))
        let old = Date().addingTimeInterval(-10 * 86400)
        try FileManager.default.setAttributes([.modificationDate: old, .creationDate: old], ofItemAtPath: build.path)

        let findings = await scan()

        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.path))")
    }

    // MARK: - Helpers

    /// Creates `relative` with one backdated child, backdates the directory, and optionally drops `marker` beside it.
    @discardableResult
    private func makeArtifact(_ relative: String, marker: String?) throws -> URL {
        let dir = tmp.appending(path: relative)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let child = dir.appending(path: "content.bin")
        try Data(repeating: 0xAB, count: 1024).write(to: child)
        let old = Date().addingTimeInterval(-10 * 86400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: child.path)
        try FileManager.default.setAttributes([.modificationDate: old, .creationDate: old], ofItemAtPath: dir.path)
        if let marker {
            try Data().write(to: dir.deletingLastPathComponent().appending(path: marker))
        }
        return URL(fileURLWithPath: dir.path)
    }

    private func scan(gitStatus: GitArtifactStatus? = nil) async -> [ScanFinding] {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "pare_test_store_\(UUID().uuidString)/project-roots.json")
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = ProjectRootsStore(confirmed: [], excluded: [], manual: [tmp.path], lastDiscoveredAt: Date())
        try? JSONEncoder().encode(store).write(to: storeURL)
        let suiteName = "pare.tests.hidden-artifacts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let rule = ProjectArtifactsRule(
            discovery: ProjectRootDiscovery(storeURL: storeURL),
            pathStore: ProjectScanPathStore(defaults: defaults),
            gitInspector: StubGitInspector(status: gitStatus)
        )
        return await rule.customScan(environment: ScanEnvironment.current()) ?? []
    }
}
