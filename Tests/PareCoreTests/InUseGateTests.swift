import XCTest
@testable import PareCore

/// Cleanup skips anything another process has open, using one `lsof -F` snapshot per batch.
final class InUseGateTests: XCTestCase {

    private static let lsofOutput = """
    p123
    cSafari
    fcwd
    n/
    ftxt
    n/Applications/Safari.app/Contents/MacOS/Safari
    f12
    n/Users/u/Library/Caches/com.apple.Safari/Cache.db
    f13
    n/private/var/folders/ab/T/x/cache/blob
    f14
    n*:443
    f15
    n/System/Volumes/Data/Users/u/Library/Caches/com.example/db.sqlite
    p456
    ccurl
    f5
    n/Users/u/Library/Caches/Homebrew/downloads/abc--wget.tar.gz.incomplete
    """

    // MARK: - Parsing

    func testHolderLookupOnParsedSnapshot() {
        let snapshot = OpenFileSnapshot(lsofFieldOutput: Self.lsofOutput)
        let cases: [(path: String, holder: String?)] = [
            ("/Users/u/Library/Caches/com.apple.Safari", "Safari (pid 123)"),
            ("/Users/u/Library/Caches/com.apple.safari/Cache.db", "Safari (pid 123)"),
            ("/var/folders/ab/T/x", "Safari (pid 123)"),
            ("/private/var/folders/ab/T/x/cache", "Safari (pid 123)"),
            ("/Users/u/Library/Caches/com.example", "Safari (pid 123)"),
            ("/Users/u/Library/Caches/Homebrew/downloads", "curl (pid 456)"),
            ("/Users/u/Library/Caches/com.apple.Safari2", nil),
            ("/Users/u/Library/Caches/com.apple.Saf", nil),
            ("/Users/u/Library/Caches/Homebrew/downloads/abc--wget.tar.gz", nil),
            ("/Users/u/Library/Logs", nil),
        ]
        for testCase in cases {
            XCTAssertEqual(snapshot.holder(atOrUnder: testCase.path), testCase.holder, testCase.path)
        }
    }

    func testEmptyOrGarbageOutputHasNoHolders() {
        for output in ["", "p1\ncX\nn*:22\nn->0x1234\n", "garbage\nlines\n"] {
            XCTAssertNil(OpenFileSnapshot(lsofFieldOutput: output).holder(atOrUnder: "/Users/u/Library/Caches"), output)
        }
    }

    // MARK: - Fail open / fail closed

