import XCTest
@testable import PareApp

final class DiskTableQueryTests: XCTestCase {

    private func entry(
        _ name: String,
        size: Int64 = 0,
        items: Int = 0,
        modified: Date? = nil,
        kind: DiskKind = .other
    ) -> DiskEntry {
        DiskEntry(
            id: "/root/\(name)",
            url: URL(fileURLWithPath: "/root/\(name)"),
            name: name,
            isDirectory: kind == .folder,
            isPackage: false,
            sizeBytes: size,
            itemCount: items,
            modified: modified,
            kind: kind
        )
    }

    // MARK: - Search

    func testSearchIsCaseAndDiacriticInsensitive() {
        let entries = [entry("Café Notes"), entry("Budget")]
        let result = DiskTableQuery.apply(
            entries: entries, search: "cafe notes", kind: nil,
            sizeFloor: .any, sortOrder: .nameAscending
        )
        XCTAssertEqual(result.map(\.name), ["Café Notes"])
    }

    func testEmptySearchMatchesEverything() {
        let entries = [entry("A"), entry("B")]
        let result = DiskTableQuery.apply(
            entries: entries, search: "", kind: nil, sizeFloor: .any, sortOrder: .nameAscending
        )
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Kind filter

    func testKindFilterKeepsOnlyMatchingKind() {
        let entries = [entry("pic", kind: .image), entry("clip", kind: .video)]
        let result = DiskTableQuery.apply(
            entries: entries, search: "", kind: .image, sizeFloor: .any, sortOrder: .nameAscending
        )
        XCTAssertEqual(result.map(\.name), ["pic"])
    }

    func testNilKindMeansAnyKind() {
        let entries = [entry("pic", kind: .image), entry("clip", kind: .video)]
        let result = DiskTableQuery.apply(
            entries: entries, search: "", kind: nil, sizeFloor: .any, sortOrder: .nameAscending
        )
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Size buckets

    func testSizeFloorExcludesSmallerEntries() {
        let entries = [
            entry("tiny", size: 500_000),
            entry("medium", size: 50_000_000),
            entry("big", size: 2_000_000_000),
        ]
        let result = DiskTableQuery.apply(
            entries: entries, search: "", kind: nil, sizeFloor: .oneHundredMB, sortOrder: .nameAscending
        )
        XCTAssertEqual(Set(result.map(\.name)), ["big"])
    }

    // MARK: - Sorting

    func testSortsBySizeDescending() {
        let entries = [entry("small", size: 10), entry("large", size: 1_000)]
        let result = DiskTableQuery.apply(
            entries: entries, search: "", kind: nil, sizeFloor: .any,
            sortOrder: DiskSortDescriptor(field: .size, ascending: false)
        )
        XCTAssertEqual(result.map(\.name), ["large", "small"])
    }

    func testStableNameTiebreakWhenPrimaryFieldTies() {
        let entries = [entry("Zebra", size: 100), entry("Apple", size: 100)]
        let result = DiskTableQuery.apply(
            entries: entries, search: "", kind: nil, sizeFloor: .any,
            sortOrder: DiskSortDescriptor(field: .size, ascending: true)
        )
        XCTAssertEqual(result.map(\.name), ["Apple", "Zebra"])
    }

    func testSortsByModifiedWithNilTreatedAsOldest() {
        let older = Date(timeIntervalSince1970: 0)
        let entries = [entry("dated", modified: older), entry("undated", modified: nil)]
        let result = DiskTableQuery.apply(
            entries: entries, search: "", kind: nil, sizeFloor: .any,
            sortOrder: DiskSortDescriptor(field: .modified, ascending: true)
        )
        XCTAssertEqual(result.map(\.name), ["undated", "dated"])
    }

    func testSearchFindsDecomposedUnicodeNameAndCombinedFilters() {
        let entries = [
            entry("Cafe\u{301} Archive", size: 200_000_000, kind: .archive),
            entry("Cafe\u{301} Photo", size: 500_000, kind: .image),
            entry("Plain Archive", size: 250_000_000, kind: .archive),
        ]
        let result = DiskTableQuery.apply(
            entries: entries,
            search: "café archive",
            kind: .archive,
            sizeFloor: .oneHundredMB,
            sortOrder: .nameAscending
        )
        XCTAssertEqual(result.map(\.name), ["Cafe\u{301} Archive"])
    }
}
