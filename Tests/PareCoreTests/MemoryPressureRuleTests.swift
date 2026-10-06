import XCTest
@testable import PareCore

/// Recent system-wide memory shortages, read from JetsamEvent reports and explained, never cleaned.
final class MemoryPressureRuleTests: XCTestCase {

    private var reports: URL!
    private static let now = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!
    private static let gigabyte: Int64 = 1024 * 1024 * 1024

    override func setUpWithError() throws {
        reports = FileManager.default.temporaryDirectory.appending(path: "pare_jetsam_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: reports)
    }

    // MARK: - Parsing

    func testParsesLargestProcessTopResidentAndKillReasons() throws {
        let event = try XCTUnwrap(MemoryPressureRule.event(fromReport: Self.report(
            date: "2026-10-06 21:01:25.66 +0700",
            largest: "Google Chrome",
            processes: [
                ("Google Chrome", 131_072, nil),
                ("Safari", 65_536, nil),
                ("node", 1_000, "vm-pageshortage"),
                ("mds", 10, nil),
            ]
        )))

        XCTAssertEqual(event.largestProcess, "Google Chrome")
        XCTAssertEqual(event.topProcesses.map(\.name), ["Google Chrome", "Safari", "node"])
        XCTAssertEqual(event.topProcesses.first?.residentBytes, 131_072 * 16_384)
        XCTAssertEqual(event.killReasons, ["vm-pageshortage"])
        XCTAssertTrue(event.isSystemMemoryShortage)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T14:01:25Z")).addingTimeInterval(0.66)
        XCTAssertEqual(try XCTUnwrap(event.date).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.01)
    }

    func testOnlySystemWideKillReasonsCountAsRunningOutOfMemory() throws {
        let cases: [(reasons: [String?], shortage: Bool)] = [
            (["per-process-limit"], false),
            (["per-process-limit", "per-process-limit"], false),
            (["idle-exit"], false),
            ([nil], false),
            (["vm-pageshortage"], true),
            (["per-process-limit", "fc-thrashing"], true),
            (["vm-compressor-space-shortage"], true),
            (["low-swap"], true),
            (["zone-map-exhaustion"], true),
            (["highwater"], true),
        ]
        for testCase in cases {
            let processes = testCase.reasons.enumerated().map { ("p\($0.offset)", 100, $0.element) }
            let event = try XCTUnwrap(MemoryPressureRule.event(fromReport: Self.report(processes: processes)))
            XCTAssertEqual(event.isSystemMemoryShortage, testCase.shortage, "\(testCase.reasons)")
        }
    }

    func testMalformedReportsAreIgnored() {
        let cases = [
            "",
            "not json",
            "{\"bug_type\":\"298\"}",
            "{\"bug_type\":\"298\"}\n{ broken",
            "{\"bug_type\":\"298\"}\n[1, 2, 3]",
            "{\"bug_type\":\"298\"}\n{\"processes\": \"nope\"}",
        ]
        for text in cases {
            XCTAssertNil(MemoryPressureRule.event(fromReport: text), text)
        }
    }

    func testToleratesMissingPageSizeLargestProcessAndDate() throws {
        let body = """
        {"processes": [{"name": "a", "rpages": 2, "reason": "vm-pageshortage"}, {"name": "b", "rpages": 5}, {"rpages": 9}]}
        """
        let event = try XCTUnwrap(MemoryPressureRule.event(fromReport: "{\"bug_type\":\"298\"}\n" + body))

        XCTAssertEqual(event.largestProcess, "b", "falls back to the biggest named process")
        XCTAssertEqual(event.topProcesses.first?.residentBytes, 5 * MemoryPressureRule.defaultPageSize)
        XCTAssertNil(event.date)
    }

    // MARK: - Rule

    func testReportsMostRecentShortageWithinWindow() async throws {
        try write("JetsamEvent-2026-10-06-210125.ips", date: "2026-10-06 21:01:25.66 +0700", largest: "Google Chrome",
                  reason: "vm-pageshortage", age: 15 * 3600)
        try write("JetsamEvent-2026-10-07-044717.ips", date: "2026-10-07 04:47:17.10 +0700", largest: "Paseo Helper",
                  reason: "per-process-limit", age: 7 * 3600)

        let findings = await rule().customScan(environment: .current()) ?? []

        let finding = try XCTUnwrap(findings.first)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(finding.category, .diagnostics)
        XCTAssertEqual(finding.riskLevel, .advanced)
        XCTAssertEqual(finding.sizeBytes, 0)
        XCTAssertTrue(finding.path.hasSuffix("JetsamEvent-2026-10-06-210125.ips"), finding.path)
        XCTAssertTrue(finding.reason.hasPrefix("The Mac ran out of memory on "), finding.reason)
        XCTAssertTrue(finding.reason.contains("largest process was Google Chrome (2 GB)"), finding.reason)
        XCTAssertFalse(finding.reason.contains("Low disk"), finding.reason)
        XCTAssertEqual(finding.annotations, [.explainOnly(action: "Quit memory-heavy apps such as Google Chrome before memory runs out")])
    }

    func testNothingReportedForPerProcessLimitsStaleOrMissingReports() async throws {
        let empty = await rule().customScan(environment: .current()) ?? []
        XCTAssertTrue(empty.isEmpty)

        try write("JetsamEvent-a.ips", date: nil, largest: "x", reason: "per-process-limit", age: 3600)
        try write("JetsamEvent-b.ips", date: nil, largest: "y", reason: "vm-pageshortage", age: 8 * 24 * 3600)
        try write("CrashReport-c.ips", date: nil, largest: "z", reason: "vm-pageshortage", age: 3600)

        let findings = await rule().customScan(environment: .current()) ?? []
        XCTAssertTrue(findings.isEmpty, "\(findings.map(\.reason))")
    }

    func testLowDiskWithHighSwapAddsWarning() async throws {
        try write("JetsamEvent-1.ips", date: nil, largest: "Google Chrome", reason: "vm-compressor-space-shortage", age: 3600)
        let highSwap = SwapUsageRule.minimumReportedSwapBytes + 1
        let lowDisk = MemoryPressureRule.lowDiskWarningBytes - 1

        let warned = await rule(swap: highSwap, freeDisk: lowDisk).customScan(environment: .current()) ?? []
        let plentyOfDisk = await rule(swap: highSwap, freeDisk: MemoryPressureRule.lowDiskWarningBytes).customScan(environment: .current()) ?? []
        let lowSwap = await rule(swap: 0, freeDisk: lowDisk).customScan(environment: .current()) ?? []

        XCTAssertTrue(warned.first?.reason.contains("Low disk space coincides with high swap use") == true, "\(warned.map(\.reason))")
        XCTAssertFalse(plentyOfDisk.first?.reason.contains("Low disk") ?? true)
        XCTAssertFalse(lowSwap.first?.reason.contains("Low disk") ?? true)
    }

    func testOnlyNewestReportsAreRead() async throws {
        for index in 0..<(MemoryPressureRule.maxReportsInspected + 2) {
            let reason = index < MemoryPressureRule.maxReportsInspected ? "per-process-limit" : "vm-pageshortage"
            try write("JetsamEvent-\(index).ips", date: nil, largest: "p\(index)", reason: reason, age: TimeInterval(index + 1) * 600)
        }

        let findings = await rule().customScan(environment: .current()) ?? []

        XCTAssertTrue(findings.isEmpty, "older shortages beyond the newest \(MemoryPressureRule.maxReportsInspected) are not read")
    }

    func testSizeZeroDiagnosticSurvivesScanAndStaysOutOfTotals() async throws {
        try write("JetsamEvent-1.ips", date: nil, largest: "Google Chrome", reason: "vm-pageshortage", age: 3600)

        let report = await ScanRunner(environment: .current()).run(rules: [rule()])

        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.totalReclaimableBytes, 0)
    }

