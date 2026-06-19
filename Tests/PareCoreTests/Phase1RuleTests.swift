import XCTest
@testable import PareCore

// MARK: - AIToolCachesRuleTests

final class AIToolCachesRuleTests: XCTestCase {
    let rule = AIToolCachesRule()
    let home = "/Users/test"

    private func oldValues() -> URLResourceValues {
        var v = URLResourceValues()
        v.contentModificationDate = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        return v
    }

    private func newValues() -> URLResourceValues {
        var v = URLResourceValues()
        v.contentModificationDate = Date()
        return v
    }

    // MARK: Category and risk

    func testCategoryAndRisk() {
        XCTAssertEqual(rule.category, .aiToolCaches)
        XCTAssertEqual(rule.riskLevel, .safe)
    }

    // MARK: Cursor (Application Support)

    func testCursorCacheIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/Cache/data"),
            resourceValues: oldValues()
        ))
    }

    func testCursorCachedDataIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/CachedData/bundle.js"),
            resourceValues: oldValues()
        ))
    }

    func testCursorCodeCacheIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/Code Cache/v8.data"),
            resourceValues: oldValues()
        ))
    }

    func testCursorCacheExcludedWhenTooNew() {
        XCTAssertFalse(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/Cache/data"),
            resourceValues: newValues()
        ))
    }

    // MARK: Claude desktop (Application Support)

    func testClaudeCacheIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/Claude/Cache/response.bin"),
            resourceValues: oldValues()
        ))
    }

    func testClaudeCachedDataIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/Claude/CachedData/bundle.js"),
            resourceValues: oldValues()
        ))
    }

    // MARK: Windsurf (Application Support)

    func testWindsurfCacheIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/Windsurf/Cache/data"),
            resourceValues: oldValues()
        ))
    }

    // MARK: Copilot for Xcode (Library/Caches)

    func testCopilotXcodeCacheIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Caches/com.github.copilot-for-xcode/cache.db"),
            resourceValues: oldValues()
        ))
    }

    // MARK: Continue.dev dotfile caches

    func testContinueCacheIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/.continue/cache/response.json"),
            resourceValues: oldValues()
        ))
    }

    func testContinueIndexIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/.continue/.index/embeddings.bin"),
            resourceValues: oldValues()
        ))
    }

    // MARK: Tabnine

    func testTabnineCacheIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/.tabnine/model.bin"),
            resourceValues: oldValues()
        ))
    }

    // MARK: Non-target paths excluded

    func testCursorUserSettingsExcluded() {
        // User settings are in Application Support/Cursor/User — not a cache subdir
        XCTAssertFalse(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/User/settings.json"),
            resourceValues: oldValues()
        ))
    }

    func testUnrelatedAppSupportExcluded() {
        XCTAssertFalse(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/SomeOtherApp/cache.db"),
            resourceValues: oldValues()
        ))
    }

    // MARK: Target directories (catalog-driven)

    func testTargetDirectoriesContainsExpectedTools() {
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: home))
        let paths = rule.targetDirectories(environment: env).map { $0.path }
        // Electron-based editors — Application Support cache subdirs
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("Cursor/Cache") }))
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("Claude/Cache") }))
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("Windsurf/Cache") }))
        // Copilot — Library/Caches
        XCTAssertTrue(paths.contains(where: { $0.contains("com.github.copilot-for-xcode") }))
        // Dotfile tools
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("/.tabnine") }))
        XCTAssertTrue(paths.contains(where: { $0.hasSuffix("/.continue/cache") }))
        // Catalog is the source of truth — count must be > 0
        XCTAssertGreaterThan(paths.count, 0)
    }
}

// MARK: - AppCatalogTests

final class AppCatalogTests: XCTestCase {
    func testCatalogLoadsSuccessfully() {
        XCTAssertGreaterThan(AppCatalog.shared.entries.count, 0)
        XCTAssertEqual(AppCatalog.shared.version, 1)
    }

    func testAIEntriesPresent() {
        let aiEntries = AppCatalog.shared.entries(forCategory: "ai")
        XCTAssertGreaterThan(aiEntries.count, 0)
        let ids = aiEntries.map { $0.id }
        XCTAssertTrue(ids.contains("cursor"))
        XCTAssertTrue(ids.contains("claude-desktop"))
        XCTAssertTrue(ids.contains("windsurf"))
        XCTAssertTrue(ids.contains("tabnine"))
        XCTAssertTrue(ids.contains("continue-dev"))
    }

    func testAllEntriesHaveRequiredFields() {
        for entry in AppCatalog.shared.entries {
            XCTAssertFalse(entry.id.isEmpty, "Entry missing id")
            XCTAssertFalse(entry.displayName.isEmpty, "Entry \(entry.id) missing displayName")
            XCTAssertFalse(entry.category.isEmpty, "Entry \(entry.id) missing category")
            let hasPaths = !entry.libraryPaths.isEmpty || !entry.homePaths.isEmpty
            XCTAssertTrue(hasPaths, "Entry \(entry.id) has no paths")
        }
    }

    func testAIToolSafePathMarkersAreNonEmpty() {
        XCTAssertFalse(ScanPolicy.aiToolSafePathMarkers.isEmpty)
        XCTAssertTrue(ScanPolicy.aiToolSafePathMarkers.contains(where: { $0.contains("cursor") }))
        XCTAssertTrue(ScanPolicy.aiToolSafePathMarkers.contains(where: { $0.contains("claude") }))
    }
}

// MARK: - HomebrewCacheRuleTests

