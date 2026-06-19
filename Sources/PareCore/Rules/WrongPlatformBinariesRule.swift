import Foundation

/// Detects binaries and installers built for non-macOS platforms that are completely
/// inert on macOS and can be safely removed after user review.
///
/// **Downloads** — `.exe`, `.msi`, `.dll`, `.deb`, `.rpm`, `.AppImage` files found
/// at the top level of `~/Downloads`. These are typically Windows or Linux installers
/// a user downloaded while researching software but cannot run natively on macOS.
///
/// **JetBrains plugin native stubs** — `win/`, `linux/`, and similar subdirectories
/// that JetBrains IDEs bundle inside every plugin's native-library tree. Only the
/// `mac/` or `osx/` variant is loaded at runtime; the other platform trees are dead
/// weight and can accumulate to tens of MB per IDE version.
public struct WrongPlatformBinariesRule: ScanRule {
    public let id = "wrong-platform-binaries"
    public let title = "Non-macOS Platform Binaries"
    public let reason = "Binary or installer built for Windows or Linux — cannot run on macOS"
    public let category: ScanCategory = .temporaryFiles
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.93

    // Reuse the canonical sets from ScanPolicy so there's one source of truth.
    private static var windowsExts: Set<String> { ScanPolicy.windowsExecutableExtensions }
    private static var linuxExts: Set<String> { ScanPolicy.linuxExecutableExtensions }

    // Directory names inside JetBrains plugin trees that hold non-macOS native stubs.
    private static let nonMacPlatformDirs: Set<String> = [
        "win", "win32", "win64", "windows",
        "linux", "linux-x86_64", "linux-aarch64", "linux-arm64",
        "linux-x86", "linux_x64", "linux_aarch64"
    ]

    // Only bother reporting downloads larger than this — tiny stubs aren't worth the noise.
    private static let downloadsMinBytes: Int64 = 512 * 1024

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        var findings: [ScanFinding] = []

        findings += scanDownloads(in: environment.homeDirectory.appending(path: "Downloads"))
        findings += scanJetBrainsPluginNatives(
            in: environment.homeDirectory.appending(path: "Library/Application Support/JetBrains")
        )

        return findings
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
                riskLevel: .review,
                reason: "\(platform) \(ext.uppercased()) — not executable on macOS",
                path: url.path,
                sizeBytes: size,
                lastUsed: res?.contentModificationDate,
                confidence: confidence
            ))
        }
        return findings
    }

    // MARK: - JetBrains plugin native stubs

    private func scanJetBrainsPluginNatives(in jetbrainsDir: URL) -> [ScanFinding] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: jetbrainsDir.path) else { return [] }

        guard let ideDirs = try? fm.contentsOfDirectory(
            at: jetbrainsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var findings: [ScanFinding] = []
        for ideDir in ideDirs {
            guard (try? ideDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            // Toolbox manages app installs separately; don't recurse into it here.
            guard ideDir.lastPathComponent.lowercased() != "toolbox" else { continue }

            let pluginsDir = ideDir.appending(path: "plugins")
            guard fm.fileExists(atPath: pluginsDir.path) else { continue }

            findings += findPlatformStubDirs(under: pluginsDir, ideLabel: ideDir.lastPathComponent)
        }
        return findings
    }

    /// Walks a plugin directory tree and reports every `win/`, `linux/`, etc.
    /// subdirectory as one finding. Calls `skipDescendants()` on each match so
    /// nested directories inside are never double-counted.
    private func findPlatformStubDirs(under root: URL, ideLabel: String) -> [ScanFinding] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var findings: [ScanFinding] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = url.lastPathComponent.lowercased()
            guard Self.nonMacPlatformDirs.contains(name) else { continue }

            enumerator.skipDescendants()

            let size = FileSystemUtils.directorySize(url: url)
            guard size > 0 else { continue }

            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let platform = name.hasPrefix("win") ? "Windows" : "Linux"
            findings.append(ScanFinding(
                category: .developerPackageCaches,
                riskLevel: .review,
                reason: "\(platform) native plugin stubs in \(ideLabel) — unused on macOS",
                path: url.path,
                sizeBytes: size,
                lastUsed: modDate,
                confidence: confidence
            ))
        }
        return findings
    }
}
