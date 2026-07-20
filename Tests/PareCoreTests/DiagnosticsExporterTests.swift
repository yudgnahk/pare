import XCTest
@testable import PareCore

final class DiagnosticsExporterTests: XCTestCase {
    private let home = "/Users/testuser"

    func testAnonymizeReplacesHomeWithTilde() {
        let path = "\(home)/Library/Caches/foo.db"
        XCTAssertEqual(
            DiagnosticsExporter.anonymizePath(path, homeDirectory: home),
            "~/Library/Caches/foo.db"
        )
    }

    func testAnonymizeOtherUsersHome() {
        let path = "/Users/alice/Library/Mail/V10"
        XCTAssertEqual(
            DiagnosticsExporter.anonymizePath(path, homeDirectory: home),
            "/Users/<user>/Library/Mail/V10"
        )
    }

    func testPathPrefixesCapDepthAndDedup() {
        let paths = [
            "\(home)/Library/Caches/a/b/c/d/file.bin",
            "\(home)/Library/Caches/a/b/other.bin",
            "\(home)/Library/Logs/app.log",
        ]
        let prefixes = DiagnosticsExporter.anonymizedPathPrefixes(
            from: paths,
            homeDirectory: home,
            maxDepth: 4,
            limit: 24
        )
        XCTAssertTrue(prefixes.contains("~/Library/Caches/a"))
        XCTAssertTrue(prefixes.contains("~/Library/Logs/app.log") || prefixes.contains("~/Library/Logs"))
        // No absolute home username leaked
        XCTAssertFalse(prefixes.joined().contains("testuser"))
    }

    func testMakeBundleFromReportOmitsAbsolutePathsInJSON() throws {
        let findings = [
            ScanFinding(
                category: .userCaches,
                riskLevel: .safe,
                reason: "cache",
                path: "\(home)/Library/Caches/com.example/data",
                sizeBytes: 1024,
                lastUsed: nil,
                confidence: 0.9
            ),
            ScanFinding(
                category: .browserCaches,
                riskLevel: .review,
                reason: "storage",
                path: "\(home)/Library/Application Support/Google/Chrome/Default/Local Storage",
                sizeBytes: 2048,
                lastUsed: nil,
                confidence: 0.8
            ),
            ScanFinding(
                category: .developerPackageCaches,
                riskLevel: .advanced,
                reason: "vm",
                path: "\(home)/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                sizeBytes: 9_000_000_000,
                lastUsed: nil,
                confidence: 0.99
            ),
        ]
        let summaries = [
            ScanCategorySummary(category: .userCaches, reclaimableBytes: 1024, fileCount: 1),
            ScanCategorySummary(category: .browserCaches, reclaimableBytes: 2048, fileCount: 1),
        ]
        let report = ScanReport(findings: findings, summaries: summaries)
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)

        let bundle = DiagnosticsExporter.makeBundle(
            report: report,
            profileUsed: "all",
            scanDate: fixed,
            scanDurationSeconds: 12.5,
            appVersion: "1.0 (1)",
            macOSVersion: "14.5.0",
            ruleIds: ["user-caches", "browser-caches"],
            homeDirectory: home,
            exportDate: fixed
        )

        XCTAssertEqual(bundle.schemaVersion, 1)
        XCTAssertEqual(bundle.findingCount, 3)
        XCTAssertEqual(bundle.totalReclaimableBytes, 1024 + 2048)
        XCTAssertEqual(bundle.riskCounts.safe, 1)
        XCTAssertEqual(bundle.riskCounts.review, 1)
        XCTAssertEqual(bundle.riskCounts.advanced, 1)
        XCTAssertEqual(bundle.categorySummaries.count, 2)
        XCTAssertEqual(bundle.ruleIds, ["user-caches", "browser-caches"])
        XCTAssertFalse(bundle.anonymizedPathPrefixes.isEmpty)
        XCTAssertFalse(bundle.anonymizedPathPrefixes.joined().contains("testuser"))

        let data = try DiagnosticsExporter.jsonData(from: bundle)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains(home), "JSON must not contain absolute home path")
        XCTAssertFalse(json.contains("testuser"))
        XCTAssertTrue(json.contains("User Caches") || json.contains("userCaches") || json.contains("\"category\""))
        XCTAssertTrue(json.contains("1.0 (1)"))
        XCTAssertTrue(json.contains("14.5.0"))

        // Round-trip
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticsBundle.self, from: data)
        XCTAssertEqual(decoded, bundle)
    }

    func testMakeBundleWithoutReportIsEmptyButValid() throws {
        let bundle = DiagnosticsExporter.makeBundle(
            report: nil,
            profileUsed: "all",
            appVersion: "1.0",
            macOSVersion: "15.0.0",
            ruleIds: ["user-caches"]
        )
        XCTAssertEqual(bundle.findingCount, 0)
        XCTAssertEqual(bundle.totalReclaimableBytes, 0)
        XCTAssertTrue(bundle.categorySummaries.isEmpty)
        XCTAssertEqual(bundle.riskCounts.total, 0)
        XCTAssertEqual(bundle.ruleIds, ["user-caches"])

        let data = try DiagnosticsExporter.jsonData(from: bundle)
        XCTAssertFalse(data.isEmpty)
    }

    func testCategoryInputOverload() {
        let bundle = DiagnosticsExporter.makeBundle(
            categorySummaries: [
                DiagnosticsCategorySummary(category: "User Caches", reclaimableBytes: 100, fileCount: 2),
            ],
            riskCounts: DiagnosticsRiskCounts(safe: 2, review: 0, advanced: 0),
            profileUsed: "baseline",
            totalReclaimableBytes: 100,
            findingCount: 2,
            scanDate: nil,
            scanDurationSeconds: nil,
            pathSamples: ["\(home)/Library/Caches/x"],
            appVersion: "1.0",
            macOSVersion: "14.0.0",
            ruleIds: ["user-caches"],
            homeDirectory: home
        )
        XCTAssertEqual(bundle.profileUsed, "baseline")
        XCTAssertEqual(bundle.categorySummaries.first?.fileCount, 2)
        XCTAssertTrue(bundle.anonymizedPathPrefixes.contains { $0.hasPrefix("~/Library") })
    }

    func testRuleIdsDefaultFromCatalog() {
        let bundle = DiagnosticsExporter.makeBundle(
            report: nil,
            profileUsed: "all",
            appVersion: "1.0",
            macOSVersion: "14.0.0"
        )
        XCTAssertEqual(bundle.ruleIds.count, RuleCatalog.all.count)
        XCTAssertEqual(bundle.ruleIds, bundle.ruleIds.sorted())
    }
}
