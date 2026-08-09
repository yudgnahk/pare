import Foundation

/// Detects binaries and installers built for non-macOS platforms that are completely
/// inert on macOS and are **safe** to remove (cannot execute or install on Mac).
///
/// **Downloads** — `.exe`, `.msi`, `.dll`, `.deb`, `.rpm`, `.AppImage` files found
/// at the top level of `~/Downloads`. These are Windows/Linux installers or libraries
/// that cannot run natively on macOS.
///
/// **Multi-platform native trees** — whole `win32/`, `linux/`, `win32-x64/`, etc.
/// directories inside package managers, editor extensions, JetBrains plugins, and
/// similar tool caches. Only the macOS/`darwin` variant is loaded at runtime; the
/// other platform trees are dead weight (often tens to hundreds of MB per package).
public struct WrongPlatformBinariesRule: ScanRule {
    public let id = "wrong-platform-binaries"
    public let title = "Non-macOS Platform Binaries"
    public let reason = "Binary or installer built for Windows or Linux — cannot run on macOS"
    public let category: ScanCategory = .temporaryFiles
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.93

    // Reuse the canonical sets from ScanPolicy so there's one source of truth.
    private static var windowsExts: Set<String> { ScanPolicy.windowsExecutableExtensions }
    private static var linuxExts: Set<String> { ScanPolicy.linuxExecutableExtensions }

    // Only bother reporting downloads larger than this — tiny stubs aren't worth the noise.
    private static let downloadsMinBytes: Int64 = 512 * 1024

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        var findings: [ScanFinding] = []

        findings += scanDownloads(in: environment.homeDirectory.appending(path: "Downloads"))

        for root in Self.scanRoots(home: environment.homeDirectory) {
            findings += findPlatformStubDirs(
                under: root.url,
                label: root.label,
                requireMacSiblingForSimpleNames: root.requireMacSiblingForSimpleNames,
                sizeIndex: environment.sizeIndex
            )
        }

        return findings
    }

    // MARK: - Scan roots

    private struct ScanRoot {
        let url: URL
        let label: String
        /// When `true`, simple names like `win32`/`linux` only match if a macOS sibling
        /// exists (avoids source folders). Compound names (`win32-x64`) always match.
        let requireMacSiblingForSimpleNames: Bool
    }

    private static func scanRoots(home: URL) -> [ScanRoot] {
        ScanPolicy.wrongPlatformScanRootRelativePaths.map { relative in
            let lower = relative.lowercased()
            let isJetBrains = lower.contains("jetbrains")
            let label: String
            if isJetBrains {
                label = "JetBrains"
            } else if lower.contains("vscode") || lower.contains("/code/") {
                label = "VS Code"
            } else if lower.contains("cursor") {
                label = "Cursor"
            } else if lower.contains("windsurf") {
                label = "Windsurf"
            } else if lower.contains(".npm") {
                label = "npm/npx"
            } else if lower.contains("yarn") {
                label = "Yarn"
            } else if lower.contains("pnpm") {
                label = "pnpm"
            } else if lower.contains(".bun") {
                label = "Bun"
            } else {
                label = relative
            }
            return ScanRoot(
                url: home.appending(path: relative),
                label: label,
                // JetBrains plugin trees use `win/`/`linux/` without always shipping a
                // same-parent mac sibling; other ecosystems use multi-platform siblings.
                requireMacSiblingForSimpleNames: !isJetBrains
            )
        }
    }

    // MARK: - Downloads

    private func scanDownloads(in dir: URL) -> [ScanFinding] {
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var findings: [ScanFinding] = []
        for url in contents {
            let res = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard res?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            let isWindows = Self.windowsExts.contains(ext)
            let isLinux = Self.linuxExts.contains(ext)
            guard isWindows || isLinux else { continue }

            let size = Int64(res?.fileSize ?? 0)
            guard size >= Self.downloadsMinBytes else { continue }

            let platform = isWindows ? "Windows" : "Linux"
            findings.append(ScanFinding(
                category: .temporaryFiles,
                riskLevel: .safe,
                reason: "\(platform) \(ext.uppercased()) — not executable on macOS (safe to remove)",
                path: url.path,
                sizeBytes: size,
                lastUsed: res?.contentModificationDate,
                confidence: confidence
            ))
        }
        return findings
    }

    // MARK: - Platform native directories

    /// Walks a tree and reports every non-macOS platform native directory as one finding.
    /// Calls `skipDescendants()` on each match so nested content is never double-counted.
    private func findPlatformStubDirs(
        under root: URL,
        label: String,
        requireMacSiblingForSimpleNames: Bool,
        sizeIndex: DirectorySizeIndex
    ) -> [ScanFinding] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Cache parent → sibling names so multi-child trees don't re-list constantly.
        var siblingCache: [String: Set<String>] = [:]

        var findings: [ScanFinding] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = url.lastPathComponent
            let lower = name.lowercased()

            // Toolbox manages IDE installs separately — don't reclaim under it.
            if lower == "toolbox" {
                enumerator.skipDescendants()
                continue
            }

            let isCompound = ScanPolicy.isCompoundNonMacPlatformDirectoryName(lower)
            let isSimple = ScanPolicy.nonMacPlatformDirectoryNames.contains(lower)
            guard isCompound || isSimple else { continue }

            if isSimple && requireMacSiblingForSimpleNames {
                let parentPath = url.deletingLastPathComponent().path
                let siblings = siblingNames(of: parentPath, cache: &siblingCache)
                guard siblings.contains(where: { ScanPolicy.isMacPlatformDirectoryName($0) }) else {
                    continue
                }
            }

            enumerator.skipDescendants()

            let size = sizeIndex.directorySize(url: url)
            guard size > 0 else { continue }

            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let platform = Self.platformLabel(for: lower)
            findings.append(ScanFinding(
                category: .developerPackageCaches,
                riskLevel: .safe,
                reason: "\(platform) native binaries in \(label) — unused on macOS (safe to remove whole folder)",
                path: url.path,
                sizeBytes: size,
                lastUsed: modDate,
                confidence: confidence
            ))
        }
        return findings
    }

    private func siblingNames(of parentPath: String, cache: inout [String: Set<String>]) -> Set<String> {
        if let cached = cache[parentPath] { return cached }
        let parent = URL(fileURLWithPath: parentPath)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parentPath) else {
            cache[parentPath] = []
            return []
        }
        // Only consider directory siblings.
        var dirs = Set<String>()
        for name in names {
            var isDir: ObjCBool = false
            let child = parent.appending(path: name).path
            if FileManager.default.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue {
                dirs.insert(name.lowercased())
            }
        }
        cache[parentPath] = dirs
        return dirs
    }

    private static func platformLabel(for directoryName: String) -> String {
        if directoryName.hasPrefix("win") || directoryName.hasPrefix("windows") {
            return "Windows"
        }
        return "Linux"
    }
}
