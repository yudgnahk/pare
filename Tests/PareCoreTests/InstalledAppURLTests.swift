import XCTest
@testable import PareCore

/// App locations ride along with names; the fallback budget and its single lookup per ID still hold.
final class InstalledAppURLTests: XCTestCase {

    private let chromeURL = URL(fileURLWithPath: "/nonexistent/pare/Applications/Google Chrome.app")
    private let whisperURL = URL(fileURLWithPath: "/nonexistent/pare/Applications/Whisper.app")

    func testMapReturnsURLForExactAndPrefixMatches() {
        let index = InstalledAppIndex(
            namesByBundleID: ["com.Acme.Whisper": "Whisper"], appURLsByBundleID: ["com.Acme.Whisper": whisperURL]
        )

        XCTAssertEqual(index.appURL(forBundleID: "com.acme.whisper"), whisperURL)
        XCTAssertEqual(index.appURL(forBundleID: "com.acme.whisper.helper"), whisperURL)
        XCTAssertNil(index.appURL(forBundleID: "com.acme.other"))
    }

    func testNameWithoutURLStillNamesTheApp() {
        let index = InstalledAppIndex(namesByBundleID: ["com.acme.w": "W"])

        XCTAssertEqual(index.name(forBundleID: "com.acme.w"), "W")
        XCTAssertNil(index.appURL(forBundleID: "com.acme.w"))
    }

    func testFallbackURLIsReturnedAndAskedOnlyOnce() {
        let locator = CountingLocator(known: ["com.acme.found": URL(fileURLWithPath: "/nonexistent/pare/Found.app")])
        let index = InstalledAppIndex(namesByBundleID: [:], fallbackLocator: locator, fallbackBudgetSeconds: 60)

        XCTAssertEqual(index.name(forBundleID: "com.acme.found"), "Found")
        XCTAssertEqual(index.appURL(forBundleID: "com.acme.found")?.path, "/nonexistent/pare/Found.app")
        XCTAssertNil(index.appURL(forBundleID: "com.acme.missing"))
        XCTAssertNil(index.appURL(forBundleID: "com.acme.missing"))

        XCTAssertEqual(locator.calls, 2)
    }

    func testLoadRemembersEachBundleLocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pare-apps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Whisper.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.acme.whisper", "CFBundleName": "Whisper"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))

        let index = InstalledAppIndex.load(
            roots: [root], locator: CountingLocator(known: [:]), deadline: Date(timeIntervalSinceNow: 5)
        )

        XCTAssertEqual(index.name(forBundleID: "com.acme.whisper"), "Whisper")
        XCTAssertEqual(index.appURL(forBundleID: "com.acme.whisper")?.standardizedFileURL, app.standardizedFileURL)
    }

    func testOwnerURLUsesKnownBundleIDsThenTheKeyItself() {
        let index = InstalledAppIndex(
            namesByBundleID: ["com.google.chrome": "Google Chrome", "com.acme.whisper": "Whisper"],
            appURLsByBundleID: ["com.google.chrome": chromeURL, "com.acme.whisper": whisperURL]
        )
        let chrome = FolderOwner(kind: .app, key: "app:chrome", displayName: "Chrome")
        let whisper = FolderOwner(kind: .app, key: "app:com.acme.whisper", displayName: "Whisper")

        XCTAssertEqual(index.appURL(for: chrome), chromeURL)
        XCTAssertEqual(index.appURL(for: whisper), whisperURL)
        XCTAssertNil(index.appURL(for: FolderOwner(kind: .app, key: "app:cursor", displayName: "Cursor")))
        XCTAssertNil(index.appURL(for: FolderOwner(kind: .tool, key: "tool:com.acme.whisper", displayName: "x")))
        XCTAssertNil(index.appURL(for: .project(ProjectRef(root: "/r/a", name: "a"))))
        XCTAssertNil(index.appURL(for: .macOS))
    }

    func testEmptyIndexHasNoURLs() {
        XCTAssertNil(InstalledAppIndex.empty.appURL(forBundleID: "com.google.chrome"))
    }
}
