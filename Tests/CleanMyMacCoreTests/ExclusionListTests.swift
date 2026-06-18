import XCTest
@testable import App BCore

// MARK: - ExclusionList model tests

final class ExclusionListTests: XCTestCase {

    // MARK: - ExclusionEntry.matches

    func testExactMatchReturnsTrueForIdenticalPath() {
        let entry = ExclusionEntry(path: "/Users/test/file.bin", matchType: .exact)
        XCTAssertTrue(entry.matches("/Users/test/file.bin"))
    }

    func testExactMatchIsCaseInsensitive() {
        let entry = ExclusionEntry(path: "/Users/Test/File.bin", matchType: .exact)
        XCTAssertTrue(entry.matches("/Users/test/file.bin"))
    }

    func testExactMatchReturnsFalseForSubpath() {
        let entry = ExclusionEntry(path: "/Users/test/dir", matchType: .exact)
        XCTAssertFalse(entry.matches("/Users/test/dir/file.bin"))
    }

    func testPrefixMatchReturnsTrueForSubpath() {
        let entry = ExclusionEntry(path: "/Users/test/dir", matchType: .prefix)
        XCTAssertTrue(entry.matches("/Users/test/dir/file.bin"))
        XCTAssertTrue(entry.matches("/Users/test/dir"))
    }

    func testPrefixMatchReturnsFalseForUnrelatedPath() {
        let entry = ExclusionEntry(path: "/Users/test/dir", matchType: .prefix)
        XCTAssertFalse(entry.matches("/Users/other/dir/file.bin"))
    }

    // MARK: - ExclusionList.isExcluded

    func testIsExcludedReturnsFalseWhenEmpty() {
        let list = ExclusionList.empty
        XCTAssertFalse(list.isExcluded("/Users/test/Library/Caches/foo.bin"))
    }

    func testIsExcludedReturnsTrueWhenEntryMatches() {
        var list = ExclusionList()
        list.add(ExclusionEntry(path: "/Users/test/Library/Caches/myapp", matchType: .prefix))
        XCTAssertTrue(list.isExcluded("/Users/test/Library/Caches/myapp/v1/data.bin"))
    }

    func testIsExcludedReturnsFalseWhenNoEntryMatches() {
        var list = ExclusionList()
        list.add(ExclusionEntry(path: "/Users/test/Library/Caches/myapp", matchType: .prefix))
        XCTAssertFalse(list.isExcluded("/Users/test/Library/Caches/otherapp/data.bin"))
    }

    func testAddDeduplicatesIdenticalEntries() {
        var list = ExclusionList()
        let e1 = ExclusionEntry(path: "/Users/test/dir", matchType: .prefix)
        let e2 = ExclusionEntry(path: "/Users/test/dir", matchType: .prefix)
        list.add(e1)
        list.add(e2)
        XCTAssertEqual(list.entries.count, 1)
    }

    func testRemoveDeletesMatchingEntry() {
        var list = ExclusionList()
        let entry = ExclusionEntry(path: "/Users/test/dir", matchType: .prefix)
        list.add(entry)
        XCTAssertEqual(list.entries.count, 1)
        list.remove(id: entry.id)
        XCTAssertEqual(list.entries.count, 0)
    }

    // MARK: - ExclusionStore round-trip

    func testExclusionStorePersistsAndLoads() throws {
        let tmpFile = URL(fileURLWithPath: "/private/tmp/exclusion-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let store = ExclusionStore(fileURL: tmpFile)
        var list = ExclusionList()
        list.add(ExclusionEntry(path: "/Users/test/skip-me", matchType: .prefix, note: "Test note"))
        try store.save(list)

        let loaded = try store.load()
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.path, "/Users/test/skip-me")
        XCTAssertEqual(loaded.entries.first?.note, "Test note")
        XCTAssertTrue(loaded.isExcluded("/Users/test/skip-me/subdir/file.bin"))
    }

