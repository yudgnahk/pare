import XCTest
@testable import PareCore

final class OwnerGroupingTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/u")

    private func resolver() -> OwnerResolver {
        OwnerResolver(homeDirectory: home, installedApps: .empty, catalog: AppCatalog(version: 1, entries: []))
    }

    private func finding(
        _ category: ScanCategory, _ risk: RiskLevel, _ path: String, _ size: Int64 = 10, complete: Bool = true
    ) -> ScanFinding {
        ScanFinding(
            category: category, riskLevel: risk, reason: "test", path: path, sizeBytes: size,
            lastUsed: nil, confidence: 1, isSizeComplete: complete
        )
    }

    private func mixed() -> [ScanFinding] {
        var f: [ScanFinding] = (1...5).map {
            finding(.browserCaches, .safe, "/Users/u/Library/Caches/Google/Chrome/Default/Cache/f_\($0)", Int64($0))
        }
        f += [
            finding(.browserCaches, .review, "/Users/u/Library/Application Support/Google/Chrome/Default/History", 50),
            finding(.projectArtifacts, .safe, "/Users/u/Code/a/.next", 100),
            finding(.projectArtifacts, .review, "/Users/u/Code/b/dist", 200),
            finding(.developerPackageCaches, .safe, "/Users/u/.npm/_cacache/x", 300),
            finding(.developerPackageCaches, .review, "/Users/u/.cargo/registry/x", 400),
            finding(.logsAndCrashReports, .safe, "/Users/u/Library/Logs/DiagnosticReports/a.ips", 5),
            finding(.userCaches, .review, "/Users/u/Library/Caches/com.acme.W/data", 7),
            finding(.diagnostics, .advanced, "/private/var/vm", 0),
            finding(.userCaches, .advanced, "/Users/u/Library/Caches/Docker/Docker.raw", 9_999),
        ]
        return f
    }

    private func groups(_ sections: [OwnerSection]) -> [OwnerGroup] { sections.flatMap(\.groups) }

    func testEveryFolderLandsInExactlyOneGroup() {
        let aggregate = FolderRollup.buildAggregate(from: mixed())
        let result = OwnerGrouping.build(aggregate: aggregate, resolver: resolver())
        let all = groups(result.sections)

        let idCount = all.reduce(0) { $0 + $1.folderIds.count }
        XCTAssertEqual(idCount, aggregate.metaByFolderId.count)
        XCTAssertEqual(all.reduce(into: Set<String>()) { $0.formUnion($1.folderIds) }, Set(aggregate.metaByFolderId.keys))
        XCTAssertEqual(Set(result.ownerByFolderId.keys), Set(aggregate.metaByFolderId.keys))
        XCTAssertEqual(
            all.reduce(Int64(0)) { $0 + $1.totalBytes },
            aggregate.metaByFolderId.values.reduce(Int64(0)) { $0 + $1.bytes }
        )
    }

    func testAdvancedAndDiagnosticsAreInNoGroup() {
        let aggregate = FolderRollup.buildAggregate(from: mixed())
        let all = groups(OwnerGrouping.build(aggregate: aggregate, resolver: resolver()).sections)
        let paths = Set(all.flatMap { $0.rows.map(\.row.folderPath) })
        XCTAssertFalse(paths.contains { $0.contains("Docker.raw") || $0 == "/private/var/vm" })
    }

    func testSectionsFollowKindOrderAndSumTheirGroups() {
        let sections = OwnerGrouping.build(aggregate: FolderRollup.buildAggregate(from: mixed()), resolver: resolver()).sections
        XCTAssertEqual(sections.map(\.kind), sections.map(\.kind).sorted())
        for section in sections {
            XCTAssertEqual(section.totalBytes, section.groups.reduce(0) { $0 + $1.totalBytes })
            XCTAssertTrue(section.groups.allSatisfy { $0.owner.kind == section.kind })
        }
        XCTAssertTrue(sections.map(\.kind).contains(.macOS))
    }

    func testRowsAreCappedAndTotalsCoverHiddenFolders() throws {
        let findings = (1...130).map {
            finding(.projectArtifacts, .safe, "/Users/u/Library/Application Support/Code/ws\($0)/.next", Int64($0))
        }
        let aggregate = FolderRollup.buildAggregate(from: findings)
        XCTAssertEqual(aggregate.recordsByFolderId.count, 130)

        let sections = OwnerGrouping.build(aggregate: aggregate, resolver: resolver()).sections
        let group = try XCTUnwrap(sections.first?.groups.first)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(group.rows.count, 50)
        XCTAssertEqual(group.hiddenRowCount, 80)
        XCTAssertEqual(group.folderIds.count, 130)
        XCTAssertEqual(group.safeFolderIds.count, 130)
        XCTAssertEqual(group.totalBytes, (1...130).reduce(Int64(0)) { $0 + Int64($1) })
        XCTAssertEqual(group.rows.map(\.row.totalBytes), group.rows.map(\.row.totalBytes).sorted(by: >))
        XCTAssertFalse(group.hasPartialSize)
    }

    func testOnePartialMemberMarksGroupAndSection() throws {
        var findings = (1...3).map {
            finding(.projectArtifacts, .safe, "/Users/u/Library/Application Support/Code/ws\($0)/.next", 5)
        }
        findings.append(finding(.projectArtifacts, .safe, "/Users/u/Library/Application Support/Code/ws9/.next", 5, complete: false))
        let sections = OwnerGrouping.build(aggregate: FolderRollup.buildAggregate(from: findings), resolver: resolver()).sections
        XCTAssertTrue(try XCTUnwrap(sections.first?.groups.first).hasPartialSize)
        XCTAssertTrue(try XCTUnwrap(sections.first).hasPartialSize)
    }

    func testSelectionNeverExceedsTheAggregateSafeSet() {
        let aggregate = FolderRollup.buildAggregate(from: mixed())
        let all = groups(OwnerGrouping.build(aggregate: aggregate, resolver: resolver()).sections)

        XCTAssertEqual(all.reduce(into: Set<String>()) { $0.formUnion($1.safeFolderIds) }, aggregate.safeFolderIds)
        for group in all {
            XCTAssertTrue(group.safeFolderIds.isSubset(of: group.folderIds))
            XCTAssertTrue(group.safeFolderIds.allSatisfy { aggregate.metaByFolderId[$0]?.isSafe == true })
        }
    }

    func testReviewOnlyGroupIsNotSelectable() throws {
        let findings = [finding(.developerPackageCaches, .review, "/Users/u/.cargo/registry/x", 10)]
        let sections = OwnerGrouping.build(aggregate: FolderRollup.buildAggregate(from: findings), resolver: resolver()).sections
        let group = try XCTUnwrap(sections.first?.groups.first)
        XCTAssertTrue(group.safeFolderIds.isEmpty)
        XCTAssertFalse(group.isSelectable)
        XCTAssertEqual(group.folderIds.count, 1)
    }

    func testRecordsCoverEveryFolderIncludingHiddenOnes() throws {
        let aggregate = FolderRollup.buildAggregate(from: mixed(), maxRowsPerCategory: 1)
        XCTAssertEqual(Set(aggregate.recordsByFolderId.keys), Set(aggregate.metaByFolderId.keys))
        for (id, record) in aggregate.recordsByFolderId {
            let meta = try XCTUnwrap(aggregate.metaByFolderId[id])
            XCTAssertEqual(record.bytes, meta.bytes)
            XCTAssertEqual(record.itemCount, meta.itemCount)
            XCTAssertEqual(record.riskLevel == .safe, meta.isSafe)
            XCTAssertEqual(id, "\(record.category.rawValue)|\(record.folderPath)")
        }
    }

    // MARK: - Performance

    func testResolvesOncePerFolderAndCachesBundleLookups() {
        let bundleIDs = (0..<20).map { "com.vendor.app\($0)" }
        let findings = (0..<40_000).map { i -> ScanFinding in
            let folder = i % 2_000
            let id = bundleIDs[folder % bundleIDs.count]
            return finding(.userCaches, .safe, "/Users/u/Library/Caches/\(id)/folder\(folder)/blob\(i)", 1)
        }
        let aggregate = FolderRollup.buildAggregate(from: findings)
        XCTAssertEqual(aggregate.recordsByFolderId.count, 20)

        let locator = CountingLocator(known: [:])
        let inner = OwnerResolver(
            homeDirectory: home,
            installedApps: InstalledAppIndex(namesByBundleID: [:], fallbackLocator: locator),
            catalog: AppCatalog(version: 1, entries: [])
        )
        let counting = CountingResolver(inner: inner)

        _ = OwnerGrouping.build(aggregate: aggregate, resolver: counting)
        XCTAssertEqual(counting.calls, aggregate.recordsByFolderId.count)
        XCTAssertLessThanOrEqual(locator.calls, bundleIDs.count)

        let before = locator.calls
        _ = OwnerGrouping.build(aggregate: aggregate, resolver: inner)
        XCTAssertEqual(locator.calls, before)
    }

    func testTwoThousandFoldersCostTwoThousandResolverCalls() {
        let findings = (0..<40_000).map {
            finding(.projectArtifacts, .safe, "/Users/u/Code/p\($0 % 2_000)/.next/chunk\($0)", 1)
        }
        let aggregate = FolderRollup.buildAggregate(from: findings)
        XCTAssertEqual(aggregate.recordsByFolderId.count, 2_000)

        let counting = CountingResolver(inner: resolver())
        _ = OwnerGrouping.build(aggregate: aggregate, resolver: counting)
        XCTAssertEqual(counting.calls, 2_000)
    }
}

private final class CountingResolver: OwnerResolving, @unchecked Sendable {
    private let lock = NSLock()
    private let inner: any OwnerResolving
    private var count = 0

    init(inner: any OwnerResolving) { self.inner = inner }

    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

    func owner(forFolderPath path: String) -> FolderOwner {
        lock.lock(); count += 1; lock.unlock()
        return inner.owner(forFolderPath: path)
    }
}
