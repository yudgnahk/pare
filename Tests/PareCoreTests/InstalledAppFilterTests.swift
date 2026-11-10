import XCTest
@testable import PareCore

final class InstalledAppFilterTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func isInstalled(_ path: String) -> Bool {
        ScanPolicy.isInstalledAppLocation(URL(fileURLWithPath: path), home: home)
    }

    func testExcludesUpdaterPayloadCopy() {
        XCTAssertFalse(isInstalled(
            "/Users/tester/Library/Application Support/Open Design/launcher/channels/stable/namespaces/release-stable/versions/0.21.0/payload/Open Design.app"
        ))
    }

    func testExcludesDeveloperBuildOutput() {
        XCTAssertFalse(isInstalled("/Users/tester/Projects/yudgnahk/pare/dist/adhoc/Pare.app"))
        XCTAssertFalse(isInstalled("/Users/tester/Projects/x/.build/debug/X.app"))
        XCTAssertFalse(isInstalled("/Users/tester/Library/Developer/Xcode/DerivedData/X-abc/Build/Products/X.app"))
        XCTAssertFalse(isInstalled("/Users/tester/Projects/x/DerivedData/X.app"))
    }

    func testExcludesAnythingUnderUserLibrary() {
        XCTAssertFalse(isInstalled("/Users/tester/Library/Caches/Foo/Foo.app"))
        XCTAssertFalse(isInstalled("/Users/tester/Library/Containers/com.foo/Data/Foo.app"))
        XCTAssertFalse(isInstalled("/Users/tester/Library/Group Containers/g.foo/Foo.app"))
    }

    func testExcludesNestedBundles() {
        XCTAssertFalse(isInstalled("/Applications/Foo.app/Contents/Library/LoginItems/Helper.app"))
        XCTAssertFalse(isInstalled("/Applications/Foo.app/Contents/Frameworks/Bar.framework/Versions/A/Baz.app"))
        XCTAssertFalse(isInstalled("/Applications/Plugins.bundle/Contents/Qux.app"))
    }

    func testExcludesTrash() {
        XCTAssertFalse(isInstalled("/Users/tester/.Trash/Foo.app"))
    }

    func testKeepsLegitimateLocations() {
        XCTAssertTrue(isInstalled("/Applications/Foo.app"))
        XCTAssertTrue(isInstalled("/Applications/Setapp/Foo.app"))
        XCTAssertTrue(isInstalled("/Volumes/Data/Applications/Foo.app"))
        XCTAssertTrue(isInstalled("/Users/tester/Applications/Foo.app"))
    }

    func testKeepsLookAlikeNames() {
        XCTAssertTrue(isInstalled("/Applications/distiller.app"))
        XCTAssertTrue(isInstalled("/Users/tester/Applications/Build Tools.app"))
        XCTAssertTrue(isInstalled("/Applications/Targets/Foo.app"))
        XCTAssertTrue(isInstalled("/Users/tester/Libraryish/Foo.app"))
    }
}
