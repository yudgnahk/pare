import XCTest
@testable import PareCore

/// `brew cleanup` is previewed with `-n`, and runs only after confirmation with exactly `["cleanup"]`.
final class BrewCleanupTests: XCTestCase {

    /// The two `Warning:` lines were captured from `brew cleanup -n` on a real machine (nothing to clean
    /// there); the `Would remove` lines and summary follow Homebrew's output format. Home is `/Users/user`.
    private static let preview = """
    Warning: Skipping circleci: most recent version 1.2.0 not installed
    Warning: Skipping libomp: most recent version 23.1.3 not installed
    Would remove: /opt/homebrew/Cellar/node/20.1.0 (2,345 files, 60.1MB)
    Would remove: /opt/homebrew/Cellar/jq/1.6 (18 files, 1.1MB)
    Would remove: /Users/user/Library/Caches/Homebrew/downloads/abc123--wget-1.21.bottle.tar.gz (1.5GB)
    Would remove: /Users/user/Library/Logs/Homebrew/wget/ (1 file, 64B)
    ==> This operation would free approximately 1.6GB of disk space.
    """

    // MARK: - Parsing

    func testParsesItemsAndHomebrewTotal() {
        let parsed = BrewCleanupPreview.parse(Self.preview)

        XCTAssertEqual(parsed.items.map(\.path), [
            "/opt/homebrew/Cellar/node/20.1.0",
            "/opt/homebrew/Cellar/jq/1.6",
            "/Users/user/Library/Caches/Homebrew/downloads/abc123--wget-1.21.bottle.tar.gz",
            "/Users/user/Library/Logs/Homebrew/wget/",
        ])
        XCTAssertEqual(parsed.items.map(\.fileCount), [2345, 18, nil, 1])
        XCTAssertEqual(parsed.items.first?.bytes, Int64(60.1 * 1_048_576))
        XCTAssertEqual(parsed.items.last?.bytes, 64)
        XCTAssertEqual(parsed.totalBytes, Int64(1.6 * 1_073_741_824), "Homebrew's own total wins when printed")
    }

    func testSizeTable() {
        let cases: [(token: String, bytes: Int64?)] = [
            ("64B", 64), ("1.2KB", Int64(1.2 * 1024)), ("60.1MB", Int64(60.1 * 1_048_576)),
            ("1.5GB", Int64(1.5 * 1_073_741_824)), ("2TB", 2 * 1_099_511_627_776),
            ("", nil), ("MB", nil), ("lots", nil), ("-1MB", nil),
        ]
        for testCase in cases {
            XCTAssertEqual(BrewCleanupPreview.bytes(fromHomebrewSize: testCase.token), testCase.bytes, testCase.token)
        }
    }

    func testEmptyGarbageAndSummaryOnlyOutput() {
        XCTAssertTrue(BrewCleanupPreview.parse("").isEmpty)
        XCTAssertTrue(BrewCleanupPreview.parse("Warning: Skipping glab: most recent version 1.121.0 not installed").isEmpty)
        XCTAssertTrue(BrewCleanupPreview.parse("Would remove: relative/path (1MB)\nWould remove: /x (no size)\ngarbage").isEmpty)
        let summed = BrewCleanupPreview.parse("Would remove: /a (1KB)\nWould remove: /b (2KB)")
        XCTAssertEqual(summed.totalBytes, 3 * 1024, "without a summary line the items are summed")
    }

    // MARK: - Action

    func testRunRequiresConfirmation() async {
        let stub = StubProcessRunner(result: ProcessResult(standardOutput: Self.preview, standardError: "", exitCode: 0))
        let action = BrewCleanupAction(runner: BrewRunner(brewPath: "/fake/bin/brew", processRunner: stub))

        do {
            _ = try await action.run(confirmed: false) { _ in }
            XCTFail("must refuse without confirmation")
        } catch {
            XCTAssertEqual(error as? BrewCleanupError, .notConfirmed)
        }
        XCTAssertTrue(stub.invocations.isEmpty, "nothing runs without confirmation, not even the preview")
    }

    func testConfirmedRunRePreviewsThenRunsExactlyCleanup() async throws {
        let stub = StubProcessRunner(
            result: ProcessResult(standardOutput: Self.preview, standardError: "", exitCode: 0),
            lines: [.stdout("Removing: /opt/homebrew/Cellar/node/20.1.0... (2,345 files, 60.1MB)")]
        )
        let action = BrewCleanupAction(runner: BrewRunner(brewPath: "/fake/bin/brew", processRunner: stub))
        let log = LineCollector()

        let actedOn = try await action.run(confirmed: true) { log.append($0) }

        XCTAssertEqual(stub.invocations.map(\.arguments), [["cleanup", "-n"], ["cleanup"]])
        XCTAssertEqual(actedOn.items.count, 4)
        XCTAssertEqual(log.lines.count, 1)
    }

    func testNothingToCleanOrFailedPreviewNeverRunsCleanup() async {
        let empty = StubProcessRunner(result: ProcessResult(standardOutput: "", standardError: "", exitCode: 0))
        let failing = StubProcessRunner(result: ProcessResult(standardOutput: "", standardError: "Error: boom", exitCode: 1))
        for (name, stub, expected) in [("empty", empty, BrewCleanupError.nothingToClean as Error?), ("failing", failing, nil)] {
            let action = BrewCleanupAction(runner: BrewRunner(brewPath: "/fake/bin/brew", processRunner: stub))
            do {
                _ = try await action.run(confirmed: true) { _ in }
                XCTFail("\(name): must not run")
            } catch {
                if let expected { XCTAssertEqual(error as? BrewCleanupError, expected as? BrewCleanupError, name) }
            }
            XCTAssertEqual(stub.invocations.map(\.arguments), [["cleanup", "-n"]], name)
        }
    }

    func testMissingBrewFailsThePreview() async {
        let action = BrewCleanupAction(runner: BrewRunner(brewPath: nil, processRunner: StubProcessRunner()))

        do {
            _ = try await action.preview()
            XCTFail("no brew, no preview")
        } catch {}
    }
}

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var lines: [String] { lock.withLock { stored } }

    func append(_ line: String) { lock.withLock { stored.append(line) } }
}
