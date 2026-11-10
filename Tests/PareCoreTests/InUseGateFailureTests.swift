import XCTest
@testable import PareCore

/// When `lsof` cannot produce a snapshot, only three item classes fail closed; everything else is still cleaned.
final class InUseGateFailureTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        // Canonical `/private/var/…` spelling, as the engine and lsof see it.
        root = ScanPolicy.canonicalPathURL(FileManager.default.temporaryDirectory)
            .appending(path: "pare_inuse_fail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Failure kinds

    private enum FailureKind: String, CaseIterable {
        case timeout, nonZeroExit, garbageText, undecodableBytes

        var script: String {
            switch self {
            case .timeout: return "exec sleep 5\nprintf 'p1\\ncX\\nn/tmp/x\\n'"
            case .nonZeroExit: return "printf 'p1\\ncX\\nn/tmp/x\\n'\nexit 1"
            case .garbageText: return "echo 'lsof: WARNING: something odd'\necho 'not a field listing'"
            case .undecodableBytes: return "printf '\\377\\376\\375'"
            }
        }
    }

    func testEveryFailureKindYieldsNoSnapshot() async throws {
        for kind in FailureKind.allCases {
            let snapshot = await provider(kind.script).snapshot()
            XCTAssertNil(snapshot, kind.rawValue)
        }
    }

    func testRecognizedOutputYieldsSnapshot() async throws {
        let snapshot = await provider("printf 'p42\\ncTool\\nf3\\nn/tmp/held\\n'").snapshot()

        XCTAssertEqual(snapshot?.holder(atOrUnder: "/tmp/held"), "Tool (pid 42)")
    }

    func testEachFailureKindBlocksExactlyTheFailClosedClasses() async throws {
        for kind in FailureKind.allCases {
            let home = root.appending(path: "home-\(kind.rawValue)")
            let caches = home.appending(path: "Library/Caches")
            let runningCache = try makeDirectory(caches.appending(path: "com.example.running"))
            let database = try makeFile(caches.appending(path: "com.example.idle/Store.DB"))
            let download = try makeFile(caches.appending(path: "Homebrew/downloads/x--wget.tar.gz.incomplete"))
            let ordinaryFolder = try makeDirectory(caches.appending(path: "com.example.idle-other"))
            let ordinaryFile = try makeFile(caches.appending(path: "com.example.idle/blob.bin"))
            let trash = root.appending(path: "Trash-\(kind.rawValue)")
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            let engine = CleanupEngineFixture.make(
                store: CleanupTransactionStore(directory: root.appending(path: "store-\(kind.rawValue)")),
                projectRootsProvider: { [] },
                exclusionsProvider: { .empty },
                trashItem: { url in
                    let destination = trash.appending(path: UUID().uuidString)
                    try FileManager.default.moveItem(at: url, to: destination)
                    return destination
                },
                openFiles: provider(kind.script),
                runningApps: FixedRunningAppsList(apps: [RunningApp(bundleIdentifier: "com.example.running", name: "Running")])
            )
            let findings = [runningCache, database, download, ordinaryFolder, ordinaryFile].map(finding)

            let result = try await engine.clean(findings: findings, profileName: "test")

            let blocked = Set(result.skipped.compactMap { item -> String? in
                if case .inUse = item.error { return item.path }
                return nil
            })
            XCTAssertEqual(blocked, [runningCache.path, database.path, download.path], kind.rawValue)
            XCTAssertEqual(Set(result.succeeded.map(\.originalPath)), [ordinaryFolder.path, ordinaryFile.path],
                           "\(kind.rawValue): \(result.skipped.map(\.reason))")
            XCTAssertFalse(FileManager.default.fileExists(atPath: ordinaryFolder.path), kind.rawValue)
            XCTAssertTrue(FileManager.default.fileExists(atPath: database.path), kind.rawValue)
        }
    }

    // MARK: - Fail-closed classes

    func testSQLiteSuffixMatchIsCaseInsensitiveAndLimitedToCaches() {
        let cases: [(path: String, blocked: Bool)] = [
            ("/Users/u/Library/Caches/com.foo/Foo.DB", true),
            ("/Users/u/Library/Caches/com.foo/x.SQLITE-WAL", true),
            ("/Users/u/Library/Caches/com.foo/y.Sqlite3", true),
            ("/Users/u/Library/Caches/com.foo/z.db-SHM", true),
            ("/Users/u/Library/Caches/com.foo/j.sqlite-Journal", true),
            ("/Users/u/LIBRARY/CACHES/com.foo/data.sqlite", true),
            ("/Users/u/Library/Caches/com.foo/notes.dbx", false),
            ("/Users/u/Library/Caches/com.foo/sqlite.bin", false),
            ("/Users/u/Library/Caches/com.foo/Foo.DB.bak", false),
            ("/Users/u/Documents/Foo.DB", false),
            ("/Users/u/Library/Logs/x.sqlite-wal", false),
        ]
        for testCase in cases {
            let holder = InUseGate.holder(forPath: testCase.path, snapshot: nil, runningApps: { [] })
            XCTAssertEqual(holder != nil, testCase.blocked, "\(testCase.path): \(String(describing: holder))")
        }
    }

    func testRunningAppAndIncompleteDownloadClasses() {
        let running = [RunningApp(bundleIdentifier: "com.Example.Editor", name: "Editor")]
        let cases: [(path: String, blocked: Bool)] = [
            ("/Users/u/Library/Caches/com.example.editor", true),
            ("/Users/u/Library/Caches/COM.EXAMPLE.EDITOR/sub/file", true),
            ("/Users/u/Library/Caches/com.example.editor2", false),
            ("/Users/u/Library/Caches/other/com.example.editor", false),
            ("/Users/u/Library/Application Support/com.example.editor", false),
            ("/Users/u/Downloads/big.iso.incomplete", true),
            ("/Users/u/Library/Caches/x.INCOMPLETE", true),
            ("/Users/u/Library/Caches/x.incomplete.bak", false),
        ]
        for testCase in cases {
            let holder = InUseGate.holder(forPath: testCase.path, snapshot: nil, runningApps: { running })
            XCTAssertEqual(holder != nil, testCase.blocked, "\(testCase.path): \(String(describing: holder))")
        }
    }

    // MARK: - Logging

    func testUnavailableSnapshotIsLoggedOncePerBatch() async {
        let log = LogSink()
        let check = InUseBatchCheck(
            openFiles: CountingSnapshotProvider(snapshot: nil),
            runningApps: FixedRunningAppsList(apps: []),
            log: { log.append($0) }
        )

        _ = await check.holder(forPath: "/Users/u/Library/Caches/a")
        _ = await check.holder(forPath: "/Users/u/Library/Caches/b")

        XCTAssertEqual(log.lines.count, 1, "\(log.lines)")
        XCTAssertTrue(log.lines.first?.contains("unavailable") ?? false, "\(log.lines)")
    }

    func testAvailableSnapshotLogsNothing() async {
        let log = LogSink()
        let check = InUseBatchCheck(
            openFiles: CountingSnapshotProvider(snapshot: .nothingOpen),
            runningApps: FixedRunningAppsList(apps: []),
            log: { log.append($0) }
        )

        _ = await check.holder(forPath: "/Users/u/Library/Caches/a")

        XCTAssertTrue(log.lines.isEmpty, "\(log.lines)")
    }

    // MARK: - Helpers

    /// A provider whose `lsof` is a temp shell script, so each failure kind runs a real process.
    private func provider(_ body: String) -> LsofOpenFileSnapshotProvider {
        let script = root.appending(path: "lsof-\(UUID().uuidString).sh")
        try? Data("#!/bin/sh\n\(body)\n".utf8).write(to: script)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return LsofOpenFileSnapshotProvider(executable: script, timeoutSeconds: 1)
    }

    private func makeDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try makeFile(url.appending(path: "payload.bin"))
        try backdate(url)
        return URL(fileURLWithPath: url.path)
    }

    @discardableResult
    private func makeFile(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 2048).write(to: url)
        try backdate(url)
        return URL(fileURLWithPath: url.path)
    }

    /// Past the cache age gate so only the in-use gate decides.
    private func backdate(_ url: URL) throws {
        let old = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old, .creationDate: old], ofItemAtPath: url.path)
    }

    private func finding(_ url: URL) -> ScanFinding {
        ScanFinding(category: .userCaches, riskLevel: .safe, reason: "test cache", path: url.path,
                    sizeBytes: 2048, lastUsed: Date().addingTimeInterval(-10 * 24 * 60 * 60), confidence: 1.0)
    }
}

private final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var lines: [String] { lock.withLock { stored } }

    func append(_ line: String) {
        lock.withLock { stored.append(line) }
    }
}
