import Foundation

/// Persists the set of user-configured project root directories used by `ProjectArtifactRule`.
/// Stored as a string array in `UserDefaults` under a fixed key.
public struct ProjectScanPathStore: Sendable {
    public static let shared = ProjectScanPathStore()

    private static let key = "com.yudgnahk.pare.projectScanPaths"

    public var paths: [String] {
        UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    public func add(_ path: String) {
        var current = paths
        guard !current.contains(path) else { return }
        current.append(path)
        UserDefaults.standard.set(current, forKey: Self.key)
    }

    public func remove(_ path: String) {
        var current = paths
        current.removeAll { $0 == path }
        UserDefaults.standard.set(current, forKey: Self.key)
    }

    public func setAll(_ newPaths: [String]) {
        UserDefaults.standard.set(newPaths, forKey: Self.key)
    }
}
