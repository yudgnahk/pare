import Foundation

/// Persists the set of user-configured project root directories folded into
/// `ProjectArtifactsRule` alongside Spotlight-discovered roots.
/// Stored as a string array in `UserDefaults` under a fixed key.
public struct ProjectScanPathStore: Sendable {
    public static let shared = ProjectScanPathStore()

    private static let key = "com.yudgnahk.pare.projectScanPaths"
    private let defaults: DefaultsStorage

    public init(defaults: UserDefaults = .standard) {
        self.defaults = DefaultsStorage(defaults)
    }

    public var paths: [String] {
        defaults.value.stringArray(forKey: Self.key) ?? []
    }

    public func add(_ path: String) {
        var current = paths
        guard !current.contains(path) else { return }
        current.append(path)
        defaults.value.set(current, forKey: Self.key)
    }

    public func remove(_ path: String) {
        var current = paths
        current.removeAll { $0 == path }
        defaults.value.set(current, forKey: Self.key)
    }

    public func setAll(_ newPaths: [String]) {
        defaults.value.set(newPaths, forKey: Self.key)
    }
}

private final class DefaultsStorage: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}