    func testUnavailableSnapshotFailsClosedOnlyForRiskyCaches() {
        let running = [RunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari")]
        let cases: [(path: String, blocked: Bool)] = [
            ("/Users/u/Library/Caches/com.apple.Safari", true),
            ("/Users/u/Library/Caches/com.apple.safari/WebKit", true),
            ("/Users/u/Library/Caches/com.example.closed", false),
            ("/Users/u/Library/Caches/Homebrew/downloads/x--wget.tar.gz.incomplete", true),
            ("/Users/u/Library/Caches/com.foo/data.sqlite", true),
            ("/Users/u/Library/Caches/com.foo/data.db-wal", true),
            ("/Users/u/Library/Caches/com.foo/blob.bin", false),
            ("/Users/u/Library/Logs/old.log", false),
        ]
        for testCase in cases {
            let holder = InUseGate.holder(forPath: testCase.path, snapshot: nil, runningApps: { running })
            XCTAssertEqual(holder != nil, testCase.blocked, "\(testCase.path): \(String(describing: holder))")
        }
    }

    func testAvailableSnapshotIgnoresRunningAppsWithoutOpenFiles() {
        let running = [RunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari")]
        let empty = OpenFileSnapshot(lsofFieldOutput: "")

        XCTAssertNil(InUseGate.holder(forPath: "/Users/u/Library/Caches/com.apple.Safari", snapshot: empty, runningApps: { running }))
        XCTAssertNil(InUseGate.holder(forPath: "/Users/u/Library/Caches/x.tar.gz.incomplete", snapshot: empty, runningApps: { running }))
    }

    // MARK: - CleanupEngine

    func testOpenFileInsideFindingSkipsWithInUse() async throws {
        let fixture = try Fixture()
        let cache = try fixture.makeCache("com.example.app")
        let aliasSpelling = String(cache.path.dropFirst("/private".count)) + "/payload.bin"
        let engine = fixture.engine(snapshot: OpenFileSnapshot(lsofFieldOutput: "p77\ncExampleApp\nf4\nn\(aliasSpelling)\n"))

        let result = try await engine.clean(findings: [fixture.finding(cache)], profileName: "test")

        XCTAssertTrue(result.succeeded.isEmpty)
        guard case .some(.inUse(let path, let holder)) = result.skipped.first?.error else {
            return XCTFail("expected .inUse, got \(result.skipped)")
        }
        XCTAssertEqual(path, cache.path)
        XCTAssertEqual(holder, "ExampleApp (pid 77)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(fixture.trashedCount, 0)
    }

    func testNoOpenFilesCleans() async throws {
        let fixture = try Fixture()
        let cache = try fixture.makeCache("com.example.app")
        let engine = fixture.engine(snapshot: OpenFileSnapshot(lsofFieldOutput: ""))

        let result = try await engine.clean(findings: [fixture.finding(cache)], profileName: "test")

        XCTAssertEqual(result.succeeded.count, 1, "\(result.skipped)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(fixture.trashedCount, 1)
    }

    func testUnavailableSnapshotBlocksCacheOfRunningAppOnly() async throws {
        let fixture = try Fixture()
        let runningCache = try fixture.makeCache("com.example.running")
        let idleCache = try fixture.makeCache("com.example.idle")
        let engine = fixture.engine(
            snapshot: nil,
            running: [RunningApp(bundleIdentifier: "com.example.running", name: "Running")]
        )

        let result = try await engine.clean(
            findings: [fixture.finding(runningCache), fixture.finding(idleCache)],
            profileName: "test"
        )

        XCTAssertEqual(result.succeeded.map(\.originalPath), [idleCache.path])
        guard case .some(.inUse(runningCache.path, _)) = result.skipped.first?.error else {
            return XCTFail("expected .inUse for the running app's cache, got \(result.skipped)")
        }
    }

    func testDryRunReportsInUseToo() async throws {
        let fixture = try Fixture()
        let cache = try fixture.makeCache("com.example.app")
        let engine = fixture.engine(snapshot: OpenFileSnapshot(lsofFieldOutput: "p1\ncX\nf3\nn\(cache.path)/payload.bin\n"))

        let result = try await engine.clean(findings: [fixture.finding(cache)], profileName: "test", dryRun: true)

        XCTAssertTrue(result.succeeded.isEmpty)
        guard case .some(.inUse(_, _)) = result.skipped.first?.error else {
            return XCTFail("expected .inUse, got \(result.skipped)")
        }
    }

    func testSnapshotTakenOncePerBatchAndOnlyWhenNeeded() async throws {
        let fixture = try Fixture()
        let first = try fixture.makeCache("com.example.one")
        let second = try fixture.makeCache("com.example.two")
        let provider = CountingSnapshotProvider(snapshot: OpenFileSnapshot(lsofFieldOutput: ""))
        let engine = fixture.engine(provider: provider)

        _ = try await engine.clean(findings: [fixture.finding(first), fixture.finding(second)], profileName: "test")
        XCTAssertEqual(provider.calls, 1)

        let advanced = fixture.finding(try fixture.makeCache("com.example.three"), risk: .advanced)
        _ = try await engine.clean(findings: [advanced], profileName: "test")
        XCTAssertEqual(provider.calls, 1, "no snapshot when nothing reaches the trash step")
    }
}

// MARK: - Unavailable flag and snapshot refresh

final class InUseSnapshotRefreshTests: XCTestCase {

    func testResultFlagsAnUnavailableCheckOnlyWhenOneWasNeeded() async throws {
        let fixture = try Fixture()
        let cache = try fixture.makeCache("com.example.app")

        let unavailable = try await fixture.engine(snapshot: nil).clean(findings: [fixture.finding(cache)], profileName: "test", dryRun: true)
        XCTAssertTrue(unavailable.inUseCheckUnavailable)

        let available = try await fixture.engine(snapshot: OpenFileSnapshot(lsofFieldOutput: "p1\ncX\nf3\nn/elsewhere/file\n"))
            .clean(findings: [fixture.finding(cache)], profileName: "test", dryRun: true)
        XCTAssertFalse(available.inUseCheckUnavailable)

        let advanced = fixture.finding(cache, risk: .advanced)
        let neverNeeded = try await fixture.engine(snapshot: nil).clean(findings: [advanced], profileName: "test", dryRun: true)
        XCTAssertFalse(neverNeeded.inUseCheckUnavailable, "no snapshot is taken when nothing reaches the trash step")
    }

    func testSnapshotIsRetakenOnlyAfterTheRefreshInterval() async {
        let provider = CountingSnapshotProvider(snapshot: OpenFileSnapshot(lsofFieldOutput: ""))
        let clock = AdjustableClock()
        let check = InUseBatchCheck(
            openFiles: provider, runningApps: FixedRunningAppsList(apps: []), now: clock.now, refreshInterval: 30, log: { _ in }
        )

        _ = await check.holder(forPath: "/a")
        clock.advance(by: 29)
        _ = await check.holder(forPath: "/b")
        XCTAssertEqual(provider.calls, 1, "still fresh within the interval")

        clock.advance(by: 2)
        _ = await check.holder(forPath: "/c")
        XCTAssertEqual(provider.calls, 2, "re-taken once older than the interval")

        _ = await check.holder(forPath: "/d")
        XCTAssertEqual(provider.calls, 2)
    }
}

private final class AdjustableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSinceReferenceDate: 0)

    var now: @Sendable () -> Date { { [self] in lock.withLock { current } } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

// MARK: - Test support

private final class Fixture: @unchecked Sendable {
    let root: URL
    let trashDir: URL
    private let lock = NSLock()
    private var trashed = 0

    init() throws {
        // Canonical `/private/var/…` spelling, as the engine and lsof see it.
        root = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_inuse_\(UUID().uuidString)")
        trashDir = root.appending(path: "Trash")
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var trashedCount: Int { lock.withLock { trashed } }

    /// `<root>/home/Library/Caches/<name>` with one payload file, both back-dated past the cache age gate.
    func makeCache(_ name: String) throws -> URL {
        let dir = root.appending(path: "home/Library/Caches/\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = dir.appending(path: "payload.bin")
        try Data(repeating: 0x42, count: 2048).write(to: payload)
        let old = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: payload.path)
        try FileManager.default.setAttributes([.modificationDate: old, .creationDate: old], ofItemAtPath: dir.path)
        return URL(fileURLWithPath: dir.path)
    }

    func finding(_ url: URL, risk: RiskLevel = .safe) -> ScanFinding {
        ScanFinding(
            category: .userCaches,
            riskLevel: risk,
            reason: "test cache",
            path: url.path,
            sizeBytes: 2048,
            lastUsed: Date().addingTimeInterval(-10 * 24 * 60 * 60),
            confidence: 1.0
        )
    }

    func engine(snapshot: OpenFileSnapshot?, running: [RunningApp] = []) -> CleanupEngine {
        engine(provider: CountingSnapshotProvider(snapshot: snapshot), running: running)
    }

    func engine(provider: CountingSnapshotProvider, running: [RunningApp] = []) -> CleanupEngine {
        CleanupEngine(
            store: CleanupTransactionStore(directory: root.appending(path: "store")),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            trashItem: { [self] url in
                let destination = self.trashDir.appending(path: UUID().uuidString)
                try FileManager.default.moveItem(at: url, to: destination)
                self.lock.withLock { self.trashed += 1 }
                return destination
            },
            openFiles: provider,
            runningApps: FixedRunningAppsList(apps: running)
        )
    }
}

final class CountingSnapshotProvider: OpenFileSnapshotProviding, @unchecked Sendable {
    private let snapshotValue: OpenFileSnapshot?
    private let lock = NSLock()
    private var count = 0

    init(snapshot: OpenFileSnapshot?) {
        snapshotValue = snapshot
    }

    var calls: Int { lock.withLock { count } }

    func snapshot() async -> OpenFileSnapshot? {
        lock.withLock { count += 1 }
        return snapshotValue
    }
}

struct FixedRunningAppsList: RunningAppsProviding {
    let apps: [RunningApp]

    func runningApps() -> [RunningApp] { apps }
}
