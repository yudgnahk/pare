import Foundation

// MARK: - Wrong-platform binaries and native trees (R1.7 split)

extension ScanPolicy {

    public static let windowsExecutableExtensions: Set<String> = ["exe", "msi", "dll"]
    public static let linuxExecutableExtensions: Set<String> = ["deb", "rpm", "appimage"]
    // Union — used for the CleanupEngine bypass guard.
    static let nonMacOSDownloadExtensions: Set<String> =
        windowsExecutableExtensions.union(linuxExecutableExtensions)

    /// Simple directory names used by multi-platform native trees (Node prebuilds,
    /// JetBrains plugins, VS Code extension bins, etc.). Alone these can collide with
    /// source folders (e.g. `win32` type stubs), so callers should require a macOS
    /// sibling unless the root is a known native-only tree (JetBrains plugins).
    public static let nonMacPlatformDirectoryNames: Set<String> = [
        "win", "win32", "win64", "windows",
        "linux", "linux-x86_64", "linux-aarch64", "linux-arm64",
        "linux-x86", "linux_x64", "linux_aarch64", "linux_arm64",
    ]

    /// Directory names that hold macOS natives in multi-platform trees.
    public static let macPlatformDirectoryNames: Set<String> = [
        "darwin", "macos", "osx", "mac",
        "darwin-x64", "darwin-arm64", "darwin_x64", "darwin_arm64",
        "macos-x64", "macos-arm64", "osx-x64", "osx-arm64",
        "mac-x64", "mac-arm64",
    ]

    /// Home-relative roots that ship multi-platform natives where the *parent* tree
    /// is NOT fully reclaimable (installed editor extensions / IDE plugins).
    /// Fully reclaimable caches (npx, Yarn, pnpm, Bun) are owned by package-manager
    /// rules as whole folders — listing win32/ under them would double-count.
    public static let wrongPlatformScanRootRelativePaths: [String] = [
        ".vscode/extensions",
        ".cursor/extensions",
        ".windsurf/extensions",
        "Library/Application Support/Code/CachedExtensionVSIXs",
        "Library/Application Support/Cursor/CachedExtensionVSIXs",
        "Library/Application Support/JetBrains",
    ]

    /// Compound platform-arch directory names such as `win32-x64` / `linux-arm64`.
    /// These almost never collide with source folders and are safe to flag alone.
    public static func isCompoundNonMacPlatformDirectoryName(_ name: String) -> Bool {
        let n = name.lowercased()
        if macPlatformDirectoryNames.contains(n) { return false }
        if isMacPlatformDirectoryName(n) { return false }
        let prefixes = ["win32-", "win64-", "windows-", "win32_", "win64_", "windows_", "linux-", "linux_"]
        return prefixes.contains { n.hasPrefix($0) && n.count > $0.count }
    }

    public static func isMacPlatformDirectoryName(_ name: String) -> Bool {
        let n = name.lowercased()
        if macPlatformDirectoryNames.contains(n) { return true }
        return n.hasPrefix("darwin-") || n.hasPrefix("darwin_")
            || n.hasPrefix("macos-") || n.hasPrefix("macos_")
            || n.hasPrefix("osx-") || n.hasPrefix("osx_")
            || n.hasPrefix("mac-") || n.hasPrefix("mac_")
    }

    public static func isNonMacPlatformDirectoryName(_ name: String) -> Bool {
        let n = name.lowercased()
        return nonMacPlatformDirectoryNames.contains(n) || isCompoundNonMacPlatformDirectoryName(n)
    }

    /// `true` when any path component is a non-macOS platform native directory name.
    /// Used to avoid double-counting file findings under whole-folder wrong-platform hits.
    public static func isUnderWrongPlatformNativeDirectory(_ url: URL) -> Bool {
        url.pathComponents.contains { isNonMacPlatformDirectoryName($0) }
    }

    /// Returns `true` for files that are unambiguously non-macOS platform binaries
    /// sitting at the TOP LEVEL of `~/Downloads`. This anchoring is intentional:
    /// it avoids falsely matching `.exe` files inside project `downloads/` subdirs
    /// or nested tool caches.
    public static func isWrongPlatformBinary(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard nonMacOSDownloadExtensions.contains(ext) else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()
        let downloadsPrefix = home + "/downloads/"
        let path = url.path.lowercased()
        guard path.hasPrefix(downloadsPrefix) else { return false }
        // Top-level only — reject files inside subdirectories of ~/Downloads.
        return !path.dropFirst(downloadsPrefix.count).contains("/")
    }

    /// Downloads top-level wrong-platform files **or** paths inside non-macOS native
    /// platform directories (whole-folder reclaim). Age gates are skipped for both.
    /// NOTE: scan-time helper (double-count avoidance). For cleanup decisions use
    /// `isCleanableWrongPlatformPath`, which restricts native-dir matches to the
    /// trees `WrongPlatformBinariesRule` actually scans (fail-closed).
    public static func isWrongPlatformPath(_ url: URL) -> Bool {
        isWrongPlatformBinary(url) || isUnderWrongPlatformNativeDirectory(url)
    }

    /// Cleanup-time gate for wrong-platform paths. Fail-closed: a bare `linux/` or
    /// `win32/` path component anywhere on disk (e.g. `~/Documents/linux/notes`) must
    /// NOT unlock cleanup. Only top-level `~/Downloads` binaries and native platform
    /// directories under the editor/IDE scan roots of `WrongPlatformBinariesRule` pass.
    public static func isCleanableWrongPlatformPath(_ url: URL) -> Bool {
        if isWrongPlatformBinary(url) { return true }
        guard isUnderWrongPlatformNativeDirectory(url) else { return false }
        return wrongPlatformScanRootRelativePaths.contains { relative in
            let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: relative)
            return isEqualToOrDescendant(candidate: url, root: root)
        }
    }
}
