import XCTest
@testable import PareCore

final class SymlinkSkipSummaryTests: XCTestCase {

    /// Fake for `ScanPolicy.hasSymbolicLinkComponent`: only `/Users/k` is a link, so it and everything below qualify.
    private let homeIsLink: (String) -> Bool = { $0 == "/Users/k" || $0.hasPrefix("/Users/k/") }

    private func symlinkSkip(_ path: String) -> CleanupSkippedItem {
        CleanupSkippedItem(path: path, error: .symbolicLinkBlocked(path))
    }

    func testSharedSymlinkedAncestor() {
        let cases: [(name: String, paths: [String], expected: String?)] = [
            ("home is the link", ["/Users/k/Library/Caches/a", "/Users/k/Library/Logs/b"], "/Users/k"),
            ("items differ above the link", ["/Users/k/Library/Caches/a", "/Users/other/x"], nil),
            ("single item", ["/Users/k/Library/Caches/a"], nil),
            ("no items", [], nil),
            ("dot segments standardized", ["/Users/k/./Library/a", "/Users/x/../k/Library/b"], "/Users/k"),
        ]
        for testCase in cases {
            let result = SymlinkSkipSummary.sharedSymlinkedAncestor(
                of: testCase.paths,
                hasSymbolicLinkComponent: homeIsLink
            )
            XCTAssertEqual(result, testCase.expected, testCase.name)
        }
    }

    func testNoLinkInSharedPrefixReturnsNil() {
        let result = SymlinkSkipSummary.sharedSymlinkedAncestor(
            of: ["/Users/a/Library/x", "/Users/a/Library/y"],
            hasSymbolicLinkComponent: { $0.hasPrefix("/Users/a/Library/x") }
        )
        XCTAssertNil(result)
    }

    func testMessageNamesAncestorWhenEverySkipIsSymlinkBlocked() {
        let skipped = [symlinkSkip("/Users/k/Library/Caches/a"), symlinkSkip("/Users/k/Library/Caches/b")]

        let message = SymlinkSkipSummary.message(for: skipped, hasSymbolicLinkComponent: homeIsLink)

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("/Users/k") == true)
        XCTAssertTrue(message?.contains("2") == true)
    }

    func testMessageIsNilWhenAnySkipHasAnotherReason() {
        let skipped = [
            symlinkSkip("/Users/k/Library/Caches/a"),
            CleanupSkippedItem(path: "/Users/k/Library/Caches/b", error: .tooNew("/Users/k/Library/Caches/b")),
        ]

        XCTAssertNil(SymlinkSkipSummary.message(for: skipped, hasSymbolicLinkComponent: homeIsLink))
    }
}
