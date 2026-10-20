import XCTest
import PareCore
@testable import PareApp

/// Each note button opens exactly one place and never changes anything itself.
@MainActor
final class DiagnosticActionPerformerTests: XCTestCase {

    func testEachActionRoutesToItsTarget() {
        var opened: [[URL]] = []
        var revealed: [String] = []
        var shown: [[Int32]] = []
        let performer = DiagnosticActionPerformer(
            openFirst: { opened.append($0) },
            reveal: { revealed.append($0) },
            showProcesses: { shown.append($0) }
        )

        performer.perform(.openLoginItems)
        performer.perform(.openICloudStorage)
        performer.perform(.revealInFinder(path: "/x.plist"))
        performer.perform(.showProcesses(pids: [10, 40]))

        XCTAssertEqual(opened, [SystemSettingsLinks.loginItems, SystemSettingsLinks.iCloudStorage])
        XCTAssertEqual(revealed, ["/x.plist"])
        XCTAssertEqual(shown, [[10, 40]])
    }

    func testButtonTitles() {
        XCTAssertEqual(DiagnosticActionPerformer.title(for: .showProcesses(pids: [])), "Activity Monitor")
        XCTAssertEqual(DiagnosticActionPerformer.title(for: .openLoginItems), "Login Items")
        XCTAssertEqual(DiagnosticActionPerformer.title(for: .revealInFinder(path: "/x")), "Show in Finder")
        XCTAssertEqual(DiagnosticActionPerformer.title(for: .openICloudStorage), "iCloud Storage")
    }
}