    func testExclusionStoreReturnsEmptyWhenFileMissing() throws {
        let tmpFile = URL(fileURLWithPath: "/private/tmp/exclusion-nonexistent-\(UUID().uuidString).json")
        let store = ExclusionStore(fileURL: tmpFile)
        let list = try store.load()
        XCTAssertTrue(list.entries.isEmpty)
    }

    func testExclusionStoreAddEntryConvenienceMethod() throws {
        let tmpFile = URL(fileURLWithPath: "/private/tmp/exclusion-add-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let store = ExclusionStore(fileURL: tmpFile)
        try store.addEntry(ExclusionEntry(path: "/Users/test/a"))
        try store.addEntry(ExclusionEntry(path: "/Users/test/b"))

        let list = try store.load()
        XCTAssertEqual(list.entries.count, 2)
    }

    func testExclusionStoreRemoveEntryConvenienceMethod() throws {
        let tmpFile = URL(fileURLWithPath: "/private/tmp/exclusion-remove-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let store = ExclusionStore(fileURL: tmpFile)
        let entry = ExclusionEntry(path: "/Users/test/removable")
        try store.addEntry(entry)
        try store.removeEntry(id: entry.id)

        let list = try store.load()
        XCTAssertTrue(list.entries.isEmpty)
    }

    // MARK: - ScanRunner exclusion integration

    func testScanRunnerRespectsExclusionList() async {
        let targetDir = URL(fileURLWithPath: "/tmp/exclusion-runner-test")
        let includedFile = ScannedFile(url: URL(fileURLWithPath: "/tmp/exclusion-runner-test/keep.bin"),
                                       sizeBytes: 1000, lastModified: nil)
        let excludedFile = ScannedFile(url: URL(fileURLWithPath: "/tmp/exclusion-runner-test/skip.bin"),
                                        sizeBytes: 2000, lastModified: nil)

        struct AllIncludeRule: ScanRule {
            let id = "all-include"
            let title = "All Include"
            let reason = "Test"
            let category: ScanCategory = .userCaches
            let riskLevel: RiskLevel = .safe
            let confidence: Double = 1.0
            func targetDirectories(environment: ScanEnvironment) -> [URL] {
                [URL(fileURLWithPath: "/tmp/exclusion-runner-test")]
            }
            func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { true }
        }

        struct FixedTraversal: FileTraversing {
            let files: [ScannedFile]
            func collectFiles(in directories: [URL]) async -> [ScannedFile] { files }
        }

        var exclusionList = ExclusionList()
        exclusionList.add(ExclusionEntry(path: excludedFile.url.path, matchType: .exact))

        let runner = ScanRunner(
            environment: ScanEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/test")),
            traversal: FixedTraversal(files: [includedFile, excludedFile]),
            exclusionList: exclusionList
        )

        let report = await runner.run(rules: [AllIncludeRule()])
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings.first?.path, includedFile.url.path)
        XCTAssertEqual(report.findings.first?.sizeBytes, 1000)
    }
}

// MARK: - Deep Clean tests

final class DeepCleanTests: XCTestCase {

    private var tempDir: URL!
    private var storeDir: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: "/private/tmp/DeepCleanTests-\(UUID().uuidString)")
        tempDir = base.appending(path: "Library/Caches/com.cleanmymac.deepclean")
        storeDir = URL(fileURLWithPath: "/private/tmp/DeepCleanStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        let testRoot = tempDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testRoot)
        try? FileManager.default.removeItem(at: storeDir)
    }

    private func makeTempFile(
        name: String,
        riskLevel: RiskLevel = .safe,
        ageSeconds: TimeInterval = 5 * 24 * 60 * 60
    ) throws -> (url: URL, finding: ScanFinding) {
        let url = tempDir.appendingPathComponent(name)
        let data = Data(repeating: 0x41, count: 512)
        try data.write(to: url)
        let oldDate = Date().addingTimeInterval(-ageSeconds)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        let finding = ScanFinding(
            category: .userCaches,
            riskLevel: riskLevel,
            reason: "Test \(riskLevel.rawValue) finding",
            path: url.path,
            sizeBytes: 512,
            lastUsed: oldDate,
            confidence: 0.9
        )
        return (url, finding)
    }

