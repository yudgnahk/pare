import XCTest
@testable import PareCore

final class FindingDeduplicatorTests: XCTestCase {

    private func finding(
        _ path: String,
        risk: RiskLevel = .safe,
        category: ScanCategory = .userCaches,
        reason: String = "reason",
        size: Int64 = 100
    ) -> ScanFinding {
        ScanFinding(
            category: category,
            riskLevel: risk,
            reason: reason,
            path: path,
            sizeBytes: size,
            lastUsed: nil,
            confidence: 1.0
        )
    }

    private func dedupe(_ items: [(Int, ScanFinding)]) -> [ScanFinding] {
        FindingDeduplicator.deduplicate(items.map { (ruleIndex: $0.0, finding: $0.1) })
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(dedupe([]).isEmpty)
    }

    func testSamePathSameRiskYieldsOneFinding() {
        let result = dedupe([
            (0, finding("/a/cache")),
            (1, finding("/a/cache")),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.path, "/a/cache")
    }

    func testSamePathHighestRiskWinsInEitherRuleOrder() {
        let cases: [(name: String, items: [(Int, ScanFinding)])] = [
            ("safe first", [(0, finding("/a/x", risk: .safe)), (1, finding("/a/x", risk: .review))]),
            ("review first", [(0, finding("/a/x", risk: .review)), (1, finding("/a/x", risk: .safe))]),
        ]
        for testCase in cases {
            let result = dedupe(testCase.items)
            XCTAssertEqual(result.count, 1, testCase.name)
            XCTAssertEqual(result.first?.riskLevel, .review, testCase.name)
        }
    }

    func testSamePathTieTakesCategoryAndReasonFromLowerRuleIndex() {
        let result = dedupe([
            (3, finding("/a/x", category: .developerPackageCaches, reason: "later rule", size: 7)),
            (1, finding("/a/x", category: .browserCaches, reason: "earlier rule", size: 9)),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.category, .browserCaches)
        XCTAssertEqual(result.first?.reason, "earlier rule")
        XCTAssertEqual(result.first?.sizeBytes, 9)
    }

    func testCanonicalSpellingsCountAsOnePath() {
        let cases: [(name: String, a: String, b: String)] = [
            ("private alias", "/tmp/x", "/private/tmp/x"),
            ("trailing slash", "/x", "/x/"),
            ("case variant", "/Users/me/Cache", "/users/ME/cache"),
        ]
        for testCase in cases {
            let result = dedupe([(0, finding(testCase.a)), (1, finding(testCase.b))])
            XCTAssertEqual(result.count, 1, testCase.name)
        }
    }

    func testFolderAndFileInsideKeepsOnlyFolder() {
        let result = dedupe([
            (1, finding("/a/cache/file.bin", size: 10)),
            (0, finding("/a/cache", size: 100)),
        ])
        XCTAssertEqual(result.map(\.path), ["/a/cache"])
        XCTAssertEqual(result.first?.sizeBytes, 100)
    }

    func testSafeAncestorWithReviewDescendantBecomesReview() {
        let result = dedupe([
            (0, finding("/a/profile", risk: .safe, reason: "ancestor")),
            (1, finding("/a/profile/IndexedDB", risk: .review, reason: "descendant")),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.path, "/a/profile")
        XCTAssertEqual(result.first?.riskLevel, .review)
        XCTAssertEqual(result.first?.reason, "ancestor")
    }

    func testSafeAncestorWithAdvancedDescendantKeepsBothAndRaisesAncestor() {
        let result = dedupe([
            (0, finding("/a/caches", risk: .safe)),
            (1, finding("/a/caches/uv", risk: .advanced)),
        ])
        let byPath = Dictionary(uniqueKeysWithValues: result.map { ($0.path, $0.riskLevel) })
        XCTAssertEqual(byPath, ["/a/caches": .review, "/a/caches/uv": .advanced])
    }

    func testAdvancedAncestorKeepsSafeDescendantUnchanged() {
        let result = dedupe([
            (0, finding("/a/uv", risk: .advanced)),
            (1, finding("/a/uv/archive", risk: .safe)),
        ])
        let byPath = Dictionary(uniqueKeysWithValues: result.map { ($0.path, $0.riskLevel) })
        XCTAssertEqual(byPath, ["/a/uv": .advanced, "/a/uv/archive": .safe])
    }

    func testSiblingWithSharedNamePrefixIsNotADescendant() {
        let result = dedupe([
            (0, finding("/a/foo")),
            (1, finding("/a/foobar")),
        ])
        XCTAssertEqual(Set(result.map(\.path)), ["/a/foo", "/a/foobar"])
    }

    func testComponentOrderingKeepsDescendantNextToAncestor() {
        // String order would put "/a/b c" between "/a/b" and "/a/b/c".
        let result = dedupe([
            (0, finding("/a/b c")),
            (1, finding("/a/b/c")),
            (2, finding("/a/b")),
        ])
        XCTAssertEqual(Set(result.map(\.path)), ["/a/b", "/a/b c"])
    }

    func testOutputPreservesInputOrderOfSurvivors() {
        let result = dedupe([
            (0, finding("/z/one")),
            (1, finding("/a/two")),
            (2, finding("/m/three")),
        ])
        XCTAssertEqual(result.map(\.path), ["/z/one", "/a/two", "/m/three"])
    }
}
