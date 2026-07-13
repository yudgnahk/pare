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
        // active browsers still show reclaimable space (Mole/CleanMyMac parity).
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

    func testProjectArtifactRuleDetectsNodeModules() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let nodeModules = tmp.appending(path: "myapp/node_modules")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try Data(repeating: 0x00, count: 2048).write(to: nodeModules.appending(path: "package.json"))

        // Back-date so it passes the 7-day age gate.
        let oldDate = Date().addingTimeInterval(-(8 * 24 * 60 * 60))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: nodeModules.path)

        let store = ProjectScanPathStore()
        store.setAll([tmp.path])
        let rule = ProjectArtifactRule(pathStore: store)
        let env = ScanEnvironment.current()
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        XCTAssertEqual(findings!.count, 1)
        XCTAssertTrue(findings![0].path.hasSuffix("node_modules"))
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
        let artifactNames = ["node_modules", "dist", "venv"]

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
        XCTAssertEqual(findings!.count, artifactNames.count, "Should find one finding per artifact directory")
    }

    func testProjectArtifactRuleDoesNotRecurseIntoArtifacts() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "pare_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Nested node_modules inside node_modules — should only flag the outer one.
        let outer = tmp.appending(path: "app/node_modules")
        let inner = outer.appending(path: "some_package/node_modules")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data(repeating: 0x00, count: 256).write(to: inner.appending(path: "pkg.json"))

        let oldDate = Date().addingTimeInterval(-(10 * 24 * 60 * 60))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: outer.path)

        let store = ProjectScanPathStore()
        store.setAll([tmp.path])
        let rule = ProjectArtifactRule(pathStore: store)
        let env = ScanEnvironment.current()
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        let nodePaths = findings!.filter { $0.path.hasSuffix("node_modules") }
        XCTAssertEqual(nodePaths.count, 1, "Only the outer node_modules should be flagged; inner is pruned")
    }

    // MARK: - ScanPolicy additions

    func testIsProjectArtifactMatchesKnownNames() {
        let names = ["node_modules", "dist", "venv", ".venv", "__pycache__", "build", ".gradle", ".bundle", ".next", ".nuxt", ".cache"]
        for name in names {
            let url = URL(fileURLWithPath: "/Users/kelvin/Projects/myapp/\(name)")
            XCTAssertTrue(ScanPolicy.isProjectArtifact(url), "\(name) should be recognised as a project artifact")
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