    private func makeStore() -> CleanupTransactionStore {
        CleanupTransactionStore(directory: storeDir)
    }

    // Deep clean includes safe + review, excludes advanced.
    func testDeepCleanIncludesSafeAndReview() async throws {
        let (_, safeFile) = try makeTempFile(name: "dc-safe.bin", riskLevel: .safe)
        let (_, reviewFile) = try makeTempFile(name: "dc-review.bin", riskLevel: .review)
        let (_, advancedFile) = try makeTempFile(name: "dc-advanced.bin", riskLevel: .advanced)
        let engine = CleanupEngine(store: makeStore())

        let result = try await engine.deepClean(
            findings: [safeFile, reviewFile, advancedFile],
            profileName: "test",
            dryRun: true,
            confirmed: true
        )

        // Safe + review should be candidates; advanced is always blocked.
        XCTAssertEqual(result.succeeded.count, 2)
        let paths = Set(result.succeeded.map(\.originalPath))
        XCTAssertTrue(paths.contains(safeFile.path))
        XCTAssertTrue(paths.contains(reviewFile.path))
        XCTAssertFalse(paths.contains(advancedFile.path))
    }

    func testDeepCleanWithoutConfirmationReturnsEmpty() async throws {
        let (_, safeFile) = try makeTempFile(name: "dc-unconfirmed.bin", riskLevel: .safe)
        let engine = CleanupEngine(store: makeStore())

        let result = try await engine.deepClean(
            findings: [safeFile],
            profileName: "test",
            confirmed: false
        )

        // Nothing should happen without explicit confirmation.
        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertNil(result.transaction)
        XCTAssertTrue(FileManager.default.fileExists(atPath: safeFile.path))
    }

    func testDeepCleanMovesReviewFileToTrash() async throws {
        let (_, reviewFile) = try makeTempFile(name: "dc-real-review.bin", riskLevel: .review)
        let engine = CleanupEngine(store: makeStore())

        let result = try await engine.deepClean(
            findings: [reviewFile],
            profileName: "test",
            confirmed: true
        )

        XCTAssertEqual(result.succeeded.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reviewFile.path),
                       "Review-risk file should have been moved to Trash")
    }
}

// MARK: - Path safety regression tests

final class PathSafetyTests: XCTestCase {

    // Protected paths must be blocked by isLowImpactPath.
    func testDocumentsPathIsBlocked() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/report.pdf")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    func testDesktopPathIsBlocked() {
        let url = URL(fileURLWithPath: "/Users/test/Desktop/screenshot.png")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    func testDownloadsPathIsBlocked() {
        let url = URL(fileURLWithPath: "/Users/test/Downloads/installer.dmg")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    func testGitDirectoryIsBlocked() {
        let url = URL(fileURLWithPath: "/Users/test/myproject/.git/config")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    // Valid cache paths must pass isLowImpactPath.
    func testLibraryCachesPathPasses() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.app/data.bin")
        XCTAssertTrue(ScanPolicy.isLowImpactPath(url))
    }

    func testLibraryLogsPathPasses() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Logs/SomeApp/debug.log")
        XCTAssertTrue(ScanPolicy.isLowImpactPath(url))
    }

    func testTmpPathPasses() {
        let url = URL(fileURLWithPath: "/private/tmp/scratch.bin")
        XCTAssertTrue(ScanPolicy.isLowImpactPath(url))
    }

