import XCTest
@testable import PareCore

final class CleanCategoryTests: XCTestCase {

    private let other = FolderOwner.other

    /// Every scan category with an unknown owner, Safe and Review: a new case fails here until someone places it.
    private let byCategory: [ScanCategory: (safe: CleanCategory?, review: CleanCategory?)] = [
        .userCaches: (.appCaches, .appCaches),
        .temporaryFiles: (.oldVersions, .oldVersions),
        .logsAndCrashReports: (.appCaches, .appCaches),
        .browserCaches: (.appCaches, .siteData),
        .developerBuildArtifacts: (.developerTools, .developerTools),
        .developerPackageCaches: (.developerTools, .developerTools),
        .developerSimulatorCaches: (.developerTools, .developerTools),
        .designerCaches: (.appCaches, .appCaches),
        .videoBuilderCaches: (.appCaches, .appCaches),
        .aiToolCaches: (.aiTools, .aiTools),
        .installerFiles: (.oldVersions, .oldVersions),
        .applications: (.oldVersions, .oldVersions),
        .projectArtifacts: (.developerTools, .developerTools),
        .deviceBackups: (.oldVersions, .oldVersions),
        .productivityCaches: (.appCaches, .appCaches),
        .launchAgents: (.oldVersions, .oldVersions),
        .diagnostics: (nil, nil),
    ]

    private func classify(_ category: ScanCategory, _ risk: RiskLevel, _ owner: FolderOwner) -> CleanCategory? {
        CleanCategory.classify(category: category, risk: risk, owner: owner)
    }

    private func knownOwner(_ id: String) throws -> FolderOwner {
        try XCTUnwrap(KnownOwners.all.first { $0.id == id }, id).owner
    }

    func testTableCoversEveryCategory() {
        XCTAssertEqual(Set(byCategory.keys), Set(ScanCategory.allCases))
    }

    func testEveryCategoryAndRiskWithAnUnknownOwner() {
        for category in ScanCategory.allCases {
            let expected = byCategory[category]
            XCTAssertEqual(classify(category, .safe, other), expected?.safe, "\(category.rawValue) safe")
            XCTAssertEqual(classify(category, .review, other), expected?.review, "\(category.rawValue) review")
            XCTAssertEqual(
                classify(category, .advanced, other), category == .diagnostics ? nil : .sizeOnly, "\(category.rawValue) advanced"
            )
        }
    }

    func testOwnerDrivenCategories() throws {
        let slack = try knownOwner("slack")
        let openCode = try knownOwner("opencode")
        let chrome = try knownOwner("chrome")
        let npm = try knownOwner("npm")
        let project = FolderOwner.project(ProjectRef(root: "/Users/u/Code/shop", name: "shop"))

        XCTAssertEqual(classify(.userCaches, .safe, slack), .communication)
        XCTAssertEqual(classify(.userCaches, .safe, openCode), .aiTools)
        XCTAssertEqual(classify(.userCaches, .safe, .macOS), .system)
        XCTAssertEqual(classify(.logsAndCrashReports, .safe, .macOS), .system)
        XCTAssertEqual(classify(.temporaryFiles, .safe, .macOS), .system)
        XCTAssertEqual(classify(.userCaches, .safe, npm), .developerTools)
        XCTAssertEqual(classify(.projectArtifacts, .safe, project), .projects)
        XCTAssertEqual(classify(.projectArtifacts, .review, project), .projects)
        XCTAssertEqual(classify(.projectArtifacts, .advanced, project), .sizeOnly)
        XCTAssertEqual(classify(.browserCaches, .safe, chrome), .appCaches)
        XCTAssertEqual(classify(.browserCaches, .review, chrome), .siteData)
        XCTAssertEqual(classify(.browserCaches, .review, slack), .siteData)
        XCTAssertEqual(classify(.installerFiles, .review, slack), .oldVersions)
        XCTAssertEqual(classify(.logsAndCrashReports, .safe, chrome), .appCaches)
    }

