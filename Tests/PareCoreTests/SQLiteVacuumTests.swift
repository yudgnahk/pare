import XCTest
@testable import PareCore

/// VACUUM in WAL mode can leave a `-wal` file as large as the database; the plan checkpoints around it
/// and skips databases that are corrupt, busy, owned by a running app, or too large for the free space.
final class SQLiteVacuumTests: XCTestCase {

    private static let sqlite3 = "/usr/bin/sqlite3"

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "pare_vacuum_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Plan

    func testVacuumPlanOrder() {
        XCTAssertEqual(SQLiteVacuumPlan.steps(dbPath: "/x/History.db"), [
            ["/x/History.db", "PRAGMA quick_check;"],
            ["/x/History.db", "PRAGMA wal_checkpoint(TRUNCATE);"],
            ["/x/History.db", "VACUUM;"],
            ["/x/History.db", "PRAGMA wal_checkpoint(TRUNCATE);"],
        ])
    }

    // MARK: - Skips

    func testSkipsWhenQuickCheckNotOK() async throws {
        let cases: [(name: String, result: ProcessResult)] = [
            ("corrupt", .ok("*** in database main ***\nPage 5: btreeInitPage() returns error code 11")),
            ("locked", .failure("Error: database is locked", exitCode: 5)),
        ]
        for testCase in cases {
            let db = try makeDatabase("\(testCase.name).db", bytes: 1000)
            let runner = ScriptedProcessRunner { invocation in
                invocation.arguments.last == "PRAGMA quick_check;" ? testCase.result : .ok()
            }

            let log = await vacuum([target(db)], processRunner: runner)

            XCTAssertEqual(runner.invocations.map(\.arguments), [[db.path, "PRAGMA quick_check;"]], testCase.name)
            XCTAssertTrue(log.contains { $0.contains("Skipped") }, "\(testCase.name): \(log)")
        }
    }

    func testSkipsWhenFreeSpaceBelowTwiceDbPlusWal() async throws {
        let db = try makeDatabase("Envelope Index", bytes: 1000, walBytes: 500)
        let cases: [(free: Int64?, runs: Bool)] = [(2999, false), (3000, true), (nil, false)]
        for testCase in cases {
            let runner = ScriptedProcessRunner { invocation in
                invocation.arguments.last == "PRAGMA quick_check;" ? .ok("ok") : .ok()
            }

            let log = await vacuum([target(db)], processRunner: runner, freeSpace: [testCase.free])

            XCTAssertEqual(runner.invocations.count, testCase.runs ? 4 : 0, "free \(String(describing: testCase.free)): \(log)")
        }
    }

    func testSkipsWhenOwnerAppRunning() async throws {
        let mail = target(try makeDatabase("Envelope Index", bytes: 100), owner: ("com.apple.mail", "Mail"))
        let safari = target(try makeDatabase("History.db", bytes: 100), owner: ("com.apple.Safari", "Safari"))
        for (running, expectedPaths) in [("com.apple.mail", [safari.path]), ("com.apple.Safari", [mail.path])] {
            let runner = ScriptedProcessRunner { invocation in
                invocation.arguments.last == "PRAGMA quick_check;" ? .ok("ok") : .ok()
            }

            let log = await vacuum([mail, safari], processRunner: runner, running: [running])

            XCTAssertEqual(Set(runner.invocations.compactMap(\.arguments.first)), Set(expectedPaths), running)
            XCTAssertTrue(log.contains { $0.contains("Skipped") && $0.contains("quit") }, "\(running): \(log)")
        }
    }

    // MARK: - Resilience and reporting

    func testOneDbFailureContinuesOthers() async throws {
        let first = try makeDatabase("first.db", bytes: 100)
        let second = try makeDatabase("second.db", bytes: 100)
        let runner = ScriptedProcessRunner { invocation in
            if invocation.arguments.last == "PRAGMA quick_check;" { return .ok("ok") }
            if invocation.arguments == [first.path, "VACUUM;"] {
                return .failure("Error: database is locked", exitCode: 5)
            }
            return .ok()
        }

        let log = await vacuum([target(first, label: "First"), target(second, label: "Second")], processRunner: runner)

        XCTAssertEqual(runner.invocations.filter { $0.arguments.first == second.path }.count, 4)
        XCTAssertTrue(log.contains { $0.contains("First") && $0.contains("database is locked") }, "\(log)")
        XCTAssertTrue(log.contains { $0.contains("✓") && $0.contains("Second") }, "\(log)")
    }

    func testLaunchFailureContinuesOthers() async throws {
        let first = try makeDatabase("first.db", bytes: 100)
        let second = try makeDatabase("second.db", bytes: 100)
        let runner = ScriptedProcessRunner { invocation in
            if invocation.arguments.first == first.path { throw ProcessRunnerError.executableNotFound(Self.sqlite3) }
            return invocation.arguments.last == "PRAGMA quick_check;" ? .ok("ok") : .ok()
        }

        _ = await vacuum([target(first), target(second)], processRunner: runner)

        XCTAssertEqual(runner.invocations.filter { $0.arguments.first == second.path }.count, 4)
    }

    func testReportsFreeSpaceBeforeAfter() async throws {
        let db = try makeDatabase("History.db", bytes: 100)
        let runner = ScriptedProcessRunner { invocation in
            invocation.arguments.last == "PRAGMA quick_check;" ? .ok("ok") : .ok()
        }
        let gigabyte: Int64 = 1_000_000_000

        let log = await vacuum([target(db)], processRunner: runner, freeSpace: [5 * gigabyte, 5 * gigabyte, 6 * gigabyte])

        let before = try XCTUnwrap(log.firstIndex { $0.hasPrefix("Free space before:") }, "\(log)")
        let after = try XCTUnwrap(log.firstIndex { $0.hasPrefix("Free space after:") }, "\(log)")
        XCTAssertLessThan(before, after)
        XCTAssertTrue(log[before].contains("5"), log[before])
        XCTAssertTrue(log[after].contains("6"), log[after])
    }

