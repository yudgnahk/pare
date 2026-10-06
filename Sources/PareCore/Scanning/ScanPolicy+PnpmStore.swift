import Foundation

// MARK: - Old pnpm store versions

extension ScanPolicy {

    /// `v<N>` with digits only; anything else in a store root (`tmp`, `v12-beta`, `v10.1`) is not a store version.
    public static func pnpmStoreVersion(_ name: String) -> Int? {
        guard name.hasPrefix("v"), name.count > 1 else { return nil }
        let digits = name.dropFirst()
        guard digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    /// A `v<N>` folder directly inside a `…/pnpm/store` root. The broad pnpm persona marker would admit
    /// these too, so `CleanupEngine` lets them through only `isReclaimableOldPnpmStore`.
    public static func isPnpmStoreVersionPath(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= 3, pnpmStoreVersion(components[components.count - 1]) != nil else { return false }
        // Case-insensitive like the volume and the persona marker, so a re-cased path cannot skip this gate.
        return components[components.count - 2].lowercased() == "store" && components[components.count - 3].lowercased() == "pnpm"
    }

    /// Anything at or under a `…/pnpm/store`, or a pnpm home folder itself (`Library/pnpm`, `.local/share/pnpm`).
    /// The broad pnpm persona markers would admit all of these; cleanup must not.
    public static func isPnpmGuardedPath(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        if components.indices.dropFirst().contains(where: { components[$0 - 1] == "pnpm" && components[$0] == "store" }) {
            return true
        }
        guard components.last == "pnpm", components.count >= 2 else { return false }
        let parent = components[components.count - 2]
        return parent == "library" || (parent == "share" && components.count >= 3 && components[components.count - 3] == ".local")
    }

    /// A store version strictly older than the active one, in the same store root, as a real folder.
    /// Nil `activeStore` (pnpm absent or silent) fails closed.
    public static func isReclaimableOldPnpmStore(_ url: URL, activeStore: URL?) -> Bool {
        guard let activeStore,
              let active = pnpmStoreVersion(activeStore.lastPathComponent),
              let version = pnpmStoreVersion(url.lastPathComponent), version < active,
              canonicalPathURL(url.deletingLastPathComponent()).path
                  == canonicalPathURL(activeStore.deletingLastPathComponent()).path,
              !hasSymbolicLinkComponent(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return false }
        return true
    }
}
