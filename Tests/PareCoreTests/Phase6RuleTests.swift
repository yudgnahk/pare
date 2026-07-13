import XCTest
@testable import PareCore

// MARK: - PythonCachesRule

final class PythonCachesRuleTests: XCTestCase {

    func testReturnsEmptyWhenNoPythonPathsExist() async {
        let rule = PythonCachesRule()
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString)"))
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty)
    }

    func testDetectsPipCacheDirectory() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let pipCache = tmp.appending(path: "Library/Caches/pip")
        try createDirWithContent(at: pipCache)

        let rule = PythonCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!

        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/pip") }, "pip cache should be detected")
        XCTAssertEqual(findings.first { $0.path.hasSuffix("/pip") }?.riskLevel, .safe)
        XCTAssertEqual(findings.first { $0.path.hasSuffix("/pip") }?.category, .developerPackageCaches)
    }

    func testDetectsPyenvCache() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let pyenvCache = tmp.appending(path: ".pyenv/cache")
        try createDirWithContent(at: pyenvCache)

        let rule = PythonCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!

        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/.pyenv/cache") }, "pyenv cache should be detected")
    }

    func testDoesNotFlagEmptyDirectories() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create empty pip dir — should not emit a finding
        let pipCache = tmp.appending(path: "Library/Caches/pip")
        try FileManager.default.createDirectory(at: pipCache, withIntermediateDirectories: true)

        let rule = PythonCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!
        XCTAssertTrue(findings.isEmpty, "Empty directory should not emit a finding")
    }
}

// MARK: - RubyCachesRule

final class RubyCachesRuleTests: XCTestCase {

    func testReturnsEmptyWhenNoRubyPathsExist() async {
        let rule = RubyCachesRule()
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString)"))
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty)
    }

    func testDetectsVersionedGemCache() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let gemCache = tmp.appending(path: ".gem/ruby/3.2.0/cache")
        try createDirWithContent(at: gemCache)

        let rule = RubyCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!

        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/cache") && $0.path.contains(".gem/ruby") },
                      "Versioned gem cache should be detected")
        XCTAssertEqual(findings.first?.riskLevel, .safe)
    }

    func testDoesNotFlagGemSourceDirectory() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Only create gems/ (installed source), NOT cache/
        let gemsDir = tmp.appending(path: ".gem/ruby/3.2.0/gems/rake-13.0.0")
        try createDirWithContent(at: gemsDir)

        let rule = RubyCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!

        XCTAssertTrue(findings.isEmpty, "gems/ directory should NOT be flagged — only cache/ should be targeted")
    }

    func testDetectsBundleCache() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let bundleCache = tmp.appending(path: ".bundle/cache")
        try createDirWithContent(at: bundleCache)

        let rule = RubyCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!
        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/.bundle/cache") })
    }
}

// MARK: - JavaBuildCachesRule

final class JavaBuildCachesRuleTests: XCTestCase {

    func testReturnsEmptyWhenNoJavaPathsExist() async {
        let rule = JavaBuildCachesRule()
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString)"))
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty)
    }

    func testGradleCacheIsFlaggedAsSafe() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let gradleCache = tmp.appending(path: ".gradle/caches")
        try createDirWithContent(at: gradleCache)

        let rule = JavaBuildCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!

        let f = findings.first { $0.path.hasSuffix("/.gradle/caches") }
        XCTAssertNotNil(f)
        XCTAssertEqual(f?.riskLevel, .safe, "Gradle cache should be .safe")
        XCTAssertEqual(f?.category, .developerBuildArtifacts)
    }

    func testMavenRepoIsFlaggedAsReview() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let m2Repo = tmp.appending(path: ".m2/repository")
        try createDirWithContent(at: m2Repo)

        let rule = JavaBuildCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!

        let f = findings.first { $0.path.hasSuffix("/.m2/repository") }
        XCTAssertNotNil(f)
        XCTAssertEqual(f?.riskLevel, .review, "Maven local repo should be .review")
    }

    func testGradleWrapperDistsFlagged() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let wrapperDists = tmp.appending(path: ".gradle/wrapper/dists")
        try createDirWithContent(at: wrapperDists)

        let rule = JavaBuildCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!
        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/dists") && $0.riskLevel == .safe })
    }
}

// MARK: - RustCachesRule

final class RustCachesRuleTests: XCTestCase {

