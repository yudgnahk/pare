import XCTest
@testable import PareCore

final class DirectorySizeIndexTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("size-index-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func writeFile(named name: String, byteCount: Int) throws {
        let data = Data(repeating: 0xAB, count: byteCount)
        try data.write(to: tempDir.appendingPathComponent(name))
    }

    // MARK: - Correctness

    func testFirstRequestMatchesFileSystemUtils() throws {
        try writeFile(named: "a.bin", byteCount: 64 * 1024)
        try writeFile(named: "b.bin", byteCount: 32 * 1024)

        let index = DirectorySizeIndex()
        XCTAssertEqual(
            index.directorySize(url: tempDir),
            FileSystemUtils.directorySize(url: tempDir),
            "Index must report the same size as the underlying utility"
        )
        XCTAssertGreaterThan(index.directorySize(url: tempDir), 0)
    }

    // MARK: - Memoization (one computation per directory)

    func testSecondRequestIsServedFromMemoNotRecomputed() throws {
        try writeFile(named: "a.bin", byteCount: 64 * 1024)

        let index = DirectorySizeIndex()
        let first = index.directorySize(url: tempDir)

        // Grow the directory. A re-walk would see the new file; the memoized
        // index must keep returning the size captured on the first walk.
        try writeFile(named: "late-arrival.bin", byteCount: 128 * 1024)
        let underlyingNow = FileSystemUtils.directorySize(url: tempDir)
        XCTAssertGreaterThan(underlyingNow, first, "sanity: the tree really did grow")

        let second = index.directorySize(url: tempDir)
        XCTAssertEqual(second, first, "same index + same directory = exactly one size computation")
    }

    func testEquivalentPathsShareOneEntry() throws {
        try writeFile(named: "a.bin", byteCount: 64 * 1024)

        let index = DirectorySizeIndex()
        let direct = index.directorySize(url: tempDir)

        try writeFile(named: "late-arrival.bin", byteCount: 128 * 1024)

        // Same directory addressed via a non-standardized path must hit the memo.
        let indirect = index.directorySize(
            url: tempDir.appendingPathComponent("sub/..", isDirectory: true)
        )
        XCTAssertEqual(indirect, direct)
    }

    func testFreshIndexRecomputes() throws {
        try writeFile(named: "a.bin", byteCount: 64 * 1024)

        let staleIndex = DirectorySizeIndex()
        let before = staleIndex.directorySize(url: tempDir)

        try writeFile(named: "b.bin", byteCount: 128 * 1024)

        let freshIndex = DirectorySizeIndex()
        XCTAssertGreaterThan(
            freshIndex.directorySize(url: tempDir),
            before,
            "a fresh per-scan index must re-walk the directory"
        )
    }

    // MARK: - ScanEnvironment threading

    func testWithFreshSizeIndexSwapsTheIndexOnly() {
        let environment = ScanEnvironment(homeDirectory: tempDir)
        let next = environment.withFreshSizeIndex()

        XCTAssertTrue(environment.sizeIndex !== next.sizeIndex, "each scan gets its own index")
        XCTAssertEqual(environment.homeDirectory, next.homeDirectory)
        XCTAssertEqual(environment.tempDirectory, next.tempDirectory)
    }
}
