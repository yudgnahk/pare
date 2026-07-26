import XCTest
@testable import PareCore

/// Phase R0 regression tests — the cleanup re-verification gate must be fail-closed.
final class CleanupSafetyRegressionTests: XCTestCase {

    private var root: URL!
    private var storeDir: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/private/tmp/CleanupSafetyRegression-\(UUID().uuidString)")
        storeDir = root.appending(path: "store")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeEngine(projectRoots: [String] = []) -> CleanupEngine {
        CleanupEngine(
            store: CleanupTransactionStore(directory: storeDir),
            projectRootsProvider: { projectRoots }
        )
    }

    /// Creates a directory (with one file inside) whose mtime is back-dated.
    @discardableResult
    private func makeDirectory(at url: URL, ageSeconds: TimeInterval = 10 * 24 * 60 * 60) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appending(path: "payload.bin")
        try Data(repeating: 0x42, count: 2048).write(to: file)
        let old = Date().addingTimeInterval(-ageSeconds)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        return url
    }

    private func finding(
        for url: URL,
        category: ScanCategory = .projectArtifacts,
        riskLevel: RiskLevel = .safe
    ) -> ScanFinding {
        ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "regression test",
            path: url.path,
            sizeBytes: 2048,
            lastUsed: Date().addingTimeInterval(-10 * 24 * 60 * 60),
            confidence: 1.0
        )
    }

    // MARK: - R0.1a: project artifacts need project-root evidence

    /// A bare `build` directory under ~/Documents-like trees (no `.git`, no registered
    /// root) must FAIL the cleanup re-verify — the old name-only match trashed it.
    func testBareBuildDirectoryWithoutProjectEvidenceIsBlocked() async throws {
        // "/Documents/" makes the path protected, so only the project-artifact gate could pass it.
        let build = try makeDirectory(at: root.appending(path: "Documents/foo/build"))
        let engine = makeEngine(projectRoots: [])

        let result = try await engine.clean(findings: [finding(for: build)], profileName: "test")

        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("safety policy"), result.skipped[0].reason)
        XCTAssertTrue(FileManager.default.fileExists(atPath: build.path),
                      "bare build dir must remain on disk")
    }

    /// A `build` directory whose parent contains a project marker (`.git`) passes re-verify.
    func testBuildDirectoryWithProjectMarkerSiblingIsCleanable() async throws {
        let project = root.appending(path: "Documents/proj")
        try FileManager.default.createDirectory(
            at: project.appending(path: ".git"), withIntermediateDirectories: true
        )
        let build = try makeDirectory(at: project.appending(path: "build"))
        let engine = makeEngine(projectRoots: [])

        let result = try await engine.clean(findings: [finding(for: build)], profileName: "test")

        XCTAssertEqual(result.succeeded.count, 1, "skipped: \(result.skipped)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: build.path))
    }

    /// A `build` directory under a registered project scan root passes re-verify
    /// even without a marker file.
    func testBuildDirectoryUnderRegisteredRootIsCleanable() async throws {
        let projectRoot = root.appending(path: "Documents/registered")
        let build = try makeDirectory(at: projectRoot.appending(path: "build"))
        let engine = makeEngine(projectRoots: [projectRoot.path])

        let result = try await engine.clean(findings: [finding(for: build)], profileName: "test")

        XCTAssertEqual(result.succeeded.count, 1, "skipped: \(result.skipped)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: build.path))
    }

    /// The home directory itself is never accepted as project-root evidence.
    func testHomeDirectoryDotGitIsNotProjectEvidence() {
        let home = root.appending(path: "home")
        let url = home.appending(path: "somewhere/build")
        // fileExists claims a marker exists everywhere — including $HOME/.git.
        let result = ScanPolicy.isReclaimableProjectArtifact(
            url,
            registeredRootPaths: [],
            homeDirectory: home,
            fileExists: { $0.hasPrefix(home.path + "/.") || $0 == home.path + "/.git" }
        )
        XCTAssertFalse(result, "a dotfiles repo at ~ must not make ~/**/build cleanable")
    }

    // MARK: - R0.1b: wrong-platform bypass restricted to scanned trees

    /// A path with a `linux` component outside the wrong-platform scan roots must not
    /// unlock cleanup (old behavior: any `linux`/`win32` component anywhere passed).
    func testLinuxComponentOutsideScanRootsDoesNotUnlockCleanup() async throws {
        let dir = try makeDirectory(at: root.appending(path: "Documents/linux/data"))
        let engine = makeEngine()

        let result = try await engine.clean(
            findings: [finding(for: dir, category: .temporaryFiles)],
            profileName: "test"
        )

        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("safety policy"), result.skipped[0].reason)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    /// Wrong-platform native dirs under the editor-extension scan roots stay cleanable.
    func testWin32DirUnderEditorExtensionsIsCleanable() async throws {
        let dir = try makeDirectory(
            at: root.appending(path: "Documents/.vscode/extensions/pkg/win32-x64")
        )
        let engine = makeEngine()

        let result = try await engine.clean(
            findings: [finding(for: dir, category: .developerPackageCaches)],
            profileName: "test"
        )

        XCTAssertEqual(result.succeeded.count, 1, "skipped: \(result.skipped)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testIsCleanableWrongPlatformPathSemantics() {
        // Top-level Downloads binary — allowed.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(ScanPolicy.isCleanableWrongPlatformPath(
            URL(fileURLWithPath: "\(home)/Downloads/Setup.exe")))
        // Native dir under a scanned root — allowed.
        XCTAssertTrue(ScanPolicy.isCleanableWrongPlatformPath(
            URL(fileURLWithPath: "/Users/t/.vscode/extensions/pkg/win32/lib.dll")))
        XCTAssertTrue(ScanPolicy.isCleanableWrongPlatformPath(
            URL(fileURLWithPath: "/Users/t/Library/Application Support/JetBrains/GoLand/plugins/p/lib/linux")))
        // Bare platform component elsewhere — blocked.
        XCTAssertFalse(ScanPolicy.isCleanableWrongPlatformPath(
            URL(fileURLWithPath: "/Users/t/Documents/linux/notes.txt")))
        XCTAssertFalse(ScanPolicy.isCleanableWrongPlatformPath(
            URL(fileURLWithPath: "/Users/t/Projects/win32/main.c")))
    }

    // MARK: - R0.2: exclusions honored at cleanup time

    /// A path excluded AFTER the scan must still be skipped by the engine.
    func testExcludedPathIsSkippedAtCleanupTime() async throws {
        let cacheDir = root.appending(path: "Library/Caches/com.pare.test")
        let dir = try makeDirectory(at: cacheDir.appending(path: "excluded-cache"))
        let engine = CleanupEngine(
            store: CleanupTransactionStore(directory: storeDir),
            projectRootsProvider: { [] },
            exclusionsProvider: { ExclusionList(entries: [ExclusionEntry(path: dir.path)]) }
        )

        let result = try await engine.clean(
            findings: [finding(for: dir, category: .userCaches)],
            profileName: "test"
        )

        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("Excluded"), result.skipped[0].reason)
        // R1.1: skip reasons are typed, not stringly.
        if case .excludedByUser = result.skipped[0].error {} else {
            XCTFail("expected .excludedByUser, got \(result.skipped[0].error)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    // MARK: - R0.4: durable undo record

    /// If the undo record cannot be persisted, the engine must abort BEFORE
    /// trashing anything — never delete without a durable undo record.
    func testCleanupAbortsWhenUndoRecordCannotBePersisted() async throws {
        // Occupy the store directory path with a FILE so createDirectory fails.
        let blockedStorePath = root.appending(path: "blocked-store")
        try Data("not a directory".utf8).write(to: blockedStorePath)

        let cacheDir = root.appending(path: "Library/Caches/com.pare.test")
        let dir = try makeDirectory(at: cacheDir.appending(path: "victim-cache"))
        let engine = CleanupEngine(
            store: CleanupTransactionStore(directory: blockedStorePath),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty }
        )

        let result = try await engine.clean(
            findings: [finding(for: dir, category: .userCaches)],
            profileName: "test"
        )

        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertNotNil(result.transactionSaveError)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("undo record"), result.skipped[0].reason)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path),
                      "file must NOT be trashed when the undo record cannot be written")
    }

    /// Normal path: the transaction is persisted with all items and no save error.
    func testUndoRecordPersistedWithAllItemsAfterClean() async throws {
        let cacheDir = root.appending(path: "Library/Caches/com.pare.test")
        let a = try makeDirectory(at: cacheDir.appending(path: "cache-a"))
        let b = try makeDirectory(at: cacheDir.appending(path: "cache-b"))
        let store = CleanupTransactionStore(directory: storeDir)
        let engine = CleanupEngine(
            store: store,
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty }
        )

        let result = try await engine.clean(
            findings: [finding(for: a, category: .userCaches), finding(for: b, category: .userCaches)],
            profileName: "test"
        )

        XCTAssertEqual(result.succeeded.count, 2, "skipped: \(result.skipped)")
        XCTAssertNil(result.transactionSaveError)
        let persisted = try store.loadAll()
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.items.count, 2)
        XCTAssertEqual(persisted.first?.id, result.transaction?.id)
    }

    /// A run where everything is skipped must not leave an empty transaction record.
    func testSkipOnlyRunLeavesNoEmptyTransactionRecord() async throws {
        let dir = try makeDirectory(at: root.appending(path: "Documents/foo/build"))
        let store = CleanupTransactionStore(directory: storeDir)
        let engine = CleanupEngine(
            store: store,
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty }
        )

        let result = try await engine.clean(findings: [finding(for: dir)], profileName: "test")

        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertTrue(try store.loadAll().isEmpty,
                      "skip-only run must not persist an empty undo record")
    }

    // MARK: - R0.7: undo honesty

    /// Restore failures must be reported with reasons — never silently dropped.
    func testRestoreReportsFailureWhenTrashItemMissing() async {
        let engine = makeEngine()
        let item = CleanupItem(
            originalPath: root.appending(path: "gone.bin").path,
            trashedPath: root.appending(path: "not-in-trash.bin").path,
            sizeBytes: 10,
            reason: "test",
            riskLevel: .safe
        )
        let tx = CleanupTransaction(profileName: "test", isDryRun: false, items: [item])

        let (restored, failed) = await engine.restore(transaction: tx)

        XCTAssertTrue(restored.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertFalse(failed[0].reason.isEmpty, "restore failure must carry a reason")
    }

    /// Single-item restore throws (with the real reason) instead of returning false.
    func testRestoreItemThrowsWithoutRecordedTrashPath() async {
        let engine = makeEngine()
        let item = CleanupItem(
            originalPath: root.appending(path: "orphan.bin").path,
            trashedPath: nil,
            sizeBytes: 10,
            reason: "test",
            riskLevel: .safe
        )

        do {
            try await engine.restoreItem(item)
            XCTFail("restoreItem must throw when no Trash path was recorded")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Cannot restore"),
                          error.localizedDescription)
        }
    }

    // MARK: - R0.3: fail-closed age gates

    /// Unreadable attributes must block the unused-age check (previously passed open).
    func testPassesUnusedAgeFailsClosedForUnreadableAttributes() {
        let missing = URL(fileURLWithPath: "/private/tmp/does-not-exist-\(UUID().uuidString)")
        XCTAssertFalse(ScanPolicy.passesUnusedAge(for: missing, minimumAgeSeconds: 60))
    }

    /// A missing date must fail an active age gate (previously passed open),
    /// while a nil gate still passes.
    func testPassesMinimumAgeFailsClosedWhenDateMissing() {
        let noDates = URLResourceValues()
        XCTAssertFalse(ScanPolicy.passesMinimumAge(for: noDates, minimumAgeSeconds: 60))
        XCTAssertTrue(ScanPolicy.passesMinimumAge(for: noDates, minimumAgeSeconds: nil))
    }
}
