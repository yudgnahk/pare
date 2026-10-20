import Foundation

/// System Settings deep links, first choice first, checked against the extension plists on macOS 27.
public enum SystemSettingsLinks {
    public static let loginItems: [URL] = [
        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
        "x-apple.systempreferences:com.apple.ExtensionsPreferences",
    ].compactMap(URL.init(string:))

    /// The first opens Apple Account → iCloud → Manage Storage; the second only the Apple Account pane.
    public static let iCloudStorage: [URL] = [
        "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"
            + "?email/prefs/storage?root=APPLE_ACCOUNT&path=STORAGE_AND_BACKUP/MANAGE_STORAGE",
        "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings",
    ].compactMap(URL.init(string:))
}
