import XCTest
@testable import PareApp

final class DiskEntryIDTests: XCTestCase {

    private let nfcPath = "/Volumes/Share/caf\u{E9}"
    private let nfdPath = "/Volumes/Share/cafe\u{301}"

    private func makeEntry(path: String) -> DiskEntry {
        DiskEntry(
            id: path, url: URL(fileURLWithPath: path), name: URL(fileURLWithPath: path).lastPathComponent,
            isDirectory: false, isPackage: false, sizeBytes: 1, itemCount: 1, modified: nil, kind: .other
        )
    }

    /// Swift `String ==` treats these as equal, so a String id would merge two real rows.
    func testNFCAndNFDSiblingsGetDistinctIDs() {
        XCTAssertEqual(nfcPath, nfdPath, "precondition: String equality is canonical")
        let nfc = makeEntry(path: nfcPath)
        let nfd = makeEntry(path: nfdPath)

        XCTAssertNotEqual(nfc.id, nfd.id)
        XCTAssertEqual(Set([nfc.id, nfd.id]).count, 2)
    }

    func testSameBytesGiveEqualStableIDs() {
        let first = makeEntry(path: nfdPath)
        let second = makeEntry(path: nfdPath)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.id.hashValue, second.id.hashValue)
        XCTAssertEqual(first.id.path, nfdPath)
    }

    /// Mirrors the table's `entry(for:)` and the view's `selectedEntry` lookups.
    func testSelectionLookupFindsTheExactRow() {
        let entries = [makeEntry(path: nfcPath), makeEntry(path: nfdPath)]
        let selection: Set<DiskEntryID> = [entries[1].id]

        let selected = entries.filter { selection.contains($0.id) }

        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(selected.first?.id.path.utf8.elementsEqual(nfdPath.utf8) == true)
        XCTAssertEqual(entries.first { $0.id == entries[0].id }?.id, entries[0].id)
    }

    func testTableOrderIsTotalForCanonicallyEqualPaths() {
        let nfc = makeEntry(path: nfcPath)
        let nfd = makeEntry(path: nfdPath)

        let forward = DiskTableQuery.ordering(nfc, nfd, by: .nameAscending)
        let backward = DiskTableQuery.ordering(nfd, nfc, by: .nameAscending)

        XCTAssertNotEqual(forward, .orderedSame)
        XCTAssertEqual(forward, backward == .orderedAscending ? .orderedDescending : .orderedAscending)
    }
}
