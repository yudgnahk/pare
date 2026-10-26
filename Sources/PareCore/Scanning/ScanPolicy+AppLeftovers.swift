import Foundation

/// How a leftover's file name relates to the bundle ID being uninstalled.
public enum BundleIDNameMatch: Sendable, Equatable {
    /// `com.foo` or `com.foo.plist`.
    case exact
    /// `com.foo.helper.plist` — may equally be another app's own bundle ID, so never auto-selected.
    case derived
    case none
}

extension ScanPolicy {
    /// Library folders whose direct children the App Manager may offer as leftovers.
    static let appLeftoverLibraryFolders = [
        "Application Support", "Caches", "Containers", "WebKit", "HTTPStorages",
        "Saved Application State", "Application Scripts", "Preferences", "Logs",
        "Cookies", "LaunchAgents", "Group Containers",
    ]

    /// Rejects bundle IDs that could escape a Library folder when joined as a path component.
    public static func isUsableLeftoverBundleID(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty, !bundleID.hasPrefix("."), !bundleID.contains("..") else { return false }
        return bundleID.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_"
        }
    }

    /// False for IDs too generic for prefix or component matching: under three components, or Apple's
    /// namespace on an app outside `/System`; such apps only get exact-name leftovers.
    public static func allowsDerivedLeftovers(bundleID: String, appPath: String) -> Bool {
        let id = bundleID.lowercased()
        guard id.split(separator: ".").count >= 3 else { return false }
        return !id.hasPrefix("com.apple.") || appPath.hasPrefix("/System/")
    }

    /// Dot-boundary match of a Preferences or launchd file name (`.plist` stripped), case-insensitive.
    public static func bundleIDNameMatch(_ fileName: String, bundleID: String) -> BundleIDNameMatch {
        let id = bundleID.lowercased()
        guard !id.isEmpty else { return .none }
        var stem = fileName.lowercased()
        if stem.hasSuffix(".plist") { stem = String(stem.dropLast(".plist".count)) }
        if stem == id { return .exact }
        return stem.hasPrefix(id + ".") ? .derived : .none
    }

    /// Group container names wrap the ID (`TEAMID.com.foo`, `group.com.foo.shared`), so match whole dot components anywhere.
    public static func groupContainerNameMatches(_ name: String, bundleID: String) -> Bool {
        let nameParts = name.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        let idParts = bundleID.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        guard !bundleID.isEmpty, nameParts.count >= idParts.count else { return false }
        return (0...(nameParts.count - idParts.count)).contains { start in
            Array(nameParts[start..<(start + idParts.count)]) == idParts
        }
    }

    /// True when a more specific installed bundle ID also claims `name`, e.g. Chrome Canary's files while removing Chrome.
    public static func isLeftoverClaimedByOtherApp(
        _ name: String,
        bundleID: String,
        otherBundleIDs: Set<String>,
        isGroupContainer: Bool
    ) -> Bool {
        let id = bundleID.lowercased()
        return otherBundleIDs.contains { other in
            let lowered = other.lowercased()
            guard lowered.count > id.count, lowered.hasPrefix(id + ".") else { return false }
            return isGroupContainer
                ? groupContainerNameMatches(name, bundleID: other)
                : bundleIDNameMatch(name, bundleID: other) != .none
        }
    }

    /// True when `path` is a direct child of a per-user Library folder the App Manager scans.
    public static func isAppLeftoverLocation(_ path: String, home: URL) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let parent = url.deletingLastPathComponent().path
        let library = home.standardizedFileURL.appendingPathComponent("Library")
        return appLeftoverLibraryFolders.contains { folder in
            library.appendingPathComponent(folder).path.caseInsensitiveCompare(parent) == .orderedSame
        }
    }
}