    func testReturnsEmptyWhenNoRustPathsExist() async {
        let rule = RustCachesRule()
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString)"))
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty)
    }

    func testDetectsCargoRegistryCache() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cargoCache = tmp.appending(path: ".cargo/registry/cache")
        try createDirWithContent(at: cargoCache)
        backdateItem(at: cargoCache, days: 1)
        backdateItem(at: cargoCache.appending(path: "content.bin"), days: 1)

        let rule = RustCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!

        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/.cargo/registry/cache") })
        XCTAssertEqual(findings.first?.riskLevel, .safe)
        XCTAssertEqual(findings.first?.category, .developerPackageCaches)
    }

    func testDoesNotFlagCargoBin() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create ~/.cargo/bin/ — should NOT be flagged
        let cargoBin = tmp.appending(path: ".cargo/bin")
        try createDirWithContent(at: cargoBin)
        backdateItem(at: cargoBin, days: 1)

        let rule = RustCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!
        XCTAssertTrue(findings.isEmpty, "~/.cargo/bin/ should NOT be flagged")
    }

    func testDetectsRustupDownloads() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let rustupDownloads = tmp.appending(path: ".rustup/downloads")
        try createDirWithContent(at: rustupDownloads)
        backdateItem(at: rustupDownloads, days: 1)
        backdateItem(at: rustupDownloads.appending(path: "content.bin"), days: 1)

        let rule = RustCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!
        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/.rustup/downloads") })
    }
}

// MARK: - GoCachesRule

final class GoCachesRuleTests: XCTestCase {

    func testReturnsEmptyWhenNoGoPathsExist() async {
        let rule = GoCachesRule()
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString)"))
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty)
    }

    func testDetectsGoBuildCache() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let goBuild = tmp.appending(path: "Library/Caches/go-build")
        try createDirWithContent(at: goBuild)
        backdateItem(at: goBuild, days: 1)
        backdateItem(at: goBuild.appending(path: "content.bin"), days: 1)

        let rule = GoCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!

        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/go-build") })
        XCTAssertEqual(findings.first?.riskLevel, .safe)
        XCTAssertEqual(findings.first?.category, .developerPackageCaches)
    }

    func testDetectsGoModuleCache() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let goModCache = tmp.appending(path: "go/pkg/mod/cache")
        try createDirWithContent(at: goModCache)
        backdateItem(at: goModCache, days: 1)
        backdateItem(at: goModCache.appending(path: "content.bin"), days: 1)

        let rule = GoCachesRule()
        let findings = await rule.customScan(environment: ScanEnvironment(homeDirectory: tmp))!
        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/mod/cache") })
    }
}

// MARK: - ProjectRootDiscovery (deduplication unit tests)

final class ProjectRootDiscoveryTests: XCTestCase {

    func testDeduplicatesNestedGitAtDepth2() {
        // ~/code/.git and ~/code/subdir/.git — the inner root should be collapsed
        // because depth difference == 1 ≤ 3.
        let outer = URL(fileURLWithPath: "/Users/user/code/.git")
        let inner = URL(fileURLWithPath: "/Users/user/code/subdir/.git")

        let result = ProjectRootDiscovery.deduplicate([outer, inner])
        let paths = result.map(\.path)

        XCTAssertTrue(paths.contains("/Users/user/code"), "Outer root should be present")
        XCTAssertFalse(paths.contains("/Users/user/code/subdir"), "Inner root at depth 2 should be collapsed")
    }

    func testKeepsDeeplyNestedIndependentProject() {
        // Root + a deeply nested project (4+ levels deep) — should keep both.
        // Avoid excluded path components (/vendor/, /node_modules/, etc.).
        let outer = URL(fileURLWithPath: "/Users/user/code/.git")
        let deep  = URL(fileURLWithPath: "/Users/user/code/services/external/lib/deep_project/.git")

        let result = ProjectRootDiscovery.deduplicate([outer, deep])
        let paths = result.map(\.path)

        XCTAssertTrue(paths.contains("/Users/user/code"), "Outer root should be present")
        XCTAssertTrue(paths.contains("/Users/user/code/services/external/lib/deep_project"),
                      "Deeply nested root (>3 levels) should be kept as independent project")
    }

    func testFiltersLibraryPath() {
        let libHit = URL(fileURLWithPath: "/Users/user/Library/Developer/Xcode/.git")
        let normalHit = URL(fileURLWithPath: "/Users/user/Projects/myapp/.git")

        let result = ProjectRootDiscovery.deduplicate([libHit, normalHit])
        let paths = result.map(\.path)

        XCTAssertFalse(paths.contains { $0.contains("/Library/") }, "/Library/ paths should be excluded")
        XCTAssertTrue(paths.contains("/Users/user/Projects/myapp"))
    }

