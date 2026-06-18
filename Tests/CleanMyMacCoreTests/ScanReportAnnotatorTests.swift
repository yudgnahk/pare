import XCTest
@testable import CleanMyMacCore

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