final class HomebrewCacheRuleTests: XCTestCase {
    let rule = HomebrewCacheRule()
    let home = "/Users/test"

    private func oldValues() -> URLResourceValues {
        var v = URLResourceValues()
        v.contentModificationDate = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        return v
    }

    private func freshValues() -> URLResourceValues {
        var v = URLResourceValues()
        v.contentModificationDate = Date().addingTimeInterval(-1800) // 30 min ago
        return v
    }

    func testCategoryAndRisk() {
        XCTAssertEqual(rule.category, .developerPackageCaches)
        XCTAssertEqual(rule.riskLevel, .safe)
    }

    func testOldBottleIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Caches/Homebrew/downloads/abc--git-2.43.0.bottle.tar.gz"),
            resourceValues: oldValues()
        ))
    }

    func testFreshDownloadExcluded() {
        // File downloaded 30 min ago — could still be in progress; skip it
        XCTAssertFalse(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Caches/Homebrew/downloads/def--node-21.0.0.bottle.tar.gz"),
            resourceValues: freshValues()
        ))
    }

    func testNonCachePathExcluded() {
        XCTAssertFalse(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Library/Application Support/Homebrew/settings.json"),
            resourceValues: oldValues()
        ))
    }

    func testTargetDirectory() {
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: home))
        let dirs = rule.targetDirectories(environment: env)
        XCTAssertEqual(dirs.count, 1)
        XCTAssertTrue(dirs[0].path.hasSuffix("Library/Caches/Homebrew/downloads"))
    }
}

// MARK: - InstallerFileRuleTests

final class InstallerFileRuleTests: XCTestCase {
    let rule = InstallerFileRule()
    let home = "/Users/test"

    private func oldValues() -> URLResourceValues {
        var v = URLResourceValues()
        v.contentModificationDate = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days
        return v
    }

    private func freshValues() -> URLResourceValues {
        var v = URLResourceValues()
        v.contentModificationDate = Date().addingTimeInterval(-2 * 24 * 60 * 60) // 2 days
        return v
    }

    func testCategoryAndRisk() {
        XCTAssertEqual(rule.category, .installerFiles)
        XCTAssertEqual(rule.riskLevel, .review)
    }

    // MARK: Extension matching

    func testOldDmgIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Downloads/App.dmg"),
            resourceValues: oldValues()
        ))
    }

    func testOldPkgIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Downloads/Installer.pkg"),
            resourceValues: oldValues()
        ))
    }

    func testOldIsoIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Desktop/ubuntu.iso"),
            resourceValues: oldValues()
        ))
    }

    func testOldXipIncluded() {
        XCTAssertTrue(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Downloads/Xcode.xip"),
            resourceValues: oldValues()
        ))
    }

    // MARK: Age gate

    func testFreshDmgExcluded() {
        // 2 days old — under the 7-day gate
        XCTAssertFalse(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Downloads/NewApp.dmg"),
            resourceValues: freshValues()
        ))
    }

    // MARK: Extension filtering

    func testZipExcluded() {
        XCTAssertFalse(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Downloads/archive.zip"),
            resourceValues: oldValues()
        ))
    }

    func testExeExcluded() {
        XCTAssertFalse(rule.include(
            fileURL: URL(fileURLWithPath: "\(home)/Downloads/Setup.exe"),
            resourceValues: oldValues()
        ))
    }

    // MARK: Target directories

    func testTargetDirectories() {
        let env = ScanEnvironment(homeDirectory: URL(fileURLWithPath: home))
        let dirs = rule.targetDirectories(environment: env)
        XCTAssertEqual(dirs.count, 2)
        XCTAssertTrue(dirs.contains(where: { $0.path.hasSuffix("/Downloads") }))
        XCTAssertTrue(dirs.contains(where: { $0.path.hasSuffix("/Desktop") }))
    }
}

// MARK: - ScanPolicyInstallerTests

final class ScanPolicyInstallerTests: XCTestCase {
    let home = FileManager.default.homeDirectoryForCurrentUser.path

    func testIsInstallerFileDownloadsDmg() {
        XCTAssertTrue(ScanPolicy.isInstallerFile(
            URL(fileURLWithPath: "\(home)/Downloads/App.dmg")
        ))
    }

    func testIsInstallerFileDesktopPkg() {
        XCTAssertTrue(ScanPolicy.isInstallerFile(
            URL(fileURLWithPath: "\(home)/Desktop/Installer.pkg")
        ))
    }

    func testIsInstallerFileXip() {
        XCTAssertTrue(ScanPolicy.isInstallerFile(
            URL(fileURLWithPath: "\(home)/Downloads/Xcode.xip")
        ))
    }

    func testZipNotInstallerFile() {
        XCTAssertFalse(ScanPolicy.isInstallerFile(
            URL(fileURLWithPath: "\(home)/Downloads/archive.zip")
        ))
    }

    func testDmgOutsideDownloadsDesktopExcluded() {
        XCTAssertFalse(ScanPolicy.isInstallerFile(
            URL(fileURLWithPath: "\(home)/Documents/Backup.dmg")
        ))
    }

    func testInstallerExtensionsContainsExpectedValues() {
        XCTAssertTrue(ScanPolicy.installerExtensions.contains("dmg"))
        XCTAssertTrue(ScanPolicy.installerExtensions.contains("pkg"))
        XCTAssertTrue(ScanPolicy.installerExtensions.contains("iso"))
        XCTAssertTrue(ScanPolicy.installerExtensions.contains("xip"))
    }
}
