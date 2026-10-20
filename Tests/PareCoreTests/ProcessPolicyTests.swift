import XCTest
@testable import PareCore

/// System processes can only be released by restarting the Mac; user apps are named and restartable.
final class ProcessPolicyTests: XCTestCase {

    func testSystemExecutables() {
        let cases: [(path: String, system: Bool)] = [
            ("/usr/libexec/linkd", true),
            ("/System/Library/PrivateFrameworks/ChronoCore.framework/Support/chronod", true),
            ("/usr/sbin/cfprefsd", true),
            ("/sbin/launchd", true),
            ("/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/XProtect", true),
            ("/System/Applications/Mail.app/Contents/MacOS/Mail", false),
            ("/usr/bin/ssh", false),
            ("/opt/homebrew/bin/node", false),
            ("/Users/u/.local/bin/claude", false),
            ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", false),
        ]
        for testCase in cases {
            XCTAssertEqual(ProcessPolicy.isSystemExecutable(path: testCase.path), testCase.system, testCase.path)
        }
    }

    func testAppDisplayNameIsTheOutermostBundle() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/"
            + "Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        XCTAssertEqual(ProcessPolicy.appDisplayName(path: helper), "Google Chrome")
        XCTAssertEqual(ProcessPolicy.appDisplayName(path: "/System/Applications/Mail.app/Contents/MacOS/Mail"), "Mail")
        XCTAssertNil(ProcessPolicy.appDisplayName(path: "/opt/homebrew/bin/node"))
    }

    func testOwnExecutablePathResolves() {
        XCTAssertNotNil(ProcessPolicy.executablePath(pid: getpid()))
        XCTAssertNil(ProcessPolicy.executablePath(pid: -1))
    }
}
