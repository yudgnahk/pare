import XCTest
@testable import PareCore

final class FolderRollupAggregateTests: XCTestCase {

    private struct Group {
        var bytes: Int64 = 0
        var reviewCount = 0
        var paths: [String] = []
    }

    /// Pins buildAggregate against an independent grouping so the accumulation loop can change safely.
    func testBuildAggregateMatchesReferenceGrouping() {
        let findings = mixedFindings()
        let aggregate = FolderRollup.buildAggregate(from: findings)

        var reference: [ScanCategory: [String: Group]] = [:]
        for f in findings where f.riskLevel != .advanced {
            let folder = FolderRollup.rollupFolderPath(for: f.path)
            var group = reference[f.category, default: [:]][folder] ?? Group()
            group.bytes += f.sizeBytes
            group.reviewCount += f.riskLevel == .review ? 1 : 0
            group.paths.append(f.path)
            reference[f.category, default: [:]][folder] = group
        }

        XCTAssertEqual(Set(aggregate.rowsByCategory.keys), Set(reference.keys))
        for (category, folders) in reference {
            let rows = aggregate.rowsByCategory[category] ?? []
            XCTAssertEqual(rows.map(\.totalBytes), rows.map(\.totalBytes).sorted(by: >))
            XCTAssertEqual(Set(rows.map(\.folderPath)), Set(folders.keys))
            for row in rows {
                let group = folders[row.folderPath]
                XCTAssertEqual(row.id, "\(category.rawValue)|\(row.folderPath)")
                XCTAssertEqual(row.totalBytes, group?.bytes)
                XCTAssertEqual(row.itemCount, group?.paths.count)
                XCTAssertEqual(row.riskLevel, (group?.reviewCount ?? 0) > 0 ? .review : .safe)
                XCTAssertEqual(row.toolName, ScanReportAnnotator.sourceApp(forPath: row.folderPath))
                XCTAssertEqual(aggregate.pathsByFolderId[row.id], group?.paths)
                XCTAssertEqual(
                    aggregate.metaByFolderId[row.id],
                    FolderMeta(
                        itemCount: group?.paths.count ?? 0,
                        bytes: group?.bytes ?? 0,
                        reviewCount: group?.reviewCount ?? 0,
                        isSafe: group?.reviewCount == 0
                    )
                )
                XCTAssertEqual(aggregate.safeFolderIds.contains(row.id), group?.reviewCount == 0)
            }
        }
    }

    func testBuildAggregateKeepsEveryFindingPathAndSkipsAdvanced() {
        let findings = mixedFindings()
        let aggregate = FolderRollup.buildAggregate(from: findings)

        let reclaimable = findings.filter { $0.riskLevel != .advanced }
        XCTAssertEqual(aggregate.folderIdByPath.count, reclaimable.count)
        XCTAssertEqual(aggregate.pathsByFolderId.values.reduce(0) { $0 + $1.count }, reclaimable.count)
        for f in findings where f.riskLevel == .advanced {
            XCTAssertNil(aggregate.folderIdByPath[f.path])
        }
        XCTAssertGreaterThan(aggregate.rowsByCategory[.browserCaches]?.count ?? 0, 1)
    }

    func testBuildAggregateLargeFolderCountsAndBytes() {
        let aggregate = FolderRollup.buildAggregate(from: mixedFindings())
        let big = aggregate.rowsByCategory[.browserCaches]?.first
        XCTAssertEqual(big?.itemCount, 500)
        XCTAssertEqual(big?.totalBytes, (1...500).reduce(Int64(0)) { $0 + Int64($1) * 10 })
    }

    // MARK: - Helpers

    private func mixedFindings() -> [ScanFinding] {
        var findings: [ScanFinding] = (1...500).map {
            finding(.browserCaches, .safe, "/Users/u/Library/Caches/Google/Chrome/Default/Cache/f_\($0)", Int64($0) * 10)
        }
        findings += (1...30).map {
            finding(.browserCaches, $0 % 7 == 0 ? .review : .safe, "/Users/u/Library/Caches/Mozilla/Firefox/cache2/e_\($0)", Int64($0) * 3)
        }
        findings += (1...40).map {
            finding(.userCaches, .safe, "/Users/u/Library/Caches/com.example.Widget/blob_\($0)", Int64($0) * 7 + 1)
        }
        findings += [
            finding(.userCaches, .review, "/Users/u/Library/Caches/com.acme.Tool/data.bin", 9_000),
            finding(.projectArtifacts, .safe, "/Users/u/dev/app-a/.next", 123_456),
            finding(.projectArtifacts, .review, "/Users/u/dev/app-b/node_modules", 654_321),
            finding(.userCaches, .advanced, "/Users/u/Library/Caches/Docker/Docker.raw", 99_999_999),
        ]
        return findings
    }

    private func finding(_ category: ScanCategory, _ risk: RiskLevel, _ path: String, _ size: Int64) -> ScanFinding {
        ScanFinding(category: category, riskLevel: risk, reason: "test", path: path, sizeBytes: size, lastUsed: nil, confidence: 1)
    }
}