    func testFiltersNodeModulesPath() {
        let nodeHit = URL(fileURLWithPath: "/Users/user/Projects/app/node_modules/somelib/.git")
        let normalHit = URL(fileURLWithPath: "/Users/user/Projects/app/.git")

        let result = ProjectRootDiscovery.deduplicate([nodeHit, normalHit])
        let paths = result.map(\.path)

        XCTAssertFalse(paths.contains { $0.contains("/node_modules/") }, "node_modules paths should be excluded")
        XCTAssertTrue(paths.contains("/Users/user/Projects/app"))
    }

    func testEmptyInputReturnsEmpty() {
        let result = ProjectRootDiscovery.deduplicate([])
        XCTAssertTrue(result.isEmpty)
    }

    func testNonGitSignalFileResolvesToParent() {
        // Package.swift → parent is the project root
        let signal = URL(fileURLWithPath: "/Users/user/Projects/mylib/Package.swift")
        let result = ProjectRootDiscovery.deduplicate([signal])
        let paths = result.map(\.path)
        XCTAssertTrue(paths.contains("/Users/user/Projects/mylib"))
    }

    /// Regression: SpotlightQueryRunner previously used `[weak self]` with no strong
    /// retention, so the runner was deallocated immediately, the async continuation
    /// never resumed, and developer/app scans hung forever after `project-artifacts-v2`.
    func testDiscoverCompletesWithoutHanging() async {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "pare_test_\(UUID().uuidString)/project-roots.json")
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }

        let discovery = ProjectRootDiscovery(storeURL: storeURL)
        // Spotlight timeout is 10s; allow a small margin for scheduling.
        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await discovery.discover()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        XCTAssertTrue(completed, "discover() hung past 15s — Spotlight continuation likely leaked")
        let date = await discovery.discoveryDate
        XCTAssertNotNil(date, "discover() should record lastDiscoveredAt on completion")
    }
}

// MARK: - ProjectArtifactsRule

final class ProjectArtifactsRuleTests: XCTestCase {

    func testReturnsEmptyWhenNoRootsConfigured() async throws {
        // Seed lastDiscoveredAt so discoverIfNeeded() skips live Spotlight (unit test isolation).
        let discovery = makeIsolatedDiscovery(manual: [], confirmed: [])
        let rule = ProjectArtifactsRule(discovery: discovery)
        let findings = await rule.customScan(environment: ScanEnvironment.current())
        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty, "No findings when no roots are configured")
    }

    func testDoesNotMarkDependencyTreesReclaimable() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        for name in ["node_modules", "venv", ".venv", ".bundle"] {
            let dir = tmp.appending(path: "myapp/\(name)")
            try createDirWithContent(at: dir)
            backdateItem(at: dir, days: 10)
        }

        let discovery = await makeDiscovery(root: tmp)
        let rule = ProjectArtifactsRule(discovery: discovery)
        let findings = await rule.customScan(environment: ScanEnvironment.current())!

        XCTAssertTrue(findings.isEmpty, "Dependency trees must never be reclaimable findings")
    }

    func testDetectsLocalCacheWithAgeGate() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cache = tmp.appending(path: "myapp/.cache")
        try createDirWithContent(at: cache)
        backdateItem(at: cache, days: 10)

        let discovery = await makeDiscovery(root: tmp)
        let rule = ProjectArtifactsRule(discovery: discovery)
        let findings = await rule.customScan(environment: ScanEnvironment.current())!

        XCTAssertTrue(findings.contains { $0.path.hasSuffix(".cache") && $0.riskLevel == .safe })
    }

    func testSkipsFreshArtifacts() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dist = tmp.appending(path: "myapp/dist")
        try createDirWithContent(at: dist)
        // No backdating — too fresh

        let discovery = await makeDiscovery(root: tmp)
        let rule = ProjectArtifactsRule(discovery: discovery)
        let findings = await rule.customScan(environment: ScanEnvironment.current())!
        XCTAssertTrue(findings.isEmpty, "Fresh artifact should not be flagged (age gate)")
    }

    func testDistIsReviewRisk() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dist = tmp.appending(path: "myapp/dist")
        try createDirWithContent(at: dist)
        backdateItem(at: dist, days: 10)

        let discovery = await makeDiscovery(root: tmp)
        let rule = ProjectArtifactsRule(discovery: discovery)
        let findings = await rule.customScan(environment: ScanEnvironment.current())!

        let distFinding = findings.first { $0.path.hasSuffix("/dist") }
        XCTAssertNotNil(distFinding)
        XCTAssertEqual(distFinding?.riskLevel, .review, "dist/ should be .review")
    }

    func testDoesNotDoubleCountNestedLocalCaches() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let outer = tmp.appending(path: "app/.cache")
        let inner = outer.appending(path: "subdir/.cache")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        // Visible file under outer — directorySize skips hidden paths.
        try Data(repeating: 0x00, count: 256).write(to: outer.appending(path: "blob.bin"))
        try Data(repeating: 0x00, count: 256).write(to: inner.appending(path: "inner.bin"))
        backdateItem(at: outer, days: 10)

        let discovery = await makeDiscovery(root: tmp)
        let rule = ProjectArtifactsRule(discovery: discovery)
        let findings = await rule.customScan(environment: ScanEnvironment.current())!

        let cacheFindings = findings.filter { $0.path.hasSuffix(".cache") }
        XCTAssertEqual(cacheFindings.count, 1, "Only outer .cache should be counted; nested is not walked")
    }

    func testSkipsWalkingIntoDependencyTrees() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // .cache buried inside node_modules must not surface (we skip the whole tree).
        let nested = tmp.appending(path: "app/node_modules/pkg/.cache")
        try createDirWithContent(at: nested)
        backdateItem(at: nested, days: 10)

        let discovery = await makeDiscovery(root: tmp)
        let rule = ProjectArtifactsRule(discovery: discovery)
        let findings = await rule.customScan(environment: ScanEnvironment.current())!

        XCTAssertTrue(findings.isEmpty, "Must not walk into node_modules to find nested caches")
    }

    func testDetectsPhase6ArtifactNames() async throws {
        let tmp = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let artifactNames = [".parcel-cache", ".turbo", ".nx"]
        for name in artifactNames {
            let dir = tmp.appending(path: "project/\(name)")
            try createDirWithContent(at: dir)
            backdateItem(at: dir, days: 10)
        }

        let discovery = await makeDiscovery(root: tmp)
        let rule = ProjectArtifactsRule(discovery: discovery)
        let findings = await rule.customScan(environment: ScanEnvironment.current())!

        for name in artifactNames {
            XCTAssertTrue(findings.contains { $0.path.hasSuffix(name) },
                          "\(name) should be detected as a build artifact")
        }
    }

    // MARK: Private helpers

    private func makeDiscovery(root: URL) async -> ProjectRootDiscovery {
        makeIsolatedDiscovery(manual: [root.path], confirmed: [])
    }

    /// Builds a discovery instance that will not invoke Spotlight in `discoverIfNeeded()`.
    private func makeIsolatedDiscovery(manual: [String], confirmed: [String]) -> ProjectRootDiscovery {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "pare_test_\(UUID().uuidString)/project-roots.json")
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ProjectRootsStore(
            confirmed: confirmed,
            excluded: [],
            manual: manual,
            lastDiscoveredAt: Date()
        )
        try? JSONEncoder().encode(store).write(to: storeURL)
        return ProjectRootDiscovery(storeURL: storeURL)
    }
}

