import XCTest
@testable import PareCore

final class HomebrewCaskroomBadgeTests: XCTestCase {
    private let tokens: Set<String> = ["open-design", "arc", "google-chrome"]

    private func manages(_ name: String, _ path: String, artifacts: Set<String> = []) -> Bool {
        HomebrewCaskroom.manages(
            appName: name, path: path, installedTokens: tokens, installedArtifactPaths: artifacts
        )
    }

    func testInstalledOpenDesignIsBadged() {
        XCTAssertTrue(manages("Open Design", "/Applications/Open Design.app"))
    }

    func testUpdaterPayloadCopyIsNotBadged() {
        let payload = "/Users/tester/Library/Application Support/Open Design/launcher/versions/0.21.0/payload/Open Design.app"
        XCTAssertFalse(manages("Open Design", payload))
    }

    func testShortTokenDoesNotMatchLookAlikes() {
        XCTAssertFalse(manages("Arcade", "/Applications/Arcade.app"))
        XCTAssertFalse(manages("Search", "/Applications/Search.app"))
        XCTAssertTrue(manages("Arc", "/Applications/Arc.app"))
    }

    func testTokenMatchesNormalizedName() {
        XCTAssertTrue(manages("Google Chrome", "/Applications/Google Chrome.app"))
    }

    func testInstalledArtifactTargetIsBadgedEvenWhenNameDiffers() {
        let path = "/Applications/Renamed Chrome.app"
        XCTAssertTrue(manages("Renamed Chrome", path, artifacts: [path.lowercased()]))
    }

    func testSameNameOutsideApplicationsIsNotBadged() {
        XCTAssertFalse(manages("Google Chrome", "/Users/tester/Downloads/Google Chrome.app"))
        XCTAssertFalse(manages("Arc", "/Volumes/Backup/Arc.app"))
    }

    func testCaskroomPathIsBadgedByWholeComponent() {
        XCTAssertTrue(manages("Foo", "/opt/homebrew/Caskroom/foo/1.0/Foo.app"))
        XCTAssertFalse(manages("Foo", "/Applications/Caskroomish/Foo.app"))
    }

    func testTokenLookupIsExact() {
        XCTAssertEqual(
            HomebrewCaskroom.token(
                forAppName: "Google Chrome", path: "/Applications/Google Chrome.app", installedTokens: tokens
            ),
            "google-chrome"
        )
        XCTAssertNil(HomebrewCaskroom.token(
            forAppName: "Arcade", path: "/Applications/Arcade.app", installedTokens: tokens
        ))
    }

    func testArtifactPathsResolveCaskroomSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("caskroom-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let versionDir = root.appendingPathComponent("foo/1.0")
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: versionDir.appendingPathComponent("Foo.app").path,
            withDestinationPath: "/Applications/Foo.app"
        )
        let targets = HomebrewCaskroom.installedArtifactPaths(roots: [root.path])
        XCTAssertEqual(targets, ["/applications/foo.app"])
    }
}
