import XCTest
@testable import PareCore

/// Deep links checked against System Settings' own extension plists on macOS 27; guard them from drift.
final class SystemSettingsLinksTests: XCTestCase {

    func testLoginItemsLinks() {
        XCTAssertEqual(SystemSettingsLinks.loginItems.map(\.absoluteString), [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ])
    }

    func testICloudStorageLinks() {
        XCTAssertEqual(SystemSettingsLinks.iCloudStorage.map(\.absoluteString), [
            "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"
                + "?email/prefs/storage?root=APPLE_ACCOUNT&path=STORAGE_AND_BACKUP/MANAGE_STORAGE",
            "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings",
        ])
    }
}
