import XCTest
@testable import PareCore

final class DirectoryListingTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        // Uncanonical `/var/…` spelling on purpose: listings must resolve it the way FileManager does.
        tmp = FileManager.default.temporaryDirectory.appending(path: "pare_listing_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testTypesEntriesWithoutFollowingSymlinks() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: tmp.appending(path: "dir"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: tmp.appending(path: "file.txt"))
        try Data().write(to: tmp.appending(path: ".hidden"))
        try fm.createSymbolicLink(at: tmp.appending(path: "link-to-dir"), withDestinationURL: tmp.appending(path: "dir"))
        try fm.createDirectory(at: tmp.appending(path: "Zoë café"), withIntermediateDirectories: true)

        let listing = try XCTUnwrap(DirectoryListing.contents(of: tmp))
        let kinds = Dictionary(uniqueKeysWithValues: listing.entries.map { ($0.name, $0.kind) })

        XCTAssertEqual(kinds, [
            "dir": .directory,
            "file.txt": .regularFile,
            ".hidden": .regularFile,
            "link-to-dir": .symbolicLink,
            "Zoë café": .directory,
        ])
    }

    func testChildPathsMatchFileManagerSpelling() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: tmp.appending(path: "real/sub/leaf"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: tmp.appending(path: "alias"), withDestinationURL: tmp.appending(path: "real"))
        let throughAlias = tmp.appending(path: "alias/sub")

        let listing = try XCTUnwrap(DirectoryListing.contents(of: throughAlias))
        let expected = try fm.contentsOfDirectory(at: throughAlias, includingPropertiesForKeys: nil).map(\.path)

        XCTAssertEqual(listing.entries.map { listing.url(of: $0).path }, expected)
        XCTAssertTrue(listing.directory.path.hasPrefix("/private/"), listing.directory.path)
    }

    func testSymlinkedOrUnopenableDirectoryIsNil() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: tmp.appending(path: "real"), withIntermediateDirectories: true)
        try Data().write(to: tmp.appending(path: "real/file"))
        try fm.createSymbolicLink(at: tmp.appending(path: "alias"), withDestinationURL: tmp.appending(path: "real"))

        XCTAssertNil(DirectoryListing.contents(of: tmp.appending(path: "alias")), "FileManager does not list through it either")
        XCTAssertNil(DirectoryListing.contents(of: tmp.appending(path: "missing")))
        XCTAssertNil(DirectoryListing.contents(of: tmp.appending(path: "real/file")))
        XCTAssertEqual(DirectoryListing.contents(of: tmp.appending(path: "real"))?.entries.map(\.name), ["file"])
    }

    func testForEachStopsWhenBodyReturnsFalse() throws {
        for index in 0..<10 {
            try Data().write(to: tmp.appending(path: "f\(index)"))
        }
        var seen = 0

        let resolved = DirectoryListing.forEach(in: tmp) { _ in
            seen += 1
            return seen < 3
        }

        XCTAssertNotNil(resolved)
        XCTAssertEqual(seen, 3)
    }
}
