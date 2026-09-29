import XCTest
import PareCore
@testable import PareApp

final class DiskReviewResolverTests: XCTestCase {

    private func makeFinding(
        path: String,
        riskLevel: RiskLevel = .safe,
        category: ScanCategory = .userCaches
    ) -> ScanFinding {
        ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: "test fixture",
            path: path,
            sizeBytes: 1_024,
            lastUsed: nil,
            confidence: 1.0
        )
    }

    func testEmptyFindingsIsNoScan() {
        let result = DiskReviewResolver.resolve(entryPath: "/Users/k/Library/Caches/foo", findings: [])

        guard case .noScan = result else {
            return XCTFail("expected .noScan, got \(result)")
        }
    }

    func testExactPathMatchIsCovered() {
        let finding = makeFinding(path: "/Users/k/Library/Caches/foo")

        let result = DiskReviewResolver.resolve(entryPath: "/Users/k/Library/Caches/foo", findings: [finding])

        guard case .covered(let findings) = result else {
            return XCTFail("expected .covered, got \(result)")
        }
        XCTAssertEqual(findings.map(\.path), [finding.path])
    }

    func testFindingNestedInsideEntryIsCovered() {
        let finding = makeFinding(path: "/Users/k/Library/Caches/foo/sub-cache")

        let result = DiskReviewResolver.resolve(entryPath: "/Users/k/Library/Caches/foo", findings: [finding])

        guard case .covered(let findings) = result else {
            return XCTFail("expected .covered, got \(result)")
        }
        XCTAssertEqual(findings.count, 1)
    }

    func testEntryNestedInsideFindingIsInsideFinding() {
        let finding = makeFinding(path: "/Users/k/Library/Caches")

        let result = DiskReviewResolver.resolve(entryPath: "/Users/k/Library/Caches/foo", findings: [finding])

        guard case .insideFinding(let matched) = result else {
            return XCTFail("expected .insideFinding, got \(result)")
        }
        XCTAssertEqual(matched.path, finding.path)
    }

    func testNearestFindingWinsWhenMultipleFindingsCoverEntry() {
        let outer = makeFinding(path: "/Users/k/Library/Caches")
        let nearest = makeFinding(path: "/Users/k/Library/Caches/App")
        let result = DiskReviewResolver.resolve(
            entryPath: "/Users/k/Library/Caches/App/Cache.db",
            findings: [outer, nearest]
        )
        guard case .insideFinding(let matched) = result else {
            return XCTFail("expected .insideFinding, got \(result)")
        }
        XCTAssertEqual(matched.path, nearest.path)
    }

    /// Matches `ScanPolicy.isEqualToOrDescendant`, which compares components case-insensitively.
    func testPathContainmentIsCaseInsensitiveLikeScanPolicy() {
        let finding = makeFinding(path: "/Users/k/Library/Caches/Build")
        let result = DiskReviewResolver.resolve(
            entryPath: "/Users/k/Library/Caches/build/item",
            findings: [finding]
        )
        guard case .insideFinding(let matched) = result else {
            return XCTFail("expected .insideFinding, got \(result)")
        }
        XCTAssertEqual(matched.path, finding.path)
    }

    func testPrivateAliasSpellingsResolveBothWays() {
        let cases: [(name: String, findingPath: String, entryPath: String)] = [
            ("finding under /var, entry under /private/var", "/var/folders/ab/T/cache", "/private/var/folders/ab/T/cache"),
            ("finding under /private/var, entry under /var", "/private/var/folders/ab/T/cache", "/var/folders/ab/T/cache"),
            ("finding under /tmp, entry under /private/tmp", "/tmp/build-cache", "/private/tmp/build-cache"),
        ]
        for testCase in cases {
            let finding = makeFinding(path: testCase.findingPath)
            let result = DiskReviewResolver.resolve(entryPath: testCase.entryPath, findings: [finding])
            guard case .covered(let findings) = result else {
                XCTFail("\(testCase.name): expected .covered, got \(result)")
                continue
            }
            XCTAssertEqual(findings.map(\.path), [finding.path], testCase.name)
        }
    }

    func testSiblingPrefixNeverMatches() {
        let cases: [(name: String, findingPath: String, entryPath: String)] = [
            ("uvicorn is not uv", "/a/uvicorn", "/a/uv"),
            ("uv is not inside uvicorn", "/a/uv", "/a/uvicorn"),
            ("var alias sibling", "/private/variable/x", "/var"),
        ]
        for testCase in cases {
            let finding = makeFinding(path: testCase.findingPath)
            let result = DiskReviewResolver.resolve(entryPath: testCase.entryPath, findings: [finding])
            guard case .notCandidate = result else {
                XCTFail("\(testCase.name): expected .notCandidate, got \(result)")
                continue
            }
        }
    }

    func testUvBackupSiblingDoesNotMatchUv() {
        let finding = makeFinding(path: "/Users/k/.cache/uv-backup")

        let result = DiskReviewResolver.resolve(entryPath: "/Users/k/.cache/uv", findings: [finding])

        guard case .notCandidate = result else {
            return XCTFail("expected .notCandidate, got \(result)")
        }
    }

    func testAdvancedFindingIsExcludedEvenOnExactMatch() {
        let finding = makeFinding(path: "/Users/k/Library/Caches/foo", riskLevel: .advanced)

        let result = DiskReviewResolver.resolve(entryPath: "/Users/k/Library/Caches/foo", findings: [finding])

        guard case .notCandidate = result else {
            return XCTFail("expected .notCandidate, got \(result)")
        }
    }

    func testAdvancedFindingNeverAppearsInCoveredList() {
        let advanced = makeFinding(path: "/Users/k/Library/Caches/foo", riskLevel: .advanced)
        let safe = makeFinding(path: "/Users/k/Library/Caches/foo/sub", riskLevel: .safe)

        let result = DiskReviewResolver.resolve(entryPath: "/Users/k/Library/Caches/foo", findings: [advanced, safe])

        guard case .covered(let findings) = result else {
            return XCTFail("expected .covered, got \(result)")
        }
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings.allSatisfy { $0.riskLevel != .advanced })
    }

    func testUnrelatedPathIsNotCandidate() {
        let finding = makeFinding(path: "/Users/k/Downloads/thing")

        let result = DiskReviewResolver.resolve(entryPath: "/Users/k/Desktop", findings: [finding])

        guard case .notCandidate = result else {
            return XCTFail("expected .notCandidate, got \(result)")
        }
    }
}