    // MARK: - Target discovery

    func testTargetsCoverMailAndSafariButNeverMessages() throws {
        let home = tmp.appending(path: "home")
        for relative in ["Library/Mail/V10/MailData/Envelope Index", "Library/Safari/History.db", "Library/Messages/chat.db"] {
            let file = home.appending(path: relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: file)
        }

        let targets = MaintenanceRunner.vacuumTargets(homeDirectory: home)

        XCTAssertEqual(targets.map(\.ownerBundleIdentifier), ["com.apple.mail", "com.apple.Safari"])
        XCTAssertFalse(targets.contains { $0.path.hasSuffix("chat.db") })
    }

    func testMaintenanceRunnerUsesInjectedHome() async throws {
        guard FileManager.default.isExecutableFile(atPath: Self.sqlite3) else {
            throw XCTSkip("sqlite3 is not installed")
        }
        let home = tmp.appending(path: "home")
        let history = home.appending(path: "Library/Safari/History.db")
        try FileManager.default.createDirectory(at: history.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: history)
        let runner = ScriptedProcessRunner { invocation in
            invocation.arguments.last == "PRAGMA quick_check;" ? .ok("ok") : .ok()
        }
        let maintenance = MaintenanceRunner(
            processRunner: runner,
            homeDirectory: home,
            freeSpace: FixedFreeSpace([Int64.max]),
            runningApps: FixedRunningApps([])
        )

        for try await _ in maintenance.run(action: MaintenanceCatalog.vacuumDatabases) {}

        XCTAssertEqual(Set(runner.invocations.compactMap(\.arguments.first)), [history.path])
    }

    // MARK: - Integration (real sqlite3, temp database only)

    func testWalTruncatedOnRealDatabase() async throws {
        guard FileManager.default.isExecutableFile(atPath: Self.sqlite3) else {
            throw XCTSkip("sqlite3 is not installed")
        }
        let db = tmp.appending(path: "bloated.db")
        try runSQLite(db, """
        PRAGMA journal_mode=WAL;
        CREATE TABLE t(x BLOB);
        WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM c WHERE i < 2000)
        INSERT INTO t SELECT randomblob(1024) FROM c;
        DELETE FROM t;
        """)
        let sizeBefore = try fileSize(db)

        let log = await vacuum([target(db)], processRunner: SystemProcessRunner(), freeSpace: [Int64.max])

        let wal = db.path + "-wal"
        let walSize = FileManager.default.fileExists(atPath: wal) ? try fileSize(URL(fileURLWithPath: wal)) : 0
        XCTAssertEqual(walSize, 0, "WAL must be truncated after VACUUM: \(log)")
        XCTAssertLessThan(try fileSize(db), sizeBefore / 4, "VACUUM should shrink the emptied database: \(log)")
    }

    // MARK: - Helpers

    private func makeDatabase(_ name: String, bytes: Int, walBytes: Int? = nil) throws -> URL {
        let dir = tmp.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appending(path: name)
        try Data(repeating: 1, count: bytes).write(to: db)
        if let walBytes {
            try Data(repeating: 2, count: walBytes).write(to: URL(fileURLWithPath: db.path + "-wal"))
        }
        return URL(fileURLWithPath: db.path)
    }

    private func target(
        _ db: URL,
        label: String? = nil,
        owner: (bundleIdentifier: String, name: String)? = nil
    ) -> SQLiteVacuumTarget {
        SQLiteVacuumTarget(
            label: label ?? db.lastPathComponent,
            path: db.path,
            ownerBundleIdentifier: owner?.bundleIdentifier,
            ownerName: owner?.name
        )
    }

    private func vacuum(
        _ targets: [SQLiteVacuumTarget],
        processRunner: any ProcessRunning,
        freeSpace: [Int64?] = [Int64.max],
        running: Set<String> = []
    ) async -> [String] {
        let log = LogCollector()
        let runner = SQLiteVacuumRunner(
            processRunner: processRunner,
            freeSpace: FixedFreeSpace(freeSpace),
            runningApps: FixedRunningApps(running),
            sqlite3Path: Self.sqlite3
        )
        await runner.vacuum(targets) { log.append($0) }
        return log.lines
    }

    private func runSQLite(_ db: URL, _ sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.sqlite3)
        process.arguments = [db.path, sql]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    /// Reads attributes fresh: `URL.resourceValues` caches per instance and would return the pre-VACUUM size.
    private func fileSize(_ url: URL) throws -> Int64 {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.int64Value ?? 0
    }
}

/// Returns the queued values in order, repeating the last one.
final class FixedFreeSpace: FreeSpaceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64?]

    init(_ values: [Int64?]) {
        self.values = values
    }

    func availableBytes(atPath path: String) -> Int64? {
        lock.withLock { values.count > 1 ? values.removeFirst() : values.first ?? nil }
    }
}

struct FixedRunningApps: RunningAppChecking {
    let running: Set<String>

    init(_ running: Set<String>) {
        self.running = running
    }

    func isRunning(bundleIdentifier: String) -> Bool {
        running.contains(bundleIdentifier)
    }
}

private final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var lines: [String] { lock.withLock { stored } }

    func append(_ line: String) {
        lock.withLock { stored.append(line) }
    }
}