    func testTraitsLiveInTheKnownOwnersData() throws {
        for id in ["slack", "teams", "zoom", "discord", "telegram", "whatsapp", "signal", "messages", "skype", "webex"] {
            XCTAssertEqual(try knownOwner(id).traits, [.communication], id)
        }
        for id in ["claude", "chatgpt", "codex", "opencode", "cursor"] {
            XCTAssertEqual(try knownOwner(id).traits, [.ai], id)
        }
        XCTAssertEqual(try knownOwner("chrome").traits, [])
        XCTAssertEqual(try knownOwner("spotify").traits, [])
    }

    func testResolvedBundleOwnerCarriesItsTrait() {
        let resolver = OwnerResolver(
            homeDirectory: URL(fileURLWithPath: "/Users/u"), installedApps: .empty, catalog: AppCatalog(version: 1, entries: [])
        )

        let slack = resolver.owner(forFolderPath: "/Users/u/Library/Caches/com.tinyspeck.slackmacgap")

        XCTAssertEqual(slack.displayName, "Slack")
        XCTAssertTrue(slack.traits.contains(.communication))
    }

    func testOrderAndSelectability() {
        XCTAssertEqual(
            CleanCategory.allCases.sorted(),
            [.appCaches, .communication, .developerTools, .projects, .aiTools, .siteData, .oldVersions, .system, .sizeOnly]
        )
        XCTAssertEqual(CleanCategory.allCases.filter { !$0.isSelectable }, [.sizeOnly])
    }
}

final class CleanListingTests: XCTestCase {

    private let threshold = CleanListing.smallRowMaxBytes

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

    private func sections(_ findings: [ScanFinding], cap: Int = CleanListing.defaultMaxRowsShown) -> [CleanSection] {
        let aggregate = FolderRollup.buildAggregate(from: findings)
        let records = Array(aggregate.recordsByFolderId.values) + CleanListing.sizeOnlyRecords(from: findings)
        return CleanListing.sections(rows: CleanListing.rows(records: records, owners: [:]), maxRowsShown: cap)
    }

    private func section(_ group: CleanCategory, in sections: [CleanSection]) throws -> CleanSection {
        try XCTUnwrap(sections.first { $0.group == group }, "\(group)")
    }

    func testCategoriesAppearInOrderAndEmptyOnesAreLeftOut() {
        XCTAssertEqual(sections(findings).map(\.group), [.appCaches, .developerTools, .siteData, .sizeOnly])
        XCTAssertEqual(sections([findings[3]]).map(\.group), [.developerTools])
    }

    func testFoldThresholdIsExclusive() throws {
        let rebuilds = try section(.appCaches, in: sections(findings))

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

    func testSafeIdsAreSafeAndReviewOnlyCategoryHasNone() throws {
        let all = sections(findings)
        let aggregate = FolderRollup.buildAggregate(from: findings)

        XCTAssertEqual(all.reduce(into: Set<String>()) { $0.formUnion($1.safeFolderIds) }, aggregate.safeFolderIds)
        XCTAssertTrue(try section(.siteData, in: all).safeFolderIds.isEmpty)
        XCTAssertFalse(try section(.siteData, in: all).isSelectable)
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
        let slower = try section(.developerTools, in: sections(big + small, cap: 2))

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
        let slower = try section(.developerTools, in: sections(findings))

        XCTAssertTrue(slower.hasPartialSize)
        XCTAssertTrue(slower.smallHasPartialSize)
    }

    func testRowsKeepTheirOwnerAndProjectRelativePath() throws {
        let aggregate = FolderRollup.buildAggregate(from: [finding(.projectArtifacts, .safe, "/Users/u/Code/a/apps/web/.next", 1)])
        let record = try XCTUnwrap(aggregate.recordsByFolderId.values.first)
        let project = FolderOwner.project(ProjectRef(root: "/Users/u/Code/a", name: "a"))

        let rows = CleanListing.rows(records: [record], owners: [record.id: project])

        XCTAssertEqual(rows.first?.owner, project)
        XCTAssertEqual(rows.first?.projectRelativePath, "apps/web/.next")
        XCTAssertNil(CleanListing.rows(records: [record], owners: [:]).first?.projectRelativePath)
        XCTAssertEqual(CleanListing.rows(records: [record], owners: [:]).first?.owner, .other)
    }
}
