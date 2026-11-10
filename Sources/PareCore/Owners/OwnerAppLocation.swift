import Foundation

extension KnownOwners {
    /// Bundle IDs of each known app owner, by owner key.
    static let appBundleIDsByKey: [String: [String]] = {
        var map: [String: [String]] = [:]
        for entry in all where entry.kind == .app && !entry.bundleIDs.isEmpty {
            map[entry.owner.key] = map[entry.owner.key] ?? entry.bundleIDs
        }
        return map
    }()
}

extension InstalledAppIndex {
    /// Bundle location of an app owner: a known owner's bundle IDs, else the key's own bundle ID; nil for other kinds.
    public func appURL(for owner: FolderOwner) -> URL? {
        guard owner.kind == .app, owner.key.hasPrefix("app:") else { return nil }
        let ids = KnownOwners.appBundleIDsByKey[owner.key] ?? [String(owner.key.dropFirst("app:".count))]
        for id in ids {
            if let url = appURL(forBundleID: id) { return url }
        }
        return nil
    }
}
