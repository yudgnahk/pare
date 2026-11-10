import XCTest
@testable import PareCore

final class ConsequenceGroupTests: XCTestCase {

    /// Every category, spelled out: a new case fails here until someone decides its group.
    private let developerWork: [ScanCategory: Bool] = [
        .userCaches: false, .temporaryFiles: false, .logsAndCrashReports: false, .browserCaches: false,
        .developerBuildArtifacts: true, .developerPackageCaches: true, .developerSimulatorCaches: true,
        .designerCaches: false, .videoBuilderCaches: false, .aiToolCaches: false, .installerFiles: false,
        .applications: false, .projectArtifacts: true, .deviceBackups: false, .productivityCaches: false,
        .launchAgents: false, .diagnostics: false,
    ]

    func testTableCoversEveryCategory() {
        XCTAssertEqual(Set(developerWork.keys), Set(ScanCategory.allCases))
    }

    func testSafeRowsSplitByDeveloperWork() {
        for category in ScanCategory.allCases where category != .diagnostics {
            let expected: ConsequenceGroup = developerWork[category] == true ? .slowerNextBuild : .rebuildsItself
            XCTAssertEqual(category.isDeveloperWork, developerWork[category], category.rawValue)
            XCTAssertEqual(ConsequenceGroup.of(category: category, risk: .safe), expected, category.rawValue)
        }
    }

    func testReviewAndAdvancedIgnoreTheCategory() {
        for category in ScanCategory.allCases where category != .diagnostics {
            XCTAssertEqual(ConsequenceGroup.of(category: category, risk: .review), .needsALook, category.rawValue)
            XCTAssertEqual(ConsequenceGroup.of(category: category, risk: .advanced), .sizeOnly, category.rawValue)
        }
    }

    func testDiagnosticsHaveNoGroup() {
        for risk in [RiskLevel.safe, .review, .advanced] {
            XCTAssertNil(ConsequenceGroup.of(category: .diagnostics, risk: risk))
        }
    }

    func testOrderAndSelectability() {
        XCTAssertEqual(ConsequenceGroup.allCases.sorted(), [.rebuildsItself, .slowerNextBuild, .needsALook, .sizeOnly])
        XCTAssertEqual(ConsequenceGroup.allCases.filter(\.isSelectable), [.rebuildsItself, .slowerNextBuild, .needsALook])
    }
}

final class ConsequenceListingTests: XCTestCase {

    private let threshold = ConsequenceListing.smallRowMaxBytes

    private func finding(
        _ category: ScanCategory, _ risk: RiskLevel, _ path: String, _ size: Int64, complete: Bool = true
    ) -> ScanFinding {
        ScanFinding(
            category: category, riskLevel: risk, reason: "test", path: path, sizeBytes: size,
            lastUsed: nil, confidence: 1, isSizeComplete: complete
        )
    }

    private var findings: [ScanFinding] {
        [
            finding(.browserCaches, .safe, "/Users/u/Library/Caches/Google/Chrome/Default/Cache/f1", threshold),
            finding(.browserCaches, .review, "/Users/u/Library/Application Support/Google/Chrome/Default/History", 3 * threshold),
            finding(.userCaches, .safe, "/Users/u/Library/Caches/com.acme.small/x", threshold - 1),
            finding(.developerPackageCaches, .safe, "/Users/u/.npm/_cacache/x", 2 * threshold),
            finding(.projectArtifacts, .safe, "/Users/u/Code/a/.next", 10, complete: false),
            finding(.developerPackageCaches, .advanced, "/Users/u/go/pkg/mod/x", 9 * threshold),
            finding(.diagnostics, .advanced, "/private/var/vm", 999),
        ]
    }

    private func sections(_ findings: [ScanFinding], cap: Int = ConsequenceListing.defaultMaxRowsShown) -> [ConsequenceSection] {
        let aggregate = FolderRollup.buildAggregate(from: findings)
        let records = Array(aggregate.recordsByFolderId.values) + ConsequenceListing.sizeOnlyRecords(from: findings)
        return ConsequenceListing.sections(rows: ConsequenceListing.rows(records: records, owners: [:]), maxRowsShown: cap)
    }

    private func section(_ group: ConsequenceGroup, in sections: [ConsequenceSection]) throws -> ConsequenceSection {
        try XCTUnwrap(sections.first { $0.group == group }, "\(group)")
    }

    func testGroupsAppearInOrderAndEmptyOnesAreLeftOut() {
        XCTAssertEqual(sections(findings).map(\.group), [.rebuildsItself, .slowerNextBuild, .needsALook, .sizeOnly])
        XCTAssertEqual(sections([findings[3]]).map(\.group), [.slowerNextBuild])
    }

