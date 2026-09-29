import Foundation
import XCTest
@testable import PareApp

final class DiskLevelLoaderTests: XCTestCase {
    func testLevelIncludesHiddenEntriesAndAllRowsRemainSearchable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DiskLevelLoaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<205 {
            let name = index == 204 ? "target-below-old-cap.txt" : "entry-\(index).txt"
            try Data([0]).write(to: directory.appending(path: name))
        }
        try Data([0]).write(to: directory.appending(path: ".hidden-cache"))

        let level = try await DiskLevelLoader().load(directory: directory)
        XCTAssertEqual(level.entries.count, 206)
        XCTAssertTrue(level.entries.contains { $0.name == ".hidden-cache" })

        let matches = DiskTableQuery.apply(
            entries: level.entries,
            search: "target-below-old-cap",
            kind: nil,
            sizeFloor: .any,
            sortOrder: .nameAscending
        )
        XCTAssertEqual(matches.map(\.name), ["target-below-old-cap.txt"])
    }

    /// A symlink and its same-folder target must be two rows, or selection acts on the wrong one.
    func testSymlinkSiblingKeepsItsOwnRowID() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DiskLevelLoaderTests-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "libz.1.dylib")
        try Data([0, 1, 2]).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "libz.dylib"),
            withDestinationURL: target
        )

        let level = try await DiskLevelLoader().load(directory: directory)

        XCTAssertEqual(level.entries.count, 2)
        XCTAssertEqual(Set(level.entries.map(\.id)).count, 2)
        let link = try XCTUnwrap(level.entries.first { $0.name == "libz.dylib" })
        XCTAssertEqual(URL(fileURLWithPath: link.id).lastPathComponent, "libz.dylib")
    }

    /// Refresh must drop stale ancestor sizes too, not only the current folder.
    func testInvalidateDirectoryAndAncestorsDropsParentLevel() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appending(path: "DiskLevelLoaderTests-ancestors-\(UUID().uuidString)")
        let child = parent.appending(path: "child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let loader = DiskLevelLoader()

        let before = try await loader.load(directory: parent)
        _ = try await loader.load(directory: child)
        try Data(repeating: 1, count: 64_000).write(to: child.appending(path: "new.bin"))
        await loader.invalidate(directoryAndAncestors: child)
        let after = try await loader.load(directory: parent)

        XCTAssertGreaterThan(after.totalBytes, before.totalBytes)
    }

    /// A mounted volume is listed but never deep-walked from its parent.
    func testMountedVolumeChildIsListedButNotSized() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DiskLevelLoaderTests-volume-\(UUID().uuidString)")
        let volume = directory.appending(path: "ExternalDisk")
        let local = directory.appending(path: "local")
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 1, count: 64_000).write(to: volume.appending(path: "big.bin"))
        try Data(repeating: 1, count: 4_000).write(to: local.appending(path: "small.bin"))
        let loader = DiskLevelLoader(isMountPoint: { $0.lastPathComponent == "ExternalDisk" })

        let level = try await loader.load(directory: directory)

        let volumeRow = try XCTUnwrap(level.entries.first { $0.name == "ExternalDisk" })
        XCTAssertTrue(volumeRow.isSeparateVolume)
        XCTAssertTrue(volumeRow.isDirectory)
        XCTAssertEqual(volumeRow.sizeBytes, 0)
        XCTAssertEqual(volumeRow.itemCount, 0)
        let localRow = try XCTUnwrap(level.entries.first { $0.name == "local" })
        XCTAssertFalse(localRow.isSeparateVolume)
        XCTAssertEqual(localRow.itemCount, 1)
        XCTAssertEqual(level.totalBytes, localRow.sizeBytes)
    }

    private func makeDirectory(_ label: String, fileCount: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DiskLevelLoaderTests-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<fileCount {
            try Data([0]).write(to: directory.appending(path: "file-\(index).bin"))
        }
        return directory
    }

    func testSecondLoadIsServedFromCacheUntilThatFolderIsInvalidated() async throws {
        let directory = try makeDirectory("cache", fileCount: 2)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = DiskLevelLoader()

        _ = try await loader.load(directory: directory)
        try Data([0]).write(to: directory.appending(path: "added-later.bin"))
        let cached = try await loader.load(directory: directory)
        await loader.invalidate(directory: directory)
        let fresh = try await loader.load(directory: directory)

        XCTAssertEqual(cached.entries.count, 2)
        XCTAssertEqual(fresh.entries.count, 3)
    }

    func testCancelledLoadThrowsAndIsNotCached() async throws {
        let directory = try makeDirectory("cancel", fileCount: 3)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = DiskLevelLoader()

        let cancelled = Task { () async throws -> DiskLevelLoader.Level in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.load(directory: directory)
        }
        do {
            _ = try await cancelled.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {}
        try Data([0]).write(to: directory.appending(path: "after-cancel.bin"))
        let level = try await loader.load(directory: directory)

        XCTAssertEqual(level.entries.count, 4)
    }

    func testMissingDirectoryThrowsAndLaterLoadSucceeds() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DiskLevelLoaderTests-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = DiskLevelLoader()

        do {
            _ = try await loader.load(directory: directory)
            XCTFail("expected an error for a missing directory")
        } catch is CancellationError {
            XCTFail("a missing directory must not look like a cancellation")
        } catch {}
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let level = try await loader.load(directory: directory)

        XCTAssertTrue(level.entries.isEmpty)
    }
}
