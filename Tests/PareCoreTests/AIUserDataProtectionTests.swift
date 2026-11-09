import XCTest
@testable import PareCore

/// AI tool sessions, model stores and compiled Neural Engine bundles must never reach the Trash.
final class AIUserDataProtectionTests: XCTestCase {

    private var tmp: URL!

    private let protectedRelatives = [
        ".ollama/models",
        ".ollama/models/blobs/sha256-abc",
        ".cache/huggingface",
        ".cache/huggingface/hub/models--x/blobs/abc",
        ".claude/projects",
        ".claude/projects/-Users-u-app/session.jsonl",
        ".claude/todos/t.json",
        ".claude/plans/p.md",
        ".codex/sessions/2026/01/rollout.jsonl",
        ".codex/archived_sessions/old.jsonl",
        ".continue/sessions/s.json",
        ".copilot/session-state/s",
        "Library/Caches/com.apple.e5rt.e5bundlecache/x",
    ]

    private let lookAlikeRelatives = [
        ".ollama-backup/models",
        ".ollama/logs",
        ".cache/huggingface-cli-old",
        ".cache/huggingface-cli-old/x",
        ".claude/projects-old/x",
        ".claude/cache",
        ".codex/sessions-old/x",
        ".codex/.tmp/bundled-marketplaces/openai-bundled.staging-1",
        "Library/Caches/com.apple.e5rt.e5bundlecache-old/x",
    ]