    func testFoldThresholdIsExclusive() throws {
        let rebuilds = try section(.rebuildsItself, in: sections(findings))

        XCTAssertEqual(rebuilds.rows.map(\.record.bytes), [threshold])
        XCTAssertEqual(rebuilds.smallRows.map(\.record.bytes), [threshold - 1])
        XCTAssertEqual(rebuilds.smallBytes, threshold - 1)
        XCTAssertEqual(rebuilds.totalBytes, 2 * threshold - 1)
        XCTAssertEqual(rebuilds.smallSafeFolderIds, Set(rebuilds.smallRows.map(\.id)))
        XCTAssertEqual(threshold, 50_000_000)
    }

    func testEverySelectableFolderIsInExactlyOneSection() {
        let aggregate = FolderRollup.buildAggregate(from: findings)
        let ids = sections(findings).flatMap(\.folderIds)

        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(Set(ids), Set(aggregate.recordsByFolderId.keys))
    }

    func testSafeIdsAreSafeAndReviewGroupHasNone() throws {
        let all = sections(findings)
        let aggregate = FolderRollup.buildAggregate(from: findings)

        XCTAssertEqual(all.reduce(into: Set<String>()) { $0.formUnion($1.safeFolderIds) }, aggregate.safeFolderIds)
        XCTAssertTrue(try section(.needsALook, in: all).safeFolderIds.isEmpty)
        XCTAssertFalse(try section(.needsALook, in: all).isSelectable)
        for section in all {
            XCTAssertTrue(section.safeFolderIds.isSubset(of: section.folderIds))
            XCTAssertTrue(section.smallSafeFolderIds.isSubset(of: section.safeFolderIds))
        }
    }

    func testSizeOnlyRowsAreDisplayOnlyAndNeverDiagnostics() throws {
        let sizeOnly = try section(.sizeOnly, in: sections(findings))
        let aggregate = FolderRollup.buildAggregate(from: findings)

        XCTAssertEqual(sizeOnly.rows.map(\.record.folderPath), ["/Users/u/go/pkg/mod/x"])
        XCTAssertEqual(sizeOnly.totalBytes, 9 * threshold)
        XCTAssertTrue(sizeOnly.folderIds.isEmpty)
        XCTAssertFalse(sizeOnly.isSelectable)
        XCTAssertFalse(sizeOnly.rows.contains { $0.isSelectable })
        XCTAssertNil(aggregate.metaByFolderId[sizeOnly.rows[0].id])
        XCTAssertFalse(sections(findings).flatMap { $0.rows + $0.smallRows }.contains { $0.record.category == .diagnostics })
    }

    func testTotalsCoverHiddenAndFoldedRows() throws {
        let big = (1...5).map { finding(.projectArtifacts, .safe, "/Users/u/Code/p\($0)/.next", threshold + Int64($0)) }
        let small = (1...4).map { finding(.projectArtifacts, .safe, "/Users/u/Code/s\($0)/dist", Int64($0)) }
        let slower = try section(.slowerNextBuild, in: sections(big + small, cap: 2))

        XCTAssertEqual(slower.rows.count, 2)
        XCTAssertEqual(slower.hiddenRowCount, 3)
        XCTAssertEqual(slower.smallRows.count, 2)
        XCTAssertEqual(slower.hiddenSmallRowCount, 2)
        XCTAssertEqual(slower.smallRowCount, 4)
        XCTAssertEqual(slower.folderIds.count, 9)
        XCTAssertEqual(slower.totalBytes, (big + small).reduce(Int64(0)) { $0 + $1.sizeBytes })
        XCTAssertEqual(slower.smallBytes, 10)
        XCTAssertEqual(slower.rows.map(\.record.bytes), slower.rows.map(\.record.bytes).sorted(by: >))
    }

    func testPartialMemberMarksItsSectionAndFold() throws {
        let slower = try section(.slowerNextBuild, in: sections(findings))

        XCTAssertTrue(slower.hasPartialSize)
        XCTAssertTrue(slower.smallHasPartialSize)
    }

    func testRowsKeepTheirOwnerAndProjectRelativePath() throws {
        let aggregate = FolderRollup.buildAggregate(from: [finding(.projectArtifacts, .safe, "/Users/u/Code/a/apps/web/.next", 1)])
        let record = try XCTUnwrap(aggregate.recordsByFolderId.values.first)
        let project = FolderOwner.project(ProjectRef(root: "/Users/u/Code/a", name: "a"))

        let rows = ConsequenceListing.rows(records: [record], owners: [record.id: project])

        XCTAssertEqual(rows.first?.owner, project)
        XCTAssertEqual(rows.first?.projectRelativePath, "apps/web/.next")
        XCTAssertNil(ConsequenceListing.rows(records: [record], owners: [:]).first?.projectRelativePath)
        XCTAssertEqual(ConsequenceListing.rows(records: [record], owners: [:]).first?.owner, .other)
    }
}
