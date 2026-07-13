import XCTest
@testable import PareCore

final class Phase5RuleTests: XCTestCase {

    // MARK: - BrowserExtendedArtifactsRule

    func testBrowserExtendedRuleReturnsEmptyWhenNoBrowsersPresent() async {
        let rule = BrowserExtendedArtifactsRule()
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/tmp/nonexistent_home_\(UUID().uuidString)"))
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings, "customScan should always return a non-nil array")
        XCTAssertTrue(findings!.isEmpty, "No findings when browser paths do not exist")
    }

    func testBrowserExtendedRuleProducesSafeShaderCacheFinding() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let shaderDir = tmp.appending(path: "Library/Application Support/Google/Chrome/GrShaderCache")
        try FileManager.default.createDirectory(at: shaderDir, withIntermediateDirectories: true)

        // Place a file old enough to pass the age gate.
        let dataFile = shaderDir.appending(path: "shader.bin")
        let content = Data(repeating: 0xAB, count: 1024)
        try content.write(to: dataFile)

        let oldDate = Date().addingTimeInterval(-(4 * 24 * 60 * 60))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: dataFile.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: shaderDir.path)

        let rule = BrowserExtendedArtifactsRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        let shaderFindings = findings!.filter { $0.riskLevel == .safe && $0.path.contains("GrShaderCache") }
        XCTAssertEqual(shaderFindings.count, 1)
        XCTAssertEqual(shaderFindings[0].category, .browserCaches)
    }

    func testBrowserExtendedRuleProducesReviewSessionFinding() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sessionDir = tmp.appending(path: "Library/Application Support/Google/Chrome/Default/Sessions")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let dataFile = sessionDir.appending(path: "session_0001")
        try Data(repeating: 0x00, count: 512).write(to: dataFile)

        let oldDate = Date().addingTimeInterval(-(5 * 24 * 60 * 60))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: dataFile.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: sessionDir.path)

        let rule = BrowserExtendedArtifactsRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        let reviewFindings = findings!.filter { $0.riskLevel == .review && $0.path.contains("Sessions") }
        XCTAssertEqual(reviewFindings.count, 1, "Session restore directory should be flagged as review")
    }

    func testBrowserExtendedRuleFlagsFreshSafeCaches() async throws {
        // SAFE regenerable caches (shader, Service Worker) skip the age gate so
        // active browsers still show reclaimable space (common Mac cleaners).
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let shaderDir = tmp.appending(path: "Library/Application Support/Google/Chrome/GrShaderCache")
        try FileManager.default.createDirectory(at: shaderDir, withIntermediateDirectories: true)
        try Data(repeating: 0x00, count: 512).write(to: shaderDir.appending(path: "x.bin"))

        let swDir = tmp.appending(path: "Library/Application Support/Google/Chrome/Default/Service Worker")
        try FileManager.default.createDirectory(at: swDir, withIntermediateDirectories: true)
        try Data(repeating: 0x01, count: 256).write(to: swDir.appending(path: "sw.bin"))

        let rule = BrowserExtendedArtifactsRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        let shaderFindings = findings!.filter { $0.path.contains("GrShaderCache") }
        XCTAssertEqual(shaderFindings.count, 1)
        XCTAssertEqual(shaderFindings.first?.riskLevel, .safe)

        let swFindings = findings!.filter { $0.path.contains("Service Worker") }
        XCTAssertEqual(swFindings.count, 1)
        XCTAssertEqual(swFindings.first?.riskLevel, .safe)
    }

    func testBrowserExtendedRuleAgeGatesLocalStorage() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let lsDir = tmp.appending(path: "Library/Application Support/Google/Chrome/Default/Local Storage")
        try FileManager.default.createDirectory(at: lsDir, withIntermediateDirectories: true)
        try Data(repeating: 0x02, count: 256).write(to: lsDir.appending(path: "ls.bin"))
        // Fresh Local Storage must remain hidden (credential-adjacent REVIEW data).

        let rule = BrowserExtendedArtifactsRule()
        let env = ScanEnvironment(homeDirectory: tmp)
        let findings = await rule.customScan(environment: env)
        let lsFindings = findings!.filter { $0.path.contains("Local Storage") }
        XCTAssertTrue(lsFindings.isEmpty, "Fresh Local Storage must not be flagged")
    }

    // MARK: - ProjectArtifactRule

    func testProjectArtifactRuleReturnsEmptyWhenNoPathsConfigured() async {
        let store = ProjectScanPathStore()
        store.setAll([])
        let rule = ProjectArtifactRule(pathStore: store)
        let env = ScanEnvironment.current()
        let findings = await rule.customScan(environment: env)
        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty, "No findings when no roots are configured")
    }

    func testProjectArtifactRuleDoesNotMarkDependencyTreesReclaimable() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let oldDate = Date().addingTimeInterval(-(8 * 24 * 60 * 60))
        for name in ["node_modules", "venv", ".venv", ".bundle"] {
            let dir = tmp.appending(path: "myapp/\(name)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x00, count: 2048).write(to: dir.appending(path: "x"))
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: dir.path)
        }

        let store = ProjectScanPathStore()
        store.setAll([tmp.path])
        let rule = ProjectArtifactRule(pathStore: store)
        let findings = await rule.customScan(environment: ScanEnvironment.current())

        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty, "Dependency trees must never be reclaimable findings")
    }

    func testProjectArtifactRuleDetectsLocalCache() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cache = tmp.appending(path: "myapp/.cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0x00, count: 2048).write(to: cache.appending(path: "data"))

        let oldDate = Date().addingTimeInterval(-(8 * 24 * 60 * 60))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cache.path)

        let store = ProjectScanPathStore()
        store.setAll([tmp.path])
        let rule = ProjectArtifactRule(pathStore: store)
        let findings = await rule.customScan(environment: ScanEnvironment.current())

        XCTAssertNotNil(findings)
        XCTAssertEqual(findings!.count, 1)
        XCTAssertTrue(findings![0].path.hasSuffix(".cache"))
        XCTAssertEqual(findings![0].riskLevel, .safe)
        XCTAssertEqual(findings![0].category, .projectArtifacts)
    }

    func testProjectArtifactRuleSkipsFreshArtifacts() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dist = tmp.appending(path: "myapp/dist")
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try Data(repeating: 0x00, count: 1024).write(to: dist.appending(path: "bundle.js"))
        // No date backdating — artifact is fresh.

        let store = ProjectScanPathStore()
        store.setAll([tmp.path])
        let rule = ProjectArtifactRule(pathStore: store)
        let env = ScanEnvironment.current()
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        XCTAssertTrue(findings!.isEmpty, "Fresh dist directory should not be flagged")
    }

    func testProjectArtifactRuleDetectsMultipleArtifactTypes() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let oldDate = Date().addingTimeInterval(-(10 * 24 * 60 * 60))
        // Local-only reclaimable dirs (deps like node_modules/venv must not appear).
        let artifactNames = ["dist", ".cache", "target", "__pycache__"]

        for name in artifactNames {
            let dir = tmp.appending(path: "project/\(name)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x00, count: 256).write(to: dir.appending(path: "x"))
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: dir.path)
        }

        let store = ProjectScanPathStore()
        store.setAll([tmp.path])
        let rule = ProjectArtifactRule(pathStore: store)
        let env = ScanEnvironment.current()
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        XCTAssertEqual(findings!.count, artifactNames.count, "Should find one finding per local artifact directory")
    }

    func testProjectArtifactRuleDoesNotRecurseIntoLocalArtifacts() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Outer local artifact with a nested same-name dir inside — only outer should be counted.
        let outer = tmp.appending(path: "app/.cache")
        let nestedVisible = outer.appending(path: "subdir")
        let inner = nestedVisible.appending(path: ".cache")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        // Visible file under outer so directorySize (which skips hidden) is non-zero.
        try Data(repeating: 0x00, count: 256).write(to: outer.appending(path: "blob.bin"))
        try Data(repeating: 0x00, count: 256).write(to: inner.appending(path: "inner.bin"))

        let oldDate = Date().addingTimeInterval(-(10 * 24 * 60 * 60))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: outer.path)

        let store = ProjectScanPathStore()
        store.setAll([tmp.path])
        let rule = ProjectArtifactRule(pathStore: store)
        let findings = await rule.customScan(environment: ScanEnvironment.current())

        XCTAssertNotNil(findings)
        let cachePaths = findings!.filter { $0.path.hasSuffix(".cache") }
        XCTAssertEqual(cachePaths.count, 1, "Only the outer .cache should be flagged; inner is not walked")
    }

    // MARK: - ScanPolicy additions

    func testIsProjectArtifactMatchesLocalNamesOnly() {
        let reclaimable = ["dist", "__pycache__", "build", ".gradle", ".next", ".nuxt", ".cache", "target"]
        for name in reclaimable {
            let url = URL(fileURLWithPath: "/Users/kelvin/Projects/myapp/\(name)")
            XCTAssertTrue(ScanPolicy.isProjectArtifact(url), "\(name) should be recognised as a local project artifact")
        }
        let deps = ["node_modules", "venv", ".venv", ".bundle"]
        for name in deps {
            let url = URL(fileURLWithPath: "/Users/kelvin/Projects/myapp/\(name)")
            XCTAssertFalse(ScanPolicy.isProjectArtifact(url), "\(name) is a dependency tree — not reclaimable")
            XCTAssertTrue(ScanPolicy.isProjectDependencyDirectory(name))
        }
    }

    func testIsProjectArtifactRejectsNormalDirs() {
        let names = ["src", "lib", "tests", "docs", "myapp"]
        for name in names {
            let url = URL(fileURLWithPath: "/Users/kelvin/Projects/\(name)")
            XCTAssertFalse(ScanPolicy.isProjectArtifact(url), "\(name) should NOT be a project artifact")
        }
    }

    // MARK: - BrowserCachesRule extended targets

    func testBrowserCachesRuleIncludesArcEdgeOpera() {
        let rule = BrowserCachesRule()
        let env = ScanEnvironment.current()
        let dirs = rule.targetDirectories(environment: env)
        let paths = dirs.map(\.path)
        XCTAssertTrue(paths.contains { $0.contains("Microsoft Edge") }, "Edge target missing")
        XCTAssertTrue(paths.contains { $0.contains("com.operasoftware.Opera") }, "Opera target missing")
        XCTAssertTrue(paths.contains { $0.contains("Arc") }, "Arc target missing")
    }
}
