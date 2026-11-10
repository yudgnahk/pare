import XCTest
import PareCore
@testable import PareApp

final class DiagnosticLinesTests: XCTestCase {

    private func finding(
        _ category: ScanCategory = .diagnostics, risk: RiskLevel = .advanced, reason: String = "r",
        path: String = "/p", bytes: Int64 = 1, annotations: [FindingAnnotation] = [.explainOnly(action: "Do it")]
    ) -> ScanFinding {
        ScanFinding(
            category: category, riskLevel: risk, reason: reason, path: path, sizeBytes: bytes,
            lastUsed: nil, confidence: 1, annotations: annotations
        )
    }

    func testNoDiagnosticsYieldsNoLines() {
        XCTAssertTrue(DiagnosticLine.lines(from: []).isEmpty)
        XCTAssertTrue(DiagnosticLine.lines(from: [finding(.userCaches, risk: .safe, annotations: [])]).isEmpty)
    }

    func testNonDiagnosticAndNonExplainOnlyFindingsAreIgnored() {
        let lines = DiagnosticLine.lines(from: [
            finding(.userCaches, risk: .safe, path: "/cache", annotations: [.explainOnly(action: "x")]),
            finding(.developerPackageCaches, risk: .advanced, path: "/go", annotations: [.workingSet(selfTrimDays: 5)]),
            finding(.diagnostics, path: "/bare", annotations: []),
        ])
        XCTAssertTrue(lines.isEmpty)
    }

    func testUsesExplainOnlyActionAndReasonHeadline() {
        let lines = DiagnosticLine.lines(from: [
            finding(reason: "4.1 GB of swap in use — close apps", path: "/swap", annotations: [.explainOnly(action: "Restart Chrome")]),
        ])
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].headline, "4.1 GB of swap in use")
        XCTAssertEqual(lines[0].action, "Restart Chrome")
    }

    func testHeadlineWithoutSeparatorKeepsReasonWithoutTrailingPeriod() {
        let lines = DiagnosticLine.lines(from: [finding(reason: "Memory ran short twice.")])
        XCTAssertEqual(lines[0].headline, "Memory ran short twice")
    }

    func testLargestFirstThenPathForTies() {
        let lines = DiagnosticLine.lines(from: [
            finding(path: "/b", bytes: 5), finding(path: "/big", bytes: 50), finding(path: "/a", bytes: 5),
        ])
        XCTAssertEqual(lines.map(\.id), ["/big", "/a", "/b"])
    }
}