    // Sensitive data markers must always be blocked.
    func testCookiesFileIsBlocked() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/com.example/cookies.db")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    func testHistoryFileIsBlocked() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/com.example/history.db")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    // App-state sensitive markers are never deleted.
    func testVSCodeSettingsJsonIsBlocked() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/Code/User/settings.json")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    func testSSHKeysAreBlocked() {
        let url = URL(fileURLWithPath: "/Users/test/.ssh/id_ed25519")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    func testGitCredentialsAreBlocked() {
        let url = URL(fileURLWithPath: "/Users/test/.git-credentials")
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    // Developer persona path markers
    func testJetBrainsLogsPassDeveloperPersonaPath() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Logs/JetBrains/GoLand2024.1/idea.log")
        let passes = ScanPolicy.matchesPersonaPath(url, allowedMarkers: ScanPolicy.developerSafePathMarkers)
        XCTAssertTrue(passes, "JetBrains log path should pass developer safe persona markers")
    }

    func testVSCodeCachedVSIXPassesDeveloperPersonaPath() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/Code/CachedExtensionVSIXs/extension.vsix")
        let passes = ScanPolicy.matchesPersonaPath(url, allowedMarkers: ScanPolicy.developerSafePathMarkers)
        XCTAssertTrue(passes)
    }

    func testVSCodeSettingsJsonIsBlockedByPersonaPath() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/Code/User/settings.json")
        let passes = ScanPolicy.matchesPersonaPath(url, allowedMarkers: ScanPolicy.developerSafePathMarkers)
        XCTAssertFalse(passes, "VS Code settings.json is an app-state-sensitive marker and must be blocked")
    }
}

// MARK: - VSCodeDuplicateExtensionsRule tests

final class VSCodeDuplicateExtensionsTests: XCTestCase {
    /// Root of the fake home tree: /private/tmp/vscode-ext-test-<uuid>
    private var fakeHome: URL!
    /// ~/.vscode/extensions inside fakeHome
    private var extensionsDir: URL!

    override func setUpWithError() throws {
        fakeHome = URL(fileURLWithPath: "/private/tmp/vscode-ext-test-\(UUID().uuidString)")
        extensionsDir = fakeHome.appending(path: ".vscode/extensions")
        try FileManager.default.createDirectory(at: extensionsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeHome)
    }

    @discardableResult
    private func makeExtDir(name: String, ageSeconds: TimeInterval = 5 * 24 * 60 * 60) throws -> URL {
        let dir = extensionsDir.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Create a dummy file inside for size calculation.
        let file = dir.appendingPathComponent("extension.js")
        try Data(repeating: 0x41, count: 1024).write(to: file)
        // Back-date modification time.
        let oldDate = Date().addingTimeInterval(-ageSeconds)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: dir.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
        return dir
    }