    func testRegisteredInUnifiedScan() {
        XCTAssertTrue(RuleCatalog.all.contains { $0.id == MemoryPressureRule().id })
    }

    // MARK: - Helpers

    private func rule(swap: Int64? = 0, freeDisk: Int64? = Int64.max) -> MemoryPressureRule {
        MemoryPressureRule(
            reportDirectories: [reports],
            swapUsedBytes: { swap },
            freeDiskBytes: { freeDisk },
            now: { Self.now }
        )
    }

    private func write(_ name: String, date: String?, largest: String, reason: String, age: TimeInterval) throws {
        let text = Self.report(date: date, largest: largest, processes: [(largest, 131_072, nil), ("victim", 10, reason)])
        let url = reports.appending(path: name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Self.now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    /// Header line plus pretty JSON body, as `.ips` reports are written.
    private static func report(
        date: String? = nil,
        largest: String? = nil,
        processes: [(name: String, rpages: Int, reason: String?)]
    ) -> String {
        var body: [String: Any] = [
            "bug_type": "298",
            "memoryStatus": ["pageSize": 16_384],
            "processes": processes.map { process -> [String: Any] in
                var entry: [String: Any] = ["name": process.name, "rpages": process.rpages, "pid": 1]
                if let reason = process.reason { entry["reason"] = reason }
                return entry
            },
        ]
        if let date { body["date"] = date }
        if let largest { body["largestProcess"] = largest }
        let header = "{\"bug_type\":\"298\",\"timestamp\":\"2026-10-07 04:47:17.00 +0700\"}"
        let data = try! JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])
        return header + "\n" + String(decoding: data, as: UTF8.self)
    }
}
