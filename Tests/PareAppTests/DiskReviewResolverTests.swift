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

    /// On a case-insensitive volume, containment ignores case like `ScanPolicy.isEqualToOrDescendant`.
    func testPathContainmentIsCaseInsensitiveLikeScanPolicy() {
        let finding = makeFinding(path: "/Users/k/Library/Caches/Build")
        let result = DiskReviewResolver.resolve(
            entryPath: "/Users/k/Library/Caches/build/item",
            findings: [finding],
            isCaseSensitive: { _ in false }
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

    func testInsideFindingResolvesAcrossAliasAndDotSegmentSpellings() {
        let cases: [(name: String, findingPath: String, entryPath: String)] = [
            ("finding /var, entry /private/var", "/var/folders/ab/T/cache", "/private/var/folders/ab/T/cache/sub/file"),
            ("finding /private/var, entry /var", "/private/var/folders/ab/T/cache", "/var/folders/ab/T/cache/sub"),
            ("finding /private/tmp, entry /tmp with dot segments", "/private/tmp/build-cache", "/tmp/x/../build-cache/./obj"),
        ]
        for testCase in cases {
            let finding = makeFinding(path: testCase.findingPath)
            let result = DiskReviewResolver.resolve(entryPath: testCase.entryPath, findings: [finding])
            guard case .insideFinding(let matched) = result else {
                XCTFail("\(testCase.name): expected .insideFinding, got \(result)")
                continue
            }
            XCTAssertEqual(matched.path, finding.path, testCase.name)
        }
    }

    /// Raw component counts tie (6 vs 6) and `max` keeps the first on ties, so only canonical depth picks `inner`.
    func testNearestFindingUsesCanonicalDepthAcrossAliasSpellings() {
        let inner = makeFinding(path: "/var/folders/ab/T/cache")
        let outer = makeFinding(path: "/private/var/folders/ab/T")

        let result = DiskReviewResolver.resolve(entryPath: "/var/folders/ab/T/cache/sub", findings: [outer, inner])

        guard case .insideFinding(let matched) = result else {
            return XCTFail("expected .insideFinding, got \(result)")
        }
        XCTAssertEqual(matched.path, inner.path)
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
    // MARK: - Volume case sensitivity

    private let lowerFinding = "/Users/k/Library/Caches/com.foo"

    private func resolve(_ entryPath: String, caseSensitive: Bool) -> DiskReviewResolution {
        DiskReviewResolver.resolve(
            entryPath: entryPath,
            findings: [makeFinding(path: lowerFinding)],
            isCaseSensitive: { _ in caseSensitive }
        )
    }

    func testCaseSensitiveVolumeDoesNotMapSiblingWithDifferentCase() {
        guard case .notCandidate = resolve("/Users/k/Library/Caches/com.Foo", caseSensitive: true) else {
            return XCTFail("com.Foo must not resolve to com.foo on a case-sensitive volume")
        }
        guard case .notCandidate = resolve("/Users/k/Library/Caches/com.Foo/data.bin", caseSensitive: true) else {
            return XCTFail("a child of com.Foo must not be inside com.foo on a case-sensitive volume")
        }
        guard case .notCandidate = resolve("/Users/k/Library/caches", caseSensitive: true) else {
            return XCTFail("a differently cased ancestor must not cover com.foo on a case-sensitive volume")
        }
    }

    func testCaseSensitiveVolumeStillMatchesExactCase() {
        guard case .covered(let covered) = resolve(lowerFinding, caseSensitive: true) else {
            return XCTFail("exact-case entry must be covered")
        }
        XCTAssertEqual(covered.map(\.path), [lowerFinding])
        guard case .covered = resolve("/Users/k/Library/Caches", caseSensitive: true) else {
            return XCTFail("exact-case ancestor must cover the finding")
        }
        guard case .insideFinding(let container) = resolve(lowerFinding + "/data.bin", caseSensitive: true) else {
            return XCTFail("exact-case child must be inside the finding")
        }
        XCTAssertEqual(container.path, lowerFinding)
    }

    func testCaseInsensitiveVolumeMatchesAcrossCase() {
        guard case .covered(let covered) = resolve("/Users/k/Library/Caches/com.Foo", caseSensitive: false) else {
            return XCTFail("com.Foo is the same item as com.foo on a case-insensitive volume")
        }
        XCTAssertEqual(covered.map(\.path), [lowerFinding])
        guard case .covered = resolve("/Users/k/Library/caches", caseSensitive: false) else {
            return XCTFail("differently cased ancestor must cover on a case-insensitive volume")
        }
        guard case .insideFinding(let container) = resolve("/Users/k/Library/Caches/COM.FOO/data.bin", caseSensitive: false) else {
            return XCTFail("differently cased child must be inside the finding on a case-insensitive volume")
        }
        XCTAssertEqual(container.path, lowerFinding)
        guard case .notCandidate = resolve("/Users/k/Library/Caches/com.foobar", caseSensitive: false) else {
            return XCTFail("component matching must not treat com.foobar as com.foo")
        }
    }
}
