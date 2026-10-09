import XCTest
@testable import PareCore

/// App user data and identity state sit next to reclaimable caches but must never reach the Trash.
final class ProtectedUserDataTests: XCTestCase {

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

    // MARK: - OpenCode

    func testOpenCodeUserDataNeverCleanable() {
        let share = "/Users/u/.local/share/opencode/"
        let personaMarkers = ScanPolicy.developerPackageCacheMarkers + ScanPolicy.aiToolSafePathMarkers
        let cases: [(relative: String, neverClean: Bool, cleanable: Bool)] = [
            ("storage", true, false),
            ("storage/session/x", true, false),
            ("opencode.db", true, false),
            ("opencode.db-wal", true, false),
            ("opencode.db-shm", true, false),
            ("auth.json", true, false),
            ("bin/opencode", false, false),  // outside the narrowed allow-list
            ("log/x", false, true),
            ("snapshot/x", false, true),
        ]
        for testCase in cases {
            let url = URL(fileURLWithPath: share + testCase.relative)
            XCTAssertEqual(ScanPolicy.isNeverCleanPath(url, customRoots: []), testCase.neverClean, testCase.relative)
            XCTAssertEqual(ScanPolicy.isLowImpactPath(url), testCase.cleanable, "low impact: \(testCase.relative)")
            XCTAssertEqual(
                ScanPolicy.matchesPersonaPath(url, allowedMarkers: personaMarkers),
                testCase.cleanable,
                "persona: \(testCase.relative)"
            )
        }
    }

    func testOpenCodeNamesOutsideItsShareDirAreNotProtected() {
        for path in ["/Users/u/Projects/app/storage", "/Users/u/Projects/app/opencode.db", "/Users/u/auth.json"] {
            XCTAssertFalse(ScanPolicy.isNeverCleanPath(URL(fileURLWithPath: path), customRoots: []), path)
        }
    }

    func testCleanupBlocksOpenCodeUserData() async throws {
        let share = tmp.appending(path: ".local/share/opencode")
        let paths = [
            try makeDirectory(share.appending(path: "storage/session")),
            try makeFile(share.appending(path: "opencode.db")),
            try makeFile(share.appending(path: "opencode.db-wal")),
            try makeFile(share.appending(path: "auth.json")),
        ]

        let result = try await dryRunClean(paths, category: .aiToolCaches)

        assertAllProtectedAsUserData(result, expected: paths)
    }

    // MARK: - Google identity caches

    func testUserCacheFolderProtectedNames() {
        let cases: [(name: String, protected: Bool)] = [
            ("GIPPseudonymousID", true),
            ("gippseudonymousid", true),
            ("CCTClearcutLogger", true),
            ("com.google.Keystone", true),
            ("org.mozilla.firefox", true),
            ("com.example.app", false),
            ("GIPPseudonymousID-old", false),
            ("google-drive-cache", false),
        ]
        for testCase in cases {
            XCTAssertEqual(ScanPolicy.isUserCacheFolderProtected(name: testCase.name), testCase.protected, testCase.name)
        }
    }

    func testUserCachesSkipsProtectedNames() async throws {
        let caches = tmp.appending(path: "Library/Caches")
        try makeDirectory(caches.appending(path: "GIPPseudonymousID"))
        try makeDirectory(caches.appending(path: "CCTClearcutLogger"))
        try makeDirectory(caches.appending(path: "com.google.Keystone"))
        let app = try makeDirectory(caches.appending(path: "com.example.app"))
        // Top-level files used to skip the name check entirely.
        try makeFile(caches.appending(path: "com.google.SoftwareUpdate.plist"), size: 300 * 1024)
        let file = try makeFile(caches.appending(path: "catalog.json"), size: 300 * 1024)
        let environment = ScanEnvironment(homeDirectory: tmp, systemApplicationDirectories: [])

        let findings = await UserCachesRule().customScan(environment: environment) ?? []

        XCTAssertEqual(Set(findings.map(\.path)), [app.path, file.path])
    }

    func testCleanupBlocksGoogleIdentityCaches() async throws {
        let caches = tmp.appending(path: "Library/Caches")
        let paths = [
            try makeDirectory(caches.appending(path: "GIPPseudonymousID")),
            try makeDirectory(caches.appending(path: "CCTClearcutLogger")),
            try makeFile(caches.appending(path: "CCTClearcutLogger/log.bin")),
        ]
        for url in paths {
            XCTAssertFalse(ScanPolicy.isLowImpactPath(url), url.path)
        }

        let result = try await dryRunClean(paths, category: .userCaches)

        assertAllProtectedAsUserData(result, expected: paths)
    }

    // MARK: - Helpers

    private func dryRunClean(_ urls: [URL], category: ScanCategory) async throws -> CleanupResult {
        let engine = CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: tmp.appending(path: "store")),
            projectRootsProvider: { [] },
            goCacheLocations: GoCacheLocations(query: { nil })
        )
        let findings = urls.map { url in
            ScanFinding(
                category: category, riskLevel: .safe, reason: "mislabelled", path: url.path,
                sizeBytes: 2048, lastUsed: Date().addingTimeInterval(-30 * 86400), confidence: 1.0
            )
        }
        return try await engine.clean(findings: findings, profileName: "test", dryRun: true)
    }

    private func assertAllProtectedAsUserData(
        _ result: CleanupResult, expected: [URL], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(result.succeeded.isEmpty, "\(result.succeeded.map(\.originalPath))", file: file, line: line)
        XCTAssertEqual(Set(result.skipped.map(\.path)), Set(expected.map(\.path)), file: file, line: line)
        for item in result.skipped {
            guard case .workingSetProtected = item.error else {
                XCTFail("expected .workingSetProtected for \(item.path), got \(item.error)", file: file, line: line)
                continue
            }
            let message = item.error.localizedDescription
            XCTAssertFalse(message.contains("Go cache"), message, file: file, line: line)
        }
    }

    @discardableResult
    private func makeDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 2048).write(to: url.appending(path: "entry.bin"))
        return URL(fileURLWithPath: url.path)
    }

    @discardableResult
    private func makeFile(_ url: URL, size: Int = 2048) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: size).write(to: url)
        return URL(fileURLWithPath: url.path)
    }
}