    func testDuplicateExtensionsAreDetected() async throws {
        // Create two versions of the same extension — older should be flagged.
        try makeExtDir(name: "ms-python.python-2023.1.0")
        try makeExtDir(name: "ms-python.python-2024.2.0")
        // A different extension — not a duplicate.
        try makeExtDir(name: "esbenp.prettier-vscode-10.0.0")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let rule = VSCodeDuplicateExtensionsRule()
        let findings = await rule.customScan(environment: env)

        // Should have exactly 1 finding: the older ms-python.python version.
        XCTAssertNotNil(findings)
        guard let findings = findings else { return }
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].path.contains("ms-python.python-2023.1.0"),
                      "Older version should be flagged, got: \(findings[0].path)")
        XCTAssertTrue(findings[0].reason.contains("2024.2.0"),
                      "Reason should mention newer version, got: \(findings[0].reason)")
    }

    func testNoDuplicatesProducesNoFindings() async throws {
        try makeExtDir(name: "ms-python.python-2024.2.0")
        try makeExtDir(name: "esbenp.prettier-vscode-10.0.0")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let rule = VSCodeDuplicateExtensionsRule()
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        XCTAssertEqual(findings?.count, 0)
    }

    func testMissingExtensionsDirProducesEmptyFindings() async throws {
        // Point to a home with no .vscode/extensions directory.
        let emptyHome = URL(fileURLWithPath: "/private/tmp/vscode-empty-home-\(UUID().uuidString)")
        let env = ScanEnvironment(homeDirectory: emptyHome)
        let rule = VSCodeDuplicateExtensionsRule()
        let findings = await rule.customScan(environment: env)

        XCTAssertNotNil(findings)
        XCTAssertEqual(findings?.count, 0)
    }

    func testThreeVersionsKeepsNewestFlagsOtherTwo() async throws {
        try makeExtDir(name: "ms-python.python-2022.0.0")
        try makeExtDir(name: "ms-python.python-2023.1.0")
        try makeExtDir(name: "ms-python.python-2024.2.0")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await VSCodeDuplicateExtensionsRule().customScan(environment: env)

        XCTAssertEqual(findings?.count, 2)
        let paths = findings?.map(\.path) ?? []
        XCTAssertTrue(paths.contains(where: { $0.contains("2022.0.0") }))
        XCTAssertTrue(paths.contains(where: { $0.contains("2023.1.0") }))
        XCTAssertFalse(paths.contains(where: { $0.contains("2024.2.0") }),
                       "Newest version must not be flagged")
    }

    func testRecentOlderExtensionIsNotFlagged() async throws {
        // Older version modified only 1 day ago — within the 3-day minimum-age gate.
        try makeExtDir(name: "ms-python.python-2023.1.0", ageSeconds: 1 * 24 * 60 * 60)
        try makeExtDir(name: "ms-python.python-2024.2.0")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await VSCodeDuplicateExtensionsRule().customScan(environment: env)

        XCTAssertEqual(findings?.count, 0)
    }

    func testRiskLevelIsSafe() async throws {
        try makeExtDir(name: "ms-python.python-2023.1.0")
        try makeExtDir(name: "ms-python.python-2024.2.0")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await VSCodeDuplicateExtensionsRule().customScan(environment: env)

        XCTAssertEqual(findings?.first?.riskLevel, .safe)
    }

    func testUnparsableDirectoriesAreIgnored() async throws {
        // Directories that don't follow <publisher>.<name>-<semver> are skipped.
        try FileManager.default.createDirectory(
            at: extensionsDir.appending(path: "no-version-here"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: extensionsDir.appending(path: ".obsolete"),
            withIntermediateDirectories: true)
        try makeExtDir(name: "ms-python.python-2024.2.0")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await VSCodeDuplicateExtensionsRule().customScan(environment: env)

        XCTAssertEqual(findings?.count, 0)
    }

    func testMultipleExtensionsEachWithDuplicates() async throws {
        try makeExtDir(name: "ms-python.python-2023.1.0")
        try makeExtDir(name: "ms-python.python-2024.2.0")
        try makeExtDir(name: "esbenp.prettier-vscode-9.0.0")
        try makeExtDir(name: "esbenp.prettier-vscode-10.0.0")
        // Unique extension — no duplicate.
        try makeExtDir(name: "golang.go-0.41.0")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await VSCodeDuplicateExtensionsRule().customScan(environment: env)

        XCTAssertEqual(findings?.count, 2)
        let paths = findings?.map(\.path) ?? []
        XCTAssertTrue(paths.contains(where: { $0.contains("ms-python.python-2023.1.0") }))
        XCTAssertTrue(paths.contains(where: { $0.contains("esbenp.prettier-vscode-9.0.0") }))
    }
}

final class JetBrainsStaleVersionTests: XCTestCase {
    private var fakeHome: URL!
    private var jetbrainsDir: URL!

    private static let staleAge: TimeInterval = 100 * 24 * 60 * 60  // 100 days — over 90-day gate
    private static let freshAge: TimeInterval = 10 * 24 * 60 * 60   // 10 days — under 90-day gate

    override func setUpWithError() throws {
        fakeHome = URL(fileURLWithPath: "/private/tmp/jb-stale-test-\(UUID().uuidString)")
        jetbrainsDir = fakeHome
            .appending(path: "Library/Application Support/JetBrains")
        try FileManager.default.createDirectory(at: jetbrainsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeHome)
    }

