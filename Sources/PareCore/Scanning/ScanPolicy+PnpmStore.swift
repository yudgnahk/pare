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
        return components[components.count - 2] == "store" && components[components.count - 3] == "pnpm"
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
