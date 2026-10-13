import XCTest
@testable import PareCore

final class ScanReportAnnotatorTests: XCTestCase {

    // MARK: - sourceApp attribution

    func testVSCodeAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/com.microsoft.vscode/foo"), "VS Code")
        XCTAssertEqual(attribution("/Users/user/.vscode/extensions"), "VS Code")
    }

    func testJetBrainsAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/JetBrains/IdeaIC2023.1/foo"), "JetBrains")
    }

    func testDockerAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Containers/com.docker.docker/Data/foo"), "Docker")
    }

    func testXcodeAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Developer/Xcode/DerivedData/foo"), "Xcode")
        XCTAssertEqual(attribution("/Users/user/Library/Developer/CoreSimulator/Caches/foo"), "Xcode")
    }

    func testSafariAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/com.apple.safari/foo"), "Safari")
    }

    func testChromeAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Application Support/Google/Chrome/foo"), "Chrome")
    }

    func testFirefoxAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/Firefox/foo"), "Firefox")
    }

    func testAdobeAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/com.adobe.Lightroom/foo"), "Adobe")
    }

    func testFigmaAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/com.figma.Desktop/foo"), "Figma")
    }

    func testDaVinciResolveAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/com.blackmagicdesign.resolve/foo"), "DaVinci Resolve")
    }

    func testFinalCutProAttribution() {
        XCTAssertEqual(attribution("/Users/user/Movies/Final Cut Pro/foo"), "Final Cut Pro")
    }

    func testPackageManagersAttribution() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/Homebrew/foo"), "Package Managers")
        XCTAssertEqual(attribution("/Users/user/.cargo/registry"), "Package Managers")
    }

    func testOtherFallback() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/com.unknown.app/foo"), "Other")
    }

    // MARK: - appRollups aggregation

    func testRollupsAggregateByApp() {
        let findings = [
            makeFinding(path: "/Library/Caches/Xcode/foo", size: 1_200_000),
            makeFinding(path: "/Library/Caches/Xcode/bar", size: 2_000_000),
            makeFinding(path: "/Library/Caches/com.microsoft.vscode/baz", size: 1_100_000),
        ]
        let rollups = ScanReportAnnotator.appRollups(from: findings)

        let xcodeRollup = rollups.first { $0.app == "Xcode" }
        XCTAssertNotNil(xcodeRollup)
        XCTAssertEqual(xcodeRollup?.totalBytes, 3_200_000)
        XCTAssertEqual(xcodeRollup?.fileCount, 2)

        let vsCodeRollup = rollups.first { $0.app == "VS Code" }
        XCTAssertNotNil(vsCodeRollup)
        XCTAssertEqual(vsCodeRollup?.totalBytes, 1_100_000)
        XCTAssertEqual(vsCodeRollup?.fileCount, 1)
    }

    func testRollupsSortedBySize() {
        let findings = [
            makeFinding(path: "/Library/Caches/com.microsoft.vscode/foo", size: 1_100_000),
            makeFinding(path: "/Library/Caches/Xcode/bar", size: 2_000_000),
        ]
        let rollups = ScanReportAnnotator.appRollups(from: findings)
        XCTAssertEqual(rollups.first?.app, "Xcode")
    }

    func testRollupsEmptyForNoFindings() {
        let rollups = ScanReportAnnotator.appRollups(from: [])
        XCTAssertTrue(rollups.isEmpty)
    }

    /// Pins the full appRollups output (fold-into-Other, top files, ordering) for a mixed input.
    func testRollupsPinnedOutputForMixedFindings() {
        let mb: Int64 = 1_048_576
        var findings = (1...40).map {
            makeFinding(path: "/Users/u/Library/Caches/Google/Chrome/Default/Cache/f_\($0)", size: Int64($0) * mb / 4)
        }
        findings += [
            makeFinding(path: "/Users/u/Library/Developer/Xcode/DerivedData/App/a", size: 3 * mb),
            makeFinding(path: "/Users/u/Library/Developer/Xcode/DerivedData/App/b", size: 2 * mb + 5),
            makeFinding(path: "/Users/u/Library/Caches/Slack/tiny", size: 1_000),
            makeFinding(path: "/Users/u/Library/Caches/com.unknown.app/blob", size: 5 * mb),
            makeFinding(path: "/Users/u/Library/Caches/com.apple.Maps/tile", size: 700),
        ]
        let rollups = ScanReportAnnotator.appRollups(from: findings)

        XCTAssertEqual(rollups.map(\.app), ["Chrome", "Other", "Xcode"])
        XCTAssertEqual(rollups.map(\.fileCount), [40, 3, 2])
        XCTAssertEqual(rollups[0].totalBytes, (1...40).reduce(Int64(0)) { $0 + Int64($1) * mb / 4 })
        XCTAssertEqual(rollups[1].totalBytes, 5 * mb + 1_700)
        XCTAssertEqual(rollups[2].totalBytes, 5 * mb + 5)
        XCTAssertEqual(rollups[0].topFiles.count, 10)
        XCTAssertEqual(rollups[0].topFiles.first?.path, "/Users/u/Library/Caches/Google/Chrome/Default/Cache/f_40")
        XCTAssertEqual(rollups[0].topFiles.last?.path, "/Users/u/Library/Caches/Google/Chrome/Default/Cache/f_31")
        XCTAssertEqual(rollups[1].topFiles.map(\.path), ["/Users/u/Library/Caches/com.unknown.app/blob"])
        XCTAssertEqual(rollups[2].topFiles.map(\.sizeBytes), [3 * mb, 2 * mb + 5])
    }

    /// Guards the ASCII fast path: non-ASCII and mixed-case paths attribute like the plain string match.
    func testAttributionHandlesCaseAndNonASCII() {
        XCTAssertEqual(attribution("/Users/user/Library/Caches/GOOGLE/CHROME/foo"), "Chrome")
        XCTAssertEqual(attribution("/Users/josé/Library/Caches/Firefox/foo"), "Firefox")
        XCTAssertEqual(attribution("/Users/josé/Library/Caches/com.example.Éditor/foo"), "Éditor")
        // "xcode" + combining accent is one grapheme ("é"), so the non-ASCII path must not match "xcode".
        XCTAssertEqual(attribution("/Users/user/Caches/xcode/foo"), "Xcode")
        XCTAssertEqual(attribution("/Users/user/Caches/xcode\u{301}/foo"), "Other")
        XCTAssertEqual(attribution("/Users/jos\u{e9}/Caches/xcode/foo"), "Xcode")
    }

    // MARK: - Helpers

    private func attribution(_ path: String) -> String {
        let finding = makeFinding(path: path, size: 0)
        return ScanReportAnnotator.sourceApp(for: finding)
    }

    private func makeFinding(path: String, size: Int64) -> ScanFinding {
        ScanFinding(
            category: .userCaches,
            riskLevel: .safe,
            reason: "test",
            path: path,
            sizeBytes: size,
            lastUsed: nil,
            confidence: 1.0
        )
    }
}
