import XCTest
@testable import PareCore

final class OwnerResolverTests: XCTestCase {

    private let home = "/Users/u"

    private func resolver(
        installed: [String: String] = [:],
        home: String = "/Users/u",
        catalog: AppCatalog = AppCatalog(version: 1, entries: []),
        locator: (any AppCopyLocating)? = nil
    ) -> OwnerResolver {
        OwnerResolver(
            homeDirectory: URL(fileURLWithPath: home),
            installedApps: InstalledAppIndex(namesByBundleID: installed, fallbackLocator: locator),
            catalog: catalog
        )
    }

    private func owner(_ rel: String, installed: [String: String] = [:]) -> FolderOwner {
        resolver(installed: installed).owner(forFolderPath: "\(home)/\(rel)")
    }

    // MARK: - Misattribution table

    func testProjectFoldersNamedLikeAppsAreNotApps() {
        for rel in [
            "Code/proj/.next", "Projects/xcode-tools/build", "Projects/zoom-clone/build",
            "Projects/slack-bot/dist", "Projects/notion-api/.next", "Projects/discord.js-app/dist",
            "Code/a/node_modules", "Code/r/.bundle",
        ] {
            XCTAssertEqual(owner(rel), .other, rel)
        }
    }

    func testKnownAppComponentPrefixes() {
        XCTAssertEqual(owner("Library/Application Support/Code/Cache").key, "app:vscode")
        XCTAssertEqual(owner("Library/Application Support/Code/Cache").displayName, "VS Code")
        XCTAssertEqual(owner("Library/Developer/Xcode/DerivedData/X").key, "app:xcode")
        XCTAssertEqual(owner("Library/Developer/CoreSimulator/Caches").key, "app:xcode")
        XCTAssertEqual(owner("Library/Application Support/JetBrains/IntelliJIdea2024.1").key, "app:jetbrains")
        XCTAssertEqual(owner("Library/Caches/Google/AndroidStudio2024.1/x").key, "app:androidstudio")
        XCTAssertEqual(owner("Library/Caches/Google/Chrome/Default/Cache").key, "app:chrome")
    }

    func testKnownAppBundleIDPrefixes() {
        XCTAssertEqual(owner("Library/Caches/us.zoom.xos").key, "app:zoom")
        XCTAssertEqual(owner("Library/Caches/com.tinyspeck.slackmacgap/x").key, "app:slack")
        XCTAssertEqual(owner("Library/Caches/com.google.Chrome.helper").key, "app:chrome")
        XCTAssertEqual(owner("Library/Containers/com.docker.docker/Data").key, "app:docker")
    }

    func testToolDirectories() {
        XCTAssertEqual(owner(".npm/_npx/h/node_modules").key, "tool:npm")
        XCTAssertEqual(owner("Library/pnpm/store/v3").key, "tool:pnpm")
        XCTAssertEqual(owner("library/caches/Homebrew").key, "tool:homebrew")
        XCTAssertEqual(owner("Library/Caches/org.swift.swiftpm").key, "tool:swiftpm")
        XCTAssertEqual(owner(".cache/uv/archive-v0").key, "tool:uv")
        XCTAssertEqual(owner(".cargo/registry").displayName, "Cargo")
    }

    func testMacOSAreas() {
        XCTAssertEqual(owner("Library/Logs/DiagnosticReports/x.ips"), .macOS)
        XCTAssertEqual(owner("Library/Caches/TemporaryItems/x"), .macOS)
        let r = resolver()
        XCTAssertEqual(r.owner(forFolderPath: "/private/var/folders/ab/cd/T/x"), .macOS)
        XCTAssertEqual(r.owner(forFolderPath: "/var/folders/ab/cd/T/x"), .macOS)
        XCTAssertEqual(r.owner(forFolderPath: "/private/tmp/x"), .macOS)
        XCTAssertEqual(r.owner(forFolderPath: "/Library/Logs/x"), .macOS)
    }

    func testAppleBundleIDsAreMacOSUnlessInstalled() {
        XCTAssertEqual(owner("Library/Caches/com.apple.akd"), .macOS)
        XCTAssertEqual(owner("Library/Containers/com.apple.akd"), .macOS)
        let maps = owner("Library/Caches/com.apple.Maps/x", installed: ["com.apple.Maps": "Maps"])
        XCTAssertEqual(maps.kind, .app)
        XCTAssertEqual(maps.displayName, "Maps")
    }

