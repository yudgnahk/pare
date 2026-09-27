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
