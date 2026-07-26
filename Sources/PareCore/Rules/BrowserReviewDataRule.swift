import Foundation

/// Scans browser personal data — history databases, cookies, form data, IndexedDB,
/// and WebSQL — for Safari, Chrome, Firefox, Brave, Edge, Arc, and Opera.
///
/// All findings are `.review` (personal data; user must confirm via Deep Clean).
/// 30-day minimum age gate avoids surfacing data from current browsing sessions.
///
/// Distinct from `BrowserCachesRule` (which stays `.safe` for render/GPU caches)
/// so users can clean caches automatically without being forced to review history.
public struct BrowserReviewDataRule: ScanRule {
    public let id = "browser-review-data"
    public let title = "Browser Personal Data"
    public let reason = "Browser history, cookies, or form data (personal data)"
    public let category: ScanCategory = .browserCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.88

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] { [] }
    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool { false }

    public func customScan(environment: ScanEnvironment) async -> [ScanFinding]? {
        let home = environment.homeDirectory
        var findings: [ScanFinding] = []

        // -- Safari --
        let safariPaths: [(String, String)] = [
            ("Library/Safari/History.db", "Safari browsing history"),
            ("Library/Safari/Cookies.binarycookies", "Safari cookies"),
            ("Library/Safari/Databases", "Safari WebSQL databases"),
            ("Library/Safari/LocalStorage", "Safari local storage / IndexedDB"),
        ]
        for (relPath, reason) in safariPaths {
            findings += fileFindings(at: home.appending(path: relPath), reason: reason)
        }

        // -- Chromium-based browsers --
        let chromiumBrowsers: [(String, String)] = [
            ("Library/Application Support/Google/Chrome", "Chrome"),
            ("Library/Application Support/BraveSoftware/Brave-Browser", "Brave"),
            ("Library/Application Support/Microsoft Edge", "Edge"),
            ("Library/Application Support/Arc/User Data", "Arc"),
            ("Library/Application Support/com.operasoftware.Opera", "Opera"),
        ]
        let chromiumFiles: [(String, String)] = [
            ("Default/History", "browsing history"),
            ("Default/Cookies", "cookies"),
            ("Default/Web Data", "autofill form data"),
            ("Default/IndexedDB", "IndexedDB"),
            ("Default/databases", "WebSQL databases"),
        ]
        for (browserBase, browserName) in chromiumBrowsers {
            for (relFile, dataType) in chromiumFiles {
                let relPath = "\(browserBase)/\(relFile)"
                let reason = "\(browserName) \(dataType)"
                findings += artifactFindings(
                    at: home.appending(path: relPath),
                    reason: reason,
                    sizeIndex: environment.sizeIndex
                )
            }
        }

        // -- Firefox --
        let firefoxProfiles = home.appending(path: "Library/Application Support/Firefox/Profiles")
        if FileManager.default.fileExists(atPath: firefoxProfiles.path) {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: firefoxProfiles,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let profileDirs = contents.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            for profile in profileDirs {
                let firefoxFiles: [(String, String)] = [
                    ("places.sqlite", "Firefox history + bookmarks"),
                    ("cookies.sqlite", "Firefox cookies"),
                    ("webappsstore.sqlite", "Firefox local storage"),
                    ("indexedDB", "Firefox IndexedDB"),
                ]
                for (relFile, reason) in firefoxFiles {
                    findings += artifactFindings(
                        at: profile.appending(path: relFile),
                        reason: reason,
                        sizeIndex: environment.sizeIndex
                    )
                }
            }
        }

        return findings
    }

    // MARK: - Private helpers

    private func fileFindings(at url: URL, reason: String) -> [ScanFinding] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = FileSystemUtils.fileSize(url: url)
        guard size > 0 else { return [] }

        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let lastUsed = resourceValues?.contentModificationDate

        if let date = lastUsed,
           Date().timeIntervalSince(date) < 30 * 24 * 60 * 60 {
            return []
        }

        return [ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            path: url.path,
            sizeBytes: size,
            lastUsed: lastUsed,
            confidence: confidence
        )]
    }

    private func artifactFindings(
        at url: URL,
        reason: String,
        sizeIndex: DirectorySizeIndex
    ) -> [ScanFinding] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
        let isDir = resourceValues?.isDirectory ?? false
        let size = isDir ? sizeIndex.directorySize(url: url) : FileSystemUtils.fileSize(url: url)
        guard size > 0 else { return [] }

        let lastUsed = resourceValues?.contentModificationDate

        if let date = lastUsed,
           Date().timeIntervalSince(date) < 30 * 24 * 60 * 60 {
            return []
        }

        return [ScanFinding(
            category: category,
            riskLevel: riskLevel,
            reason: reason,
            path: url.path,
            sizeBytes: size,
            lastUsed: lastUsed,
            confidence: confidence
        )]
    }
}