    func testThirdPartyBundleIDsNeedAnInstalledApp() {
        let installed = ["com.acme.W": "W"]
        XCTAssertEqual(owner("Library/HTTPStorages/com.acme.W", installed: installed).displayName, "W")
        XCTAssertEqual(owner("Library/HTTPStorages/com.acme.W", installed: installed).key, "app:com.acme.w")
        XCTAssertEqual(owner("Library/HTTPStorages/com.acme.W"), .other)
        XCTAssertEqual(owner("Library/Caches/com.unknown.app"), .other)
    }

    func testInstalledBundleIDMatchesHelperSuffixButNotShortPrefix() {
        let installed = ["com.acme.W": "W", "com.acme": "Acme"]
        XCTAssertEqual(owner("Library/Caches/com.acme.W.helper", installed: installed).displayName, "W")
        XCTAssertEqual(owner("Library/Caches/com.acme.other", installed: installed), .other)
    }

    func testHomeFolderNameNeverMatches() {
        let r = resolver(home: "/Users/xcode")
        XCTAssertEqual(r.owner(forFolderPath: "/Users/xcode/Projects/x/build"), .other)
        XCTAssertEqual(r.owner(forFolderPath: "/Users/xcode"), .other)
        XCTAssertEqual(resolver().owner(forFolderPath: "/Users/xcode/Library/Application Support/Code"), .other)
    }

    func testOutsideHomeOnlyMatchesRootPrefixes() {
        XCTAssertEqual(resolver().owner(forFolderPath: "/Volumes/Data/Library/Application Support/Code"), .other)
        XCTAssertEqual(resolver().owner(forFolderPath: "/Library/Application Support/Adobe/x").key, "app:adobe")
    }

    // MARK: - Catalog and lookups

    func testCatalogEntriesBecomeAppsUnlessKnownByName() throws {
        let json = """
        {"version":1,"entries":[
          {"id":"continue-dev","displayName":"Continue","category":"ai","homePaths":[".continue/cache"]},
          {"id":"cursor-dup","displayName":"Cursor","category":"ai","libraryPaths":["Application Support/CursorDup"]}
        ]}
        """
        let catalog = try JSONDecoder().decode(AppCatalog.self, from: Data(json.utf8))
        let r = resolver(catalog: catalog)
        XCTAssertEqual(r.owner(forFolderPath: "\(home)/.continue/cache/x").key, "app:continue-dev")
        XCTAssertEqual(r.owner(forFolderPath: "\(home)/Library/Application Support/CursorDup"), .other)
    }

    func testProjectIndexStubNeverClaimsAFolder() {
        XCTAssertNil(ProjectIndex.empty.project(containing: "/Users/u/Code/a/.next"))
    }

    func testLocatorFallbackIsAskedOncePerBundleID() {
        let locator = CountingLocator(known: ["com.acme.found": URL(fileURLWithPath: "/Applications/Found.app")])
        let r = resolver(locator: locator)
        let a = r.owner(forFolderPath: "\(home)/Library/Caches/com.acme.found/a")
        _ = r.owner(forFolderPath: "\(home)/Library/Caches/com.acme.found/b")
        _ = r.owner(forFolderPath: "\(home)/Library/Caches/com.acme.missing/a")
        _ = r.owner(forFolderPath: "\(home)/Library/Caches/com.acme.missing/b")
        XCTAssertEqual(a.kind, .app)
        XCTAssertEqual(locator.calls, 2)
    }

    func testLoadWithNoRootsAndPastDeadlineNeverThrows() {
        let index = InstalledAppIndex.load(
            roots: [URL(fileURLWithPath: "/definitely/not/here")],
            locator: CountingLocator(known: [:]),
            deadline: Date(timeIntervalSinceNow: -1)
        )
        XCTAssertNil(index.name(forBundleID: "com.acme.x"))
    }

    func testChartLabels() {
        XCTAssertEqual(owner("Library/Application Support/Code").chartLabel, "VS Code")
        XCTAssertEqual(owner(".npm").chartLabel, "Developer tools")
        XCTAssertEqual(FolderOwner.project(ProjectRef(root: "/a", name: "a")).chartLabel, "Projects")
        XCTAssertEqual(FolderOwner.macOS.chartLabel, "macOS")
        XCTAssertEqual(FolderOwner.other.chartLabel, "Other")
    }
}

final class CountingLocator: AppCopyLocating, @unchecked Sendable {
    private let lock = NSLock()
    private let known: [String: URL]
    private var count = 0

    init(known: [String: URL]) { self.known = known }

    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

    func appURLs(forBundleID bundleID: String) -> [URL] {
        lock.lock(); count += 1; lock.unlock()
        return known[bundleID].map { [$0] } ?? []
    }
}
