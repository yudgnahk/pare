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
}
