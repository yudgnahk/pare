import Foundation

/// One app, tool or macOS area, identified only by whole-component path prefixes and bundle-ID prefixes.
public struct KnownOwner: Sendable {
    public let id: String
    public let name: String
    public let kind: OwnerKind
    /// Component prefixes relative to `~`; a trailing `*` on the last component means "starts with".
    public let homePrefixes: [String]
    /// Component prefixes from `/`.
    public let rootPrefixes: [String]
    /// Lowercase bundle-ID prefixes, matched on dot boundaries.
    public let bundleIDs: [String]

    init(
        _ id: String, _ name: String, _ kind: OwnerKind,
        home: [String] = [], root: [String] = [], bundle: [String] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.homePrefixes = home
        self.rootPrefixes = root
        self.bundleIDs = bundle
    }

    var owner: FolderOwner {
        switch kind {
        case .macOS: return .macOS
        case .tool: return FolderOwner(kind: .tool, key: "tool:\(id)", displayName: name)
        default: return FolderOwner(kind: .app, key: "app:\(id)", displayName: name)
        }
    }
}

/// Data-only table of the owners Pare's rules already touch. Earlier entries win ties.
public enum KnownOwners {
    public static let all: [KnownOwner] = browsers + communication + editors + creative + aiTools + devTools + system

    static func app(_ id: String, _ name: String, home: [String] = [], root: [String] = [], bundle: [String] = []) -> KnownOwner {
        KnownOwner(id, name, .app, home: home, root: root, bundle: bundle)
    }

    static func tool(_ id: String, _ name: String, home: [String] = [], bundle: [String] = []) -> KnownOwner {
        KnownOwner(id, name, .tool, home: home, bundle: bundle)
    }

    private static let system: [KnownOwner] = [
        KnownOwner(
            "macos", "macOS", .macOS,
            home: ["Library/Logs/DiagnosticReports", "Library/Logs/CrashReporter", "Library/Caches/TemporaryItems"],
            root: ["Library/Logs", "private/var/folders", "private/tmp", "private/var/log"]
        ),
    ]
}
