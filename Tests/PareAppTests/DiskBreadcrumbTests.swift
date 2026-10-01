import XCTest
@testable import PareApp

final class DiskBreadcrumbTests: XCTestCase {

    func testRootEqualsCurrentProducesSingleCrumb() {
        let url = URL(fileURLWithPath: "/Users/k")
        let breadcrumb = DiskBreadcrumb(root: url, current: url)

        XCTAssertNotNil(breadcrumb)
        XCTAssertEqual(breadcrumb?.crumbs.count, 1)
        XCTAssertNil(breadcrumb?.up())
    }

    func testTrailingSlashDoesNotChangeCrumbs() {
        let breadcrumb = DiskBreadcrumb(
            root: URL(fileURLWithPath: "/Users/k/"),
            current: URL(fileURLWithPath: "/Users/k/Library/")
        )

        XCTAssertNotNil(breadcrumb)
        XCTAssertEqual(breadcrumb?.crumbs.count, 2)
        XCTAssertEqual(breadcrumb?.crumbs.last?.name, "Library")
    }

    func testPrivateVarIndirectionStillMatches() {
        // Root spelled as NSTemporaryDirectory() would (/var/folders/...), current spelled
        // as a real filesystem enumerator would return it (/private/var/folders/...).
        let breadcrumb = DiskBreadcrumb(
            root: URL(fileURLWithPath: "/var/folders/zz/T/DiskBreadcrumbTest"),
            current: URL(fileURLWithPath: "/private/var/folders/zz/T/DiskBreadcrumbTest/sub")
        )

        XCTAssertNotNil(breadcrumb)
        XCTAssertEqual(breadcrumb?.root.path, "/private/var/folders/zz/T/DiskBreadcrumbTest")
        XCTAssertEqual(breadcrumb?.crumbs.count, 2)
    }

    func testCurrentOutsideRootIsRejected() {
        let breadcrumb = DiskBreadcrumb(
            root: URL(fileURLWithPath: "/Users/k/Documents"),
            current: URL(fileURLWithPath: "/Users/k/Desktop")
        )

        XCTAssertNil(breadcrumb)
    }

    func testUpMovesOneLevelAndEnterRestoresIt() {
        let breadcrumb = DiskBreadcrumb(
            root: URL(fileURLWithPath: "/Users/k"),
            current: URL(fileURLWithPath: "/Users/k/Library/Caches")
        )!

        let parent = breadcrumb.up()
        XCTAssertEqual(parent?.current.path, "/Users/k/Library")

        let restored = parent?.enter(URL(fileURLWithPath: "/Users/k/Library/Caches"))
        XCTAssertEqual(restored?.current.path, "/Users/k/Library/Caches")
    }

    func testEnterRejectsPathOutsideCurrentLevel() {
        let breadcrumb = DiskBreadcrumb(
            root: URL(fileURLWithPath: "/Users/k"),
            current: URL(fileURLWithPath: "/Users/k/Library/Caches")
        )!

        XCTAssertNil(breadcrumb.enter(URL(fileURLWithPath: "/Users/k/Desktop")))
    }

    func testEnterRejectsSiblingWithOverlappingName() {
        // `uv-backup` must never be treated as a child of `uv` — component-exact match only.
        let breadcrumb = DiskBreadcrumb(
            root: URL(fileURLWithPath: "/Users/k/.cache"),
            current: URL(fileURLWithPath: "/Users/k/.cache/uv")
        )!

        XCTAssertNil(breadcrumb.enter(URL(fileURLWithPath: "/Users/k/.cache/uv-backup")))
    }
}
