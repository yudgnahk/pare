import Foundation

/// How Smart Scan results are grouped.
enum BrowseMode: String, CaseIterable, Sendable {
    case apps, categories
}

/// Persists the browse mode; `inMemory()` keeps it out of user defaults (snapshots, tests).
final class BrowseModeStore {
    static let storageKey = "pare.smartScan.browseMode"
    static let defaultMode: BrowseMode = .apps

    private let defaults: UserDefaults?
    private var memory: BrowseMode

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.memory = defaults.string(forKey: Self.storageKey).flatMap(BrowseMode.init(rawValue:)) ?? Self.defaultMode
    }

    private init(initial: BrowseMode) {
        self.defaults = nil
        self.memory = initial
    }

    static func inMemory(_ initial: BrowseMode = defaultMode) -> BrowseModeStore {
        BrowseModeStore(initial: initial)
    }

    var mode: BrowseMode {
        get { memory }
        set {
            memory = newValue
            defaults?.set(newValue.rawValue, forKey: Self.storageKey)
        }
    }
}
