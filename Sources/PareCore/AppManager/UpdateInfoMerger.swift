import Foundation

/// Carries known update-check results across app inventory refreshes so a
/// rescan (or a post-upgrade soft refresh) does not wipe the "Updates only"
/// list. Previously duplicated inline in the app manager view model's
/// `loadApps` and `updateApp` paths.
public enum UpdateInfoMerger {

    /// Update results captured from an existing app list, keyed by bundle ID
    /// with a path fallback for apps without one.
    public struct Snapshot: Sendable {
        public let byBundleID: [String: UpdateInfo]
        public let byPath: [String: UpdateInfo]

        public init(apps: [InstalledApp]) {
            byBundleID = Dictionary(
                apps.compactMap { app -> (String, UpdateInfo)? in
                    guard let id = app.bundleID, let info = app.updateInfo else { return nil }
                    return (id, info)
                },
                uniquingKeysWith: { first, _ in first }
            )
            byPath = Dictionary(
                apps.compactMap { app -> (String, UpdateInfo)? in
                    guard let info = app.updateInfo else { return nil }
                    return (app.path, info)
                },
                uniquingKeysWith: { first, _ in first }
            )
        }

        public var isEmpty: Bool {
            byBundleID.isEmpty && byPath.isEmpty
        }
    }

    /// Re-applies snapshotted update info onto freshly scanned apps.
    /// `clearing` marks one app as just-updated: its info is dropped instead
    /// of carried over (matched by id or path).
    public static func merge(
        scanned: [InstalledApp],
        previous: Snapshot,
        clearing updatedApp: InstalledApp? = nil
    ) -> [InstalledApp] {
        scanned.map { app in
            var merged = app
            if let updatedApp, app.id == updatedApp.id || app.path == updatedApp.path {
                merged.updateInfo = nil
                return merged
            }
            if let id = app.bundleID, let info = previous.byBundleID[id] {
                merged.updateInfo = info
            } else if let info = previous.byPath[app.path] {
                merged.updateInfo = info
            }
            return merged
        }
    }
}