    @discardableResult
    private func makeVersionDir(name: String, ageSeconds: TimeInterval = staleAge) throws -> URL {
        let dir = jetbrainsDir.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("dummy.bin")
        try Data(repeating: 0x41, count: 4096).write(to: file)
        let oldDate = Date().addingTimeInterval(-ageSeconds)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: dir.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
        return dir
    }

    func testOlderVersionFlaggedWhenNewerExists() async throws {
        try makeVersionDir(name: "GoLand2024.3")
        try makeVersionDir(name: "GoLand2025.1")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await JetBrainsStaleVersionRule().customScan(environment: env)

        XCTAssertNotNil(findings)
        guard let findings else { return }
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].path.contains("GoLand2024.3"),
                      "Older GoLand version should be flagged, got: \(findings[0].path)")
        XCTAssertTrue(findings[0].reason.contains("2025.1"),
                      "Reason should mention the newer version, got: \(findings[0].reason)")
        XCTAssertEqual(findings[0].riskLevel, .safe)
    }

    func testSingleVersionProducesNoFindings() async throws {
        try makeVersionDir(name: "GoLand2025.1")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await JetBrainsStaleVersionRule().customScan(environment: env)

        XCTAssertEqual(findings?.count, 0)
    }

    func testRecentOlderVersionIsNotFlagged() async throws {
        // Old folder is only 10 days old — within the 90-day minimum-age gate.
        try makeVersionDir(name: "GoLand2024.3", ageSeconds: Self.freshAge)
        try makeVersionDir(name: "GoLand2025.1")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await JetBrainsStaleVersionRule().customScan(environment: env)

        XCTAssertEqual(findings?.count, 0)
    }

    func testNonVersionedFoldersAreIgnored() async throws {
        // Daemon, consentOptions, etc. should not parse as versioned folders.
        try FileManager.default.createDirectory(
            at: jetbrainsDir.appending(path: "Daemon"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: jetbrainsDir.appending(path: "consentOptions"), withIntermediateDirectories: true)
        try makeVersionDir(name: "GoLand2025.1")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await JetBrainsStaleVersionRule().customScan(environment: env)

        XCTAssertEqual(findings?.count, 0)
    }

    func testDifferentProductsAreGroupedIndependently() async throws {
        // One GoLand and one DataGrip — each only has one version, so no findings.
        try makeVersionDir(name: "GoLand2025.1")
        try makeVersionDir(name: "DataGrip2024.3")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await JetBrainsStaleVersionRule().customScan(environment: env)

        XCTAssertEqual(findings?.count, 0)
    }

    func testMultipleProductsEachWithStaleVersions() async throws {
        try makeVersionDir(name: "GoLand2024.3")
        try makeVersionDir(name: "GoLand2025.1")
        try makeVersionDir(name: "DataGrip2023.3")
        try makeVersionDir(name: "DataGrip2024.3")

        let env = ScanEnvironment(homeDirectory: fakeHome)
        let findings = await JetBrainsStaleVersionRule().customScan(environment: env)

        XCTAssertEqual(findings?.count, 2)
        let paths = findings?.map(\.path) ?? []
        XCTAssertTrue(paths.contains(where: { $0.contains("GoLand2024.3") }))
        XCTAssertTrue(paths.contains(where: { $0.contains("DataGrip2023.3") }))
    }

    func testMissingJetBrainsDirProducesEmptyFindings() async throws {
        let emptyHome = URL(fileURLWithPath: "/private/tmp/jb-empty-home-\(UUID().uuidString)")
        let env = ScanEnvironment(homeDirectory: emptyHome)
        let findings = await JetBrainsStaleVersionRule().customScan(environment: env)

        XCTAssertNotNil(findings)
        XCTAssertEqual(findings?.count, 0)
    }
}
