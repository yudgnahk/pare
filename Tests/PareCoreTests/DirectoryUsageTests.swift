import XCTest
@testable import PareCore

final class DirectoryUsageTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("directory-usage-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func writeFile(named name: String, byteCount: Int, modified: Date? = nil) throws {
        let data = Data(repeating: 0xAB, count: byteCount)
        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    func testMatchesDirectorySizeForAllocatedBytes() throws {
        try writeFile(named: "a.bin", byteCount: 64 * 1024)
        try writeFile(named: "b.bin", byteCount: 32 * 1024)

        let usage = FileSystemUtils.directoryUsage(url: tempDir)
        XCTAssertEqual(usage.allocatedBytes, FileSystemUtils.directorySize(url: tempDir))
        XCTAssertGreaterThan(usage.allocatedBytes, 0)
    }

    func testCountsRegularFilesOnly() throws {
        try writeFile(named: "a.bin", byteCount: 1024)
        try writeFile(named: "b.bin", byteCount: 1024)
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("subdir"), withIntermediateDirectories: true
        )
        try writeFile(named: "subdir/c.bin", byteCount: 1024)

        let usage = FileSystemUtils.directoryUsage(url: tempDir)
        XCTAssertEqual(usage.itemCount, 3)
    }

    func testNewestModificationIsTheMostRecentFile() throws {
        let older = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)
        try writeFile(named: "old.bin", byteCount: 1024, modified: older)
        try writeFile(named: "new.bin", byteCount: 1024, modified: newer)

        let usage = FileSystemUtils.directoryUsage(url: tempDir)
        XCTAssertEqual(usage.newestModification, newer)
    }

    func testEmptyDirectoryReportsZeroesAndNilDate() throws {
        let usage = FileSystemUtils.directoryUsage(url: tempDir)
        XCTAssertEqual(usage.allocatedBytes, 0)
        XCTAssertEqual(usage.itemCount, 0)
        XCTAssertNil(usage.newestModification)
    }

    func testNonexistentURLReturnsZeroUsage() {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        let usage = FileSystemUtils.directoryUsage(url: missing)
        XCTAssertEqual(usage.allocatedBytes, 0)
        XCTAssertEqual(usage.itemCount, 0)
        XCTAssertNil(usage.newestModification)
    }
}