// MARK: - ScanPolicy additions

final class Phase6ScanPolicyTests: XCTestCase {
    func testNewArtifactNamesRecognised() {
        let names = [".parcel-cache", ".turbo", ".nx"]
        for name in names {
            let url = URL(fileURLWithPath: "/Users/user/project/\(name)")
            XCTAssertTrue(ScanPolicy.isProjectArtifact(url), "\(name) should be a recognised project artifact")
        }
    }

    func testDeveloperPackageCacheMarkersContainsAllTools() {
        let markers = ScanPolicy.developerPackageCacheMarkers
        XCTAssertTrue(markers.contains { $0.contains(".pyenv") }, "pyenv marker missing")
        XCTAssertTrue(markers.contains { $0.contains(".cargo") }, "cargo marker missing")
        XCTAssertTrue(markers.contains { $0.contains(".rustup") }, "rustup marker missing")
        XCTAssertTrue(markers.contains { $0.contains("go/pkg/mod/cache") }, "go mod cache marker missing")
        XCTAssertTrue(markers.contains { $0.contains(".gradle") }, "gradle marker missing")
        XCTAssertTrue(markers.contains { $0.contains(".m2") }, "maven marker missing")
        XCTAssertTrue(markers.contains { $0.contains(".ivy2") }, "ivy2 marker missing")
        XCTAssertTrue(markers.contains { $0.contains(".gem/ruby") }, "gem cache marker missing")
        XCTAssertTrue(markers.contains { $0.contains(".bundle/cache") }, "bundler cache marker missing")
        XCTAssertTrue(markers.contains { $0.contains(".rbenv") }, "rbenv marker missing")
    }
}

// MARK: - Test helpers

private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func createDirWithContent(at url: URL, size: Int = 1024) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let data = Data(repeating: 0xAB, count: size)
    try data.write(to: url.appending(path: "content.bin"))
}

private func backdateItem(at url: URL, days: Int) {
    let date = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
    try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}
