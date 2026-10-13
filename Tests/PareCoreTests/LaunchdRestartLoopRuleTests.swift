import XCTest
@testable import PareCore

/// Launch agents launchd keeps restarting after they fail: explained, never touched.
final class LaunchdRestartLoopRuleTests: XCTestCase {

    private static let domain = """
    gui/501 = {
    \ttype = gui
    \tservices = {
    \t\t   74263      - \tapplication.com.example.Viewer.1.2
    \t\t   73695   (pe) \tcom.example.syncd
    \t\t       0      0 \tcom.example.clean-exit
    \t\t   11755      1 \tdev.example.daemon
    \t\t       0    -10 \tcom.example.Menu
    \t\t       0   (jt) \tcom.example.constructiond
    \t\tgarbage line
    \t}
    \tunmanaged processes = {
    \t\t       0      7 \tnot.a.service
    \t}
    }
    """

    private static func service(path: String = "/Users/u/Library/LaunchAgents/dev.example.daemon.plist",
                                runs: String? = "38971",
                                exit: String? = "last exit code = 1",
                                program: String? = "/Users/u/.local/bin/example-daemon") -> String {
        var lines = ["gui/501/dev.example.daemon = {", "\tactive count = 1", "\tpath = \(path)", "\tstate = running"]
        if let program { lines.append("\tprogram = \(program)") }
        if let runs { lines.append("\truns = \(runs)") }
        if let exit { lines.append("\t\(exit)") }
        lines += ["\tendpoints = {", "\t\truns = 999999", "\t}", "}"]
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    func testCandidatesAreServicesWithNonZeroLastStatus() {
        XCTAssertEqual(LaunchdRestartLoopRule.loopCandidates(fromDomainPrint: Self.domain), ["dev.example.daemon", "com.example.Menu"])
        XCTAssertEqual(LaunchdRestartLoopRule.loopCandidates(fromDomainPrint: ""), [])
        XCTAssertEqual(LaunchdRestartLoopRule.loopCandidates(fromDomainPrint: "garbage\n\tservices = {\n}"), [])
    }

    func testServiceFieldsAreReadFromTopLevelOnly() throws {
        let service = try XCTUnwrap(LaunchdRestartLoopRule.service(label: "dev.example.daemon", fromPrint: Self.service()))

        XCTAssertEqual(service.runs, 38_971, "nested `runs` inside a block must not override the service's own")
        XCTAssertEqual(service.lastExitCode, 1)
        XCTAssertNil(service.lastSignal)
        XCTAssertEqual(service.plistPath, "/Users/u/Library/LaunchAgents/dev.example.daemon.plist")
        XCTAssertTrue(service.isRestartLoop)
    }

    func testRestartLoopTruthTable() {
        let threshold = LaunchdRestartLoopRule.minimumRestartCount
        let cases: [(runs: String?, exit: String?, loop: Bool)] = [
            ("\(threshold + 1)", "last exit code = 1", true),
            ("\(threshold + 1)", "last exit code = 78", true),
            ("\(threshold + 1)", "last exit code = 78: EX_CONFIG", true),
            ("\(threshold + 1)", "last exit code = 0: Undefined error: 0", false),
            ("\(threshold + 1)", "last terminating signal = Bus error: 10", true),
            ("\(threshold)", "last exit code = 1", false),
            ("\(threshold + 1)", "last exit code = 0", false),
            ("\(threshold + 1)", "last exit code = (never exited)", false),
            ("\(threshold + 1)", nil, false),
            (nil, "last exit code = 1", false),
            ("lots", "last exit code = 1", false),
        ]
        for testCase in cases {
            let service = LaunchdRestartLoopRule.service(
                label: "x", fromPrint: Self.service(runs: testCase.runs, exit: testCase.exit)
            )
            XCTAssertEqual(service?.isRestartLoop ?? false, testCase.loop, "\(String(describing: testCase.runs)) \(String(describing: testCase.exit))")
        }
        XCTAssertNil(LaunchdRestartLoopRule.service(label: "x", fromPrint: ""))
        XCTAssertNil(LaunchdRestartLoopRule.service(label: "x", fromPrint: "Could not find service \"x\" in domain for user gui: 501"))
    }

    // MARK: - Rule

    func testOneExplainOnlyFindingPerLoopingAgent() async throws {
        let printer = ScriptedLaunchctl(domain: Self.domain, services: [
            "dev.example.daemon": Self.service(),
            "com.example.Menu": Self.service(
                path: "(submitted by smd.542)", runs: "13645",
                exit: "last terminating signal = Bus error: 10", program: "/Applications/Example.app/Contents/MacOS/Menu"
            ),
        ])

        let findings = await LaunchdRestartLoopRule(uid: 501, print: printer.print).customScan(environment: .current()) ?? []

        XCTAssertEqual(findings.count, 2)
        let daemon = try XCTUnwrap(findings.first { $0.path.hasSuffix("dev.example.daemon.plist") })
        XCTAssertEqual(daemon.category, .diagnostics)
        XCTAssertEqual(daemon.riskLevel, .advanced)
        XCTAssertEqual(daemon.sizeBytes, 0)
        XCTAssertEqual(
            daemon.reason,
            "dev.example.daemon restarted 38,971 times; last exit code 1 — check or remove the agent in /Users/u/Library/LaunchAgents/dev.example.daemon.plist"
        )
        XCTAssertEqual(daemon.annotations, [.explainOnly(action: "Check or remove the agent in /Users/u/Library/LaunchAgents/dev.example.daemon.plist")])

        let menu = try XCTUnwrap(findings.first { $0.reason.hasPrefix("com.example.Menu") })
        XCTAssertEqual(menu.path, "/Applications/Example.app/Contents/MacOS/Menu", "no plist: the program path names it")
        XCTAssertTrue(menu.reason.contains("last terminated by signal Bus error: 10"), menu.reason)
        XCTAssertTrue(menu.reason.contains("check the app that registered it"), menu.reason)
        XCTAssertEqual(Set(printer.targets), ["gui/501", "gui/501/dev.example.daemon", "gui/501/com.example.Menu"])
    }

    func testPerLabelCallsAreCapped() async {
        let count = LaunchdRestartLoopRule.maxServicesInspected + 5
        let rows = (0..<count).map { "\t\t       0      1 \tcom.example.loop\($0)" }.joined(separator: "\n")
        let domain = "gui/501 = {\n\tservices = {\n\(rows)\n\t}\n}"
        let printer = ScriptedLaunchctl(domain: domain, services: [:], fallback: Self.service())

        let findings = await LaunchdRestartLoopRule(uid: 501, print: printer.print).customScan(environment: .current()) ?? []

        XCTAssertEqual(printer.targets.count, 1 + LaunchdRestartLoopRule.maxServicesInspected)
        XCTAssertEqual(findings.count, LaunchdRestartLoopRule.maxServicesInspected)
    }

    func testNothingReportedWhenLaunchctlUnavailable() async {
        let findings = await LaunchdRestartLoopRule(uid: 501, print: { _ in nil }).customScan(environment: .current()) ?? []

        XCTAssertTrue(findings.isEmpty)
    }

    func testCleanupRefusesLoopFindingAndTotalsExcludeIt() async throws {
        let printer = ScriptedLaunchctl(domain: Self.domain, services: ["dev.example.daemon": Self.service()])
        let rule = LaunchdRestartLoopRule(uid: 501, print: printer.print)
        let report = await ScanRunner(environment: .current()).run(rules: [rule])
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.totalReclaimableBytes, 0)

        let store = FileManager.default.temporaryDirectory.appending(path: "pare_launchd_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store) }
        let engine = CleanupEngineFixture.make(
            store: CleanupTransactionStore(directory: store),
            projectRootsProvider: { [] },
            exclusionsProvider: { .empty },
            trashItem: { url in
                XCTFail("a launch agent must never reach the Trash: \(url.path)")
                return nil
            }
        )

        let result = try await engine.clean(findings: report.findings, profileName: "test")

        XCTAssertTrue(result.succeeded.isEmpty)
        guard case .some(.advancedRiskBlocked(_)) = result.skipped.first?.error else {
            return XCTFail("expected .advancedRiskBlocked, got \(result.skipped)")
        }
    }

    func testRegisteredInUnifiedScan() {
        XCTAssertTrue(RuleCatalog.all.contains { $0.id == LaunchdRestartLoopRule().id })
    }
}

/// Answers `launchctl print <target>` from canned output and records every target asked for.
private final class ScriptedLaunchctl: @unchecked Sendable {
    private let domain: String
    private let services: [String: String]
    private let fallback: String?
    private let lock = NSLock()
    private var asked: [String] = []

    init(domain: String, services: [String: String], fallback: String? = nil) {
        self.domain = domain
        self.services = services
        self.fallback = fallback
    }

    var targets: [String] { lock.withLock { asked } }

    var print: LaunchdRestartLoopRule.Print {
        { [self] target in
            lock.withLock { asked.append(target) }
            let parts = target.split(separator: "/")
            guard parts.count == 3 else { return domain }
            return services[String(parts[2])] ?? fallback
        }
    }
}