    override func setUpWithError() throws {
        tmp = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Policy

    func testEveryAIDataPathIsNeverClean() {
        for relative in protectedRelatives {
            let url = URL(fileURLWithPath: "/Users/u/" + relative)
            XCTAssertTrue(ScanPolicy.isNeverCleanPath(url, customRoots: [], aiDataRoots: []), relative)
            XCTAssertTrue(ScanPolicy.isProtectedUserDataPath(url, aiDataRoots: []), relative)
        }
    }

    func testLookAlikePathsStayAllowed() {
        for relative in lookAlikeRelatives {
            let url = URL(fileURLWithPath: "/Users/u/" + relative)
            XCTAssertFalse(ScanPolicy.isNeverCleanPath(url, customRoots: [], aiDataRoots: []), relative)
        }
    }

    func testE5BundleCacheIsProtectedAtAnyDepth() {
        let url = URL(fileURLWithPath: "/private/var/folders/ab/cd/C/com.apple.e5rt.e5bundlecache/model")
        XCTAssertTrue(ScanPolicy.isNeverCleanPath(url, customRoots: [], aiDataRoots: []))
        XCTAssertTrue(ScanPolicy.isUserCacheFolderProtected(name: "com.apple.e5rt.e5bundlecache"))
    }

    func testDeclaredRootsHonourHuggingFaceEnvironment() {
        let home = URL(fileURLWithPath: "/Users/u")
        let environment = [
            "HF_HOME": "/Volumes/ssd/hf",
            "HF_HUB_CACHE": "/Volumes/ssd/hub",
            "XDG_CACHE_HOME": "/Volumes/ssd/xdg",
        ]

        let roots = ScanPolicy.declaredAIDataRoots(environment: environment, home: home).map(\.path)

        XCTAssertEqual(Set(roots), ["/Volumes/ssd/hf", "/Volumes/ssd/hub", "/Volumes/ssd/xdg/huggingface"])
    }

    func testDeclaredRootsIgnoreRelativeAndDangerousValues() {
        let home = URL(fileURLWithPath: "/Users/u")
        let environment = ["HF_HOME": "relative/hf", "HF_HUB_CACHE": "/", "XDG_CACHE_HOME": ""]

        XCTAssertTrue(ScanPolicy.declaredAIDataRoots(environment: environment, home: home).isEmpty)
    }

    func testDeclaredRootProtectsItsDescendantsOnly() {
        let root = URL(fileURLWithPath: "/Volumes/ssd/hf")
        let inside = URL(fileURLWithPath: "/Volumes/ssd/hf/hub/models--x/blob")
        let sibling = URL(fileURLWithPath: "/Volumes/ssd/hf-old/blob")

        XCTAssertTrue(ScanPolicy.isNeverCleanPath(inside, customRoots: [], aiDataRoots: [root]))
        XCTAssertFalse(ScanPolicy.isNeverCleanPath(sibling, customRoots: [], aiDataRoots: [root]))
    }

    func testFoldersHoldingAIDataAreFlagged() {
        let home = URL(fileURLWithPath: "/Users/u")
        for relative in [".ollama", ".claude", ".codex", ".cache"] {
            let url = home.appending(path: relative)
            XCTAssertTrue(
                ScanPolicy.holdsNeverCleanLocation(url, home: home, customRoots: [], aiDataRoots: []), relative
            )
        }
        XCTAssertFalse(
            ScanPolicy.holdsNeverCleanLocation(
                home.appending(path: ".ollama-backup"), home: home, customRoots: [], aiDataRoots: []
            )
        )
    }

    // MARK: - Rules and cleanup

    func testUserCachesRuleSkipsE5BundleCache() async throws {
        let caches = tmp.appending(path: "Library/Caches")
        try makeFile(caches.appending(path: "com.apple.e5rt.e5bundlecache/model.bin"))
        let other = try makeFile(caches.appending(path: "com.example.app/blob.bin"))
        let environment = ScanEnvironment(homeDirectory: tmp, systemApplicationDirectories: [])

        let findings = await UserCachesRule().customScan(environment: environment) ?? []

        XCTAssertEqual(findings.map(\.path), [other.deletingLastPathComponent().path])
    }

    func testAIToolCachesRuleNeverReportsProtectedPaths() async throws {
        for relative in protectedRelatives where !relative.hasPrefix("Library") {
            try makeFile(tmp.appending(path: relative))
        }
        let environment = ScanEnvironment(homeDirectory: tmp, systemApplicationDirectories: [])

        let findings = await AIToolCachesRule().customScan(environment: environment) ?? []

        for finding in findings {
            XCTAssertFalse(
                ScanPolicy.isNeverCleanPath(URL(fileURLWithPath: finding.path), customRoots: [], aiDataRoots: []),
                finding.path
            )
        }
    }

    func testCleanupRefusesEveryAIDataPath() async throws {
        let urls = try protectedRelatives.map { try makeFile(tmp.appending(path: $0)) }

        let result = try await dryRunClean(urls)

        XCTAssertTrue(result.succeeded.isEmpty, "\(result.succeeded.map(\.originalPath))")
        XCTAssertEqual(Set(result.skipped.map(\.path)), Set(urls.map(\.path)))
        for item in result.skipped {
            guard case .workingSetProtected = item.error else {
                XCTFail("expected .workingSetProtected for \(item.path), got \(item.error)")
                continue
            }
            XCTAssertFalse(item.error.localizedDescription.contains("Go cache"), item.path)
        }
    }

    func testCleanupDoesNotRefuseLookAlikesAsProtectedData() async throws {
        let urls = try lookAlikeRelatives.map { try makeFile(tmp.appending(path: $0)) }

        let result = try await dryRunClean(urls)

        for item in result.skipped {
            if case .workingSetProtected = item.error {
                XCTFail("look-alike wrongly protected: \(item.path)")
            }
        }
    }

    // MARK: - Helpers

    private func dryRunClean(_ urls: [URL]) async throws -> CleanupResult {
        let engine = CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: tmp.appending(path: "store")),
            projectRootsProvider: { [] },
            goCacheLocations: GoCacheLocations(query: { nil })
        )
        let findings = urls.map { url in
            ScanFinding(
                category: .aiToolCaches, riskLevel: .safe, reason: "mislabelled", path: url.path,
                sizeBytes: 2048, lastUsed: Date().addingTimeInterval(-30 * 86400), confidence: 1.0
            )
        }
        return try await engine.clean(findings: findings, profileName: "test", dryRun: true)
    }

    @discardableResult
    private func makeFile(_ url: URL, size: Int = 2048) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: size).write(to: url)
        return URL(fileURLWithPath: url.path)
    }
}
