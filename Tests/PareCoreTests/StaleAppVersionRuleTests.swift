import XCTest
@testable import PareCore

// MARK: - compareVersionStrings

final class CompareVersionStringsTests: XCTestCase {
    func testAscending() {
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("1.0", "2.0"), .orderedAscending)
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("1.9", "2.0"), .orderedAscending)
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("1.0", "1.0.1"), .orderedAscending)
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("2024.3", "2025.1"), .orderedAscending)
    }

    func testDescending() {
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("2.0", "1.0"), .orderedDescending)
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("1.0.1", "1.0"), .orderedDescending)
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("2025.1", "2024.3"), .orderedDescending)
    }

    func testEqual() {
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("1.0", "1.0"), .orderedSame)
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("14.2.1", "14.2.1"), .orderedSame)
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("", ""), .orderedSame)
    }

    func testMissingComponentsTreatedAsZero() {
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("1", "1.0"), .orderedSame)
        XCTAssertEqual(FileSystemUtils.compareVersionStrings("1.0.0", "1.0"), .orderedSame)
    }
}

// MARK: - StaleAppVersionRule

final class StaleAppVersionRuleTests: XCTestCase {
    var tempDir: URL!
    var env: ScanEnvironment!
    let rule = StaleAppVersionRule()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "StaleAppVersionRuleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        env = ScanEnvironment(homeDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var appsDir: URL { tempDir.appending(path: "Applications").resolvingSymlinksInPath() }

    @discardableResult
    private func makeApp(
        name: String,
        bundleID: String?,
        version: String,
        inDir: URL? = nil
    ) throws -> URL {
        let dir = inDir ?? appsDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let appURL = dir.appending(path: "\(name).app")
        let contentsURL = appURL.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleVersion": version]
        if let bid = bundleID { plist["CFBundleIdentifier"] = bid }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appending(path: "Info.plist"))
        return appURL
    }

    // MARK: Category and risk

    func testCategoryAndRisk() {
        XCTAssertEqual(rule.category, .applications)
        XCTAssertEqual(rule.riskLevel, .review)
    }

    // MARK: SIP path excluded

    func testSIPPathNotScanned() {
        let dirs = rule.scanDirectories(environment: env)
        XCTAssertFalse(dirs.contains { $0.path.hasPrefix("/System/Applications") })
    }

    func testScansHomeApplicationsAndSystemApplications() {
        let dirs = rule.scanDirectories(environment: env)
        XCTAssertTrue(dirs.contains { $0.path == "/Applications" })
        XCTAssertTrue(dirs.contains { $0.path == tempDir.appending(path: "Applications").path })
    }

    // MARK: Same bundle ID — older flagged

    func testFlagsOlderVersionForSameBundleID() async throws {
        try makeApp(name: "MyApp 1.0", bundleID: "com.example.myapp", version: "1.0")
        try makeApp(name: "MyApp 2.0", bundleID: "com.example.myapp", version: "2.0")

        let findings = await rule.customScan(environment: env) ?? []
        let local = findings.filter { $0.path.hasPrefix(appsDir.path) }

        XCTAssertEqual(local.count, 1)
        let finding = try XCTUnwrap(local.first)
        XCTAssertTrue(finding.path.contains("MyApp 1.0.app"))
    }

    func testNewerVersionNotFlagged() async throws {
        try makeApp(name: "MyApp 1.0", bundleID: "com.example.myapp", version: "1.0")
        try makeApp(name: "MyApp 2.0", bundleID: "com.example.myapp", version: "2.0")

        let findings = await rule.customScan(environment: env) ?? []
        let local = findings.filter { $0.path.hasPrefix(appsDir.path) }

        XCTAssertFalse(local.contains { $0.path.contains("MyApp 2.0.app") })
    }

    // MARK: Same bundle ID, same version — neither flagged

    func testSkipsGroupWhenAllVersionsIdentical() async throws {
        try makeApp(name: "MyApp A", bundleID: "com.example.myapp", version: "1.0")
        try makeApp(name: "MyApp B", bundleID: "com.example.myapp", version: "1.0")

        let findings = await rule.customScan(environment: env) ?? []
        let local = findings.filter { $0.path.hasPrefix(appsDir.path) }

        XCTAssertEqual(local.count, 0)
    }

    // MARK: Missing bundle ID — name-based fallback

    func testFallsBackToNormalizedNameNoBundleID() async throws {
        try makeApp(name: "Sketch", bundleID: nil, version: "1.0")
        try makeApp(name: "Sketch 2", bundleID: nil, version: "2.0")

        let findings = await rule.customScan(environment: env) ?? []
        let local = findings.filter { $0.path.hasPrefix(appsDir.path) }

        XCTAssertEqual(local.count, 1)
        let finding = try XCTUnwrap(local.first)
        XCTAssertTrue(finding.path.contains("Sketch.app"))
    }

    func testNormalizesBetaSuffix() async throws {
        try makeApp(name: "Firefox", bundleID: nil, version: "120.0")
        try makeApp(name: "Firefox Beta", bundleID: nil, version: "121.0")

        let findings = await rule.customScan(environment: env) ?? []
        let local = findings.filter { $0.path.hasPrefix(appsDir.path) }

        XCTAssertEqual(local.count, 1)
        let finding = try XCTUnwrap(local.first)
        XCTAssertTrue(finding.path.contains("Firefox.app"))
    }

    // MARK: Single app — not flagged

    func testSingleInstallNotFlagged() async throws {
        try makeApp(name: "Solo", bundleID: "com.example.solo", version: "1.0")

        let findings = await rule.customScan(environment: env) ?? []
        let local = findings.filter { $0.path.hasPrefix(appsDir.path) }

        XCTAssertEqual(local.count, 0)
    }

    // MARK: Three-component version ordering

    func testThreeComponentVersionOrdering() async throws {
        try makeApp(name: "App 1.0.0", bundleID: "com.example.app", version: "1.0.0")
        try makeApp(name: "App 1.0.1", bundleID: "com.example.app", version: "1.0.1")
        try makeApp(name: "App 1.1.0", bundleID: "com.example.app", version: "1.1.0")

        let findings = await rule.customScan(environment: env) ?? []
        let local = findings.filter { $0.path.hasPrefix(appsDir.path) }

        XCTAssertEqual(local.count, 2)
        let flaggedPaths = local.map { $0.path }
        XCTAssertTrue(flaggedPaths.contains { $0.contains("App 1.0.0.app") })
        XCTAssertTrue(flaggedPaths.contains { $0.contains("App 1.0.1.app") })
        XCTAssertFalse(flaggedPaths.contains { $0.contains("App 1.1.0.app") })
    }
}
