import XCTest
@testable import PareCore

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
        tempDir = base.appending(path: "Library/Caches/com.pare.deepclean")
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

    // Search-index stores must never pass isLowImpactPath (would force reindex).
    func testSpotlightCacheIsNotLowImpact() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/com.apple.Spotlight/Cache.db")
        XCTAssertTrue(ScanPolicy.isSearchIndexSensitivePath(url))
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
        XCTAssertFalse(ScanPolicy.isReconstructibleCachePath(url))
    }

    func testHelpdCacheIsNotLowImpact() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/com.apple.helpd/Index")
        XCTAssertTrue(ScanPolicy.isSearchIndexSensitivePath(url))
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    func testSuggestionsIsSearchIndexSensitive() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Suggestions/some.db")
        XCTAssertTrue(ScanPolicy.isSearchIndexSensitivePath(url))
        XCTAssertFalse(ScanPolicy.isReconstructibleCachePath(url))
    }

    func testMediaAnalysisCacheIsSearchIndexSensitive() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/foo")
        XCTAssertTrue(ScanPolicy.isSearchIndexSensitivePath(url))
    }

    func testCoreSpotlightMetadataIsSearchIndexSensitive() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Metadata/CoreSpotlight/index.db")
        XCTAssertTrue(ScanPolicy.isSearchIndexSensitivePath(url))
        XCTAssertFalse(ScanPolicy.isLowImpactPath(url))
    }

    func testShouldWarnAboutSpotlightIndexingThresholds() {
        XCTAssertFalse(ScanPolicy.shouldWarnAboutSpotlightIndexing(itemCount: 10, totalBytes: 100))
        XCTAssertTrue(ScanPolicy.shouldWarnAboutSpotlightIndexing(
            itemCount: ScanPolicy.largeCleanSpotlightWarningItemThreshold,
            totalBytes: 0
        ))
        XCTAssertTrue(ScanPolicy.shouldWarnAboutSpotlightIndexing(
            itemCount: 1,
            totalBytes: ScanPolicy.largeCleanSpotlightWarningBytesThreshold
        ))
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

    // MARK: - isWrongPlatformBinary

    func testWrongPlatformBinariesRuleIsSafeRisk() {
        let rule = WrongPlatformBinariesRule()
        XCTAssertEqual(rule.riskLevel, .safe,
                       "Non-macOS installers/stubs cannot run on Mac — safe to auto-select for clean")
    }

    func testWrongPlatformDownloadsFindingIsSafe() async throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "pare_wp_\(UUID().uuidString)")
        let downloads = home.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let exe = downloads.appending(path: "Setup.exe")
        // Above downloadsMinBytes (512 KB).
        try Data(repeating: 0x00, count: 600 * 1024).write(to: exe)

        let rule = WrongPlatformBinariesRule()
        let env = ScanEnvironment(homeDirectory: home)
        let findings = await rule.customScan(environment: env) ?? []
        let hit = findings.first { $0.path.hasSuffix("Setup.exe") }
        XCTAssertNotNil(hit, "Should flag top-level .exe in Downloads")
        XCTAssertEqual(hit?.riskLevel, .safe)
        XCTAssertEqual(hit?.category, .temporaryFiles)
    }

    func testWindowsInstallerAtDownloadsTopLevelIsWrongPlatform() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let url = URL(fileURLWithPath: "\(home)/Downloads/Setup.exe")
        XCTAssertTrue(ScanPolicy.isWrongPlatformBinary(url),
                      ".exe directly in ~/Downloads must be recognised as wrong-platform")
    }

    func testLinuxInstallerAtDownloadsTopLevelIsWrongPlatform() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let url = URL(fileURLWithPath: "\(home)/Downloads/package.deb")
        XCTAssertTrue(ScanPolicy.isWrongPlatformBinary(url))
    }

    func testWindowsBinaryInNestedProjectDownloadsFolderIsNotWrongPlatform() {
        // A repo's downloads/ directory must NOT be matched — the bypass is ~/Downloads only.
        let url = URL(fileURLWithPath: "/Users/test/Projects/myapp/downloads/setup.exe")
        XCTAssertFalse(ScanPolicy.isWrongPlatformBinary(url),
                       "Nested project downloads/ must not bypass the protected-path guard")
    }

    func testWindowsBinaryInSubdirectoryOfDownloadsIsNotWrongPlatform() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let url = URL(fileURLWithPath: "\(home)/Downloads/subfolder/Setup.exe")
        XCTAssertFalse(ScanPolicy.isWrongPlatformBinary(url),
                       "Files inside subdirectories of ~/Downloads are not top-level and must not match")
    }

    func testMacOSInstallerIsNotWrongPlatform() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let url = URL(fileURLWithPath: "\(home)/Downloads/App.dmg")
        XCTAssertFalse(ScanPolicy.isWrongPlatformBinary(url),
                       ".dmg is a macOS format and must not be flagged")
    }

    func testApplicationSupportDownloadsSubdirIsNotWrongPlatform() {
        // SomeApp's internal "downloads" cache folder must not trigger the bypass.
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/SomeApp/downloads/plugin.dll")
        XCTAssertFalse(ScanPolicy.isWrongPlatformBinary(url))
    }

    // MARK: - Wrong-platform native directories (packages / tools)

    func testCompoundNonMacPlatformDirectoryNames() {
        XCTAssertTrue(ScanPolicy.isCompoundNonMacPlatformDirectoryName("win32-x64"))
        XCTAssertTrue(ScanPolicy.isCompoundNonMacPlatformDirectoryName("linux-arm64"))
        XCTAssertTrue(ScanPolicy.isCompoundNonMacPlatformDirectoryName("linux_x64"))
        XCTAssertFalse(ScanPolicy.isCompoundNonMacPlatformDirectoryName("darwin-arm64"))
        XCTAssertFalse(ScanPolicy.isCompoundNonMacPlatformDirectoryName("win32"))
        XCTAssertFalse(ScanPolicy.isCompoundNonMacPlatformDirectoryName("src"))
    }

    func testIsUnderWrongPlatformNativeDirectory() {
        let win32 = URL(fileURLWithPath: "/tmp/.npm/_npx/pkg/node_modules/onnx/bin/napi-v6/win32/x64/a.dll")
        let linux = URL(fileURLWithPath: "/tmp/prebuilds/linux-x64/binding.node")
        let darwin = URL(fileURLWithPath: "/tmp/prebuilds/darwin-arm64/binding.node")
        XCTAssertTrue(ScanPolicy.isUnderWrongPlatformNativeDirectory(win32))
        XCTAssertTrue(ScanPolicy.isUnderWrongPlatformNativeDirectory(linux))
        XCTAssertFalse(ScanPolicy.isUnderWrongPlatformNativeDirectory(darwin))
    }

    func testWrongPlatformRuleFlagsWholePlatformFoldersInEditorExtensions() async throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "pare_wp_dirs_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        // Multi-platform native bins under installed VS Code extensions.
        let bin = home.appending(path: ".vscode/extensions/ms-python.pylance/dist/bundled/bin")
        for name in ["darwin-arm64", "linux-x64", "win32-x64"] {
            let dir = bin.appending(path: name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x11, count: 1024).write(to: dir.appending(path: "server"))
        }

        // Simple sibling tree with darwin/linux/win32.
        let napi = home.appending(path: ".vscode/extensions/foo.bar/native")
        for platform in ["darwin", "linux", "win32"] {
            let arch = napi.appending(path: "\(platform)/arm64")
            try FileManager.default.createDirectory(at: arch, withIntermediateDirectories: true)
            let file = arch.appending(path: platform == "win32" ? "lib.dll" : "lib.bin")
            try Data(repeating: 0xAB, count: 4096).write(to: file)
        }

        // Source-only win32 without mac sibling — must NOT be flagged.
        let sourceWin32 = home.appending(path: ".vscode/extensions/foo.bar/lib/win32")
        try FileManager.default.createDirectory(at: sourceWin32, withIntermediateDirectories: true)
        try Data("print('hi')".utf8).write(to: sourceWin32.appending(path: "helpers.py"))

        let findings = await WrongPlatformBinariesRule().customScan(
            environment: ScanEnvironment(homeDirectory: home)
        ) ?? []
        let paths = findings.map(\.path)

        XCTAssertTrue(paths.contains { $0.hasSuffix("/bin/win32-x64") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/bin/linux-x64") })
        XCTAssertFalse(paths.contains { $0.hasSuffix("/bin/darwin-arm64") })

        XCTAssertTrue(paths.contains { $0.hasSuffix("/native/win32") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/native/linux") })
        XCTAssertFalse(paths.contains { $0.hasSuffix("/native/darwin") })
        XCTAssertFalse(paths.contains { $0.hasSuffix("/lib/win32") })
        XCTAssertFalse(paths.contains { $0.contains("lib.dll") })
    }

    func testPackageManagerCachesReportsNpxExtractAsWholeFolder() async throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "pare_npx_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        let extract = home.appending(path: ".npm/_npx/abc123")
        try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
        let file = extract.appending(path: "pkg/index.js")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 4096).write(to: file)
        let old = Date().addingTimeInterval(-2 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: extract.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)

        let findings = await PackageManagerCachesRule().customScan(
            environment: ScanEnvironment(homeDirectory: home)
        ) ?? []
        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/.npm/_npx/abc123") },
                      "npx extract should be one whole-folder finding. Got: \(findings.map(\.path))")
        XCTAssertFalse(findings.contains { $0.path.hasSuffix("index.js") })
    }

    func testReconstructibleCachePathMarkers() {
        XCTAssertTrue(ScanPolicy.isReconstructibleCachePath(
            URL(fileURLWithPath: "/Users/t/.npm/_npx/abc")))
        XCTAssertTrue(ScanPolicy.isReconstructibleCachePath(
            URL(fileURLWithPath: "/Users/t/Library/Caches/go-build")))
        XCTAssertTrue(ScanPolicy.isReconstructibleCachePath(
            URL(fileURLWithPath: "/Users/t/.cargo/registry/cache")))
        XCTAssertTrue(ScanPolicy.isReconstructibleCachePath(
            URL(fileURLWithPath: "/Users/t/go/pkg/mod/cache")))
        XCTAssertTrue(ScanPolicy.isReconstructibleCachePath(
            URL(fileURLWithPath: "/Users/t/Library/Caches/Yarn")))
        XCTAssertTrue(ScanPolicy.isReconstructibleCachePath(
            URL(fileURLWithPath: "/Users/t/.cache/opencode")))
        XCTAssertFalse(ScanPolicy.isReconstructibleCachePath(
            URL(fileURLWithPath: "/Users/t/Documents/project")))
    }

    func testIsWrongPlatformPathCoversNativeDirs() {
        let dir = URL(fileURLWithPath: "/Users/t/.vscode/extensions/pkg/win32")
        XCTAssertTrue(ScanPolicy.isWrongPlatformPath(dir))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let exe = URL(fileURLWithPath: "\(home)/Downloads/Setup.exe")
        XCTAssertTrue(ScanPolicy.isWrongPlatformPath(exe))
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

// MARK: - UserCachesRule: never report search-index caches

final class UserCachesSearchIndexProtectionTests: XCTestCase {
    func testDoesNotReportSpotlightHelpdSuggestionsOrMediaAnalysis() async throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "pare_user_caches_si_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        let fm = FileManager.default
        let paths: [(String, Int)] = [
            ("Library/Caches/com.apple.Spotlight", 2 * 1024 * 1024),
            ("Library/Caches/com.apple.helpd", 2 * 1024 * 1024),
            ("Library/Caches/com.example.safe", 2 * 1024 * 1024),
            ("Library/Suggestions", 2 * 1024 * 1024),
            ("Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches", 2 * 1024 * 1024),
        ]
        for (relative, size) in paths {
            let dir = home.appending(path: relative)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x42, count: size).write(to: dir.appending(path: "payload.bin"))
        }

        let findings = await UserCachesRule().customScan(
            environment: ScanEnvironment(homeDirectory: home)
        ) ?? []
        let joined = findings.map(\.path).joined(separator: "\n")

        XCTAssertFalse(joined.localizedCaseInsensitiveContains("com.apple.Spotlight"),
                       "Must not report Spotlight cache: \(joined)")
        XCTAssertFalse(joined.localizedCaseInsensitiveContains("com.apple.helpd"),
                       "Must not report helpd cache: \(joined)")
        XCTAssertFalse(joined.localizedCaseInsensitiveContains("Suggestions"),
                       "Must not report Library/Suggestions: \(joined)")
        XCTAssertFalse(joined.localizedCaseInsensitiveContains("mediaanalysisd"),
                       "Must not report mediaanalysisd: \(joined)")
        XCTAssertTrue(findings.contains { $0.path.localizedCaseInsensitiveContains("com.example.safe") },
                      "Ordinary user caches should still be reported: \(joined)")
    }
}
