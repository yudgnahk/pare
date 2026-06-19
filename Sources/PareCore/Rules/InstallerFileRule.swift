import Foundation

/// Finds macOS installer files (.dmg, .pkg, .iso, .xip) in ~/Downloads, ~/Desktop, and
/// iCloud Drive, plus .zip files whose central directory contains a .app bundle or iOS
/// Payload/ folder. Files must be at least 7 days old.
///
/// Risk is `.review` — installer files may be intentionally kept, so the user must confirm.
public struct InstallerFileRule: ScanRule {
    public let id = "installer-files"
    public let title = "Installer Files"
    public let reason = "macOS installer — safe to remove after the app has been installed"
    public let category: ScanCategory = .installerFiles
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.80

    // 7 days — gives users time to install before the file is flagged.
    static let minimumAgeSeconds: TimeInterval = 7 * 24 * 60 * 60

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Downloads"),
            environment.homeDirectory.appending(path: "Desktop"),
            // User-visible iCloud Drive root (com~apple~CloudDocs is the canonical container).
            environment.homeDirectory.appending(path: "Library/Mobile Documents/com~apple~CloudDocs"),
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let ext = fileURL.pathExtension.lowercased()

        // ZIP files require binary inspection to confirm they contain an app bundle.
        if ext == "zip" {
            guard ScanPolicy.passesMinimumAge(for: resourceValues, minimumAgeSeconds: Self.minimumAgeSeconds) else {
                return false
            }
            return Self.isInstallerZip(at: fileURL)
        }

        guard ScanPolicy.installerExtensions.contains(ext) else { return false }
        // Bypass isLowImpactPath — installer files live in protected paths by design.
        // Safety is maintained by extension filtering + age gate + .review risk level.
        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: Self.minimumAgeSeconds
        )
    }

    /// Returns true when `url` is a ZIP file whose central directory contains an entry
    /// named `*.app/<anything>` (macOS app bundle) or starting with `Payload/` (iOS IPA).
    /// Uses EOCD-located central directory parsing — no full file read required.
    static func isInstallerZip(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { handle.closeFile() }

        // Step 1: verify PK local-file-header magic.
        let magic = handle.readData(ofLength: 4)
        guard magic.count == 4,
              magic[0] == 0x50, magic[1] == 0x4B,
              magic[2] == 0x03, magic[3] == 0x04 else { return false }

        // Step 2: find EOCD by scanning backwards (max ZIP comment = 65535 bytes).
        let fileSize = handle.seekToEndOfFile()
        guard fileSize >= 22 else { return false }
        let searchSize = min(fileSize, UInt64(22 + 65535))
        handle.seek(toFileOffset: fileSize - searchSize)
        let tail = handle.readData(ofLength: Int(searchSize))

        var cdOffset: UInt32?
        for i in stride(from: tail.count - 22, through: 0, by: -1) {
            if tail[i] == 0x50 && tail[i+1] == 0x4B && tail[i+2] == 0x05 && tail[i+3] == 0x06 {
                cdOffset = UInt32(tail[i+16])
                         | UInt32(tail[i+17]) << 8
                         | UInt32(tail[i+18]) << 16
                         | UInt32(tail[i+19]) << 24
                break
            }
        }
        guard let cdStart = cdOffset else { return false }

        // Step 3: read central directory entries and look for .app/ or Payload/.
        handle.seek(toFileOffset: UInt64(cdStart))
        let cdData = handle.readData(ofLength: 512 * 1024)

        var pos = 0
        while pos + 46 <= cdData.count {
            guard cdData[pos] == 0x50 && cdData[pos+1] == 0x4B &&
                  cdData[pos+2] == 0x01 && cdData[pos+3] == 0x02 else {
                pos += 1
                continue
            }
            let nameLen  = Int(cdData[pos+28]) | Int(cdData[pos+29]) << 8
            let extraLen = Int(cdData[pos+30]) | Int(cdData[pos+31]) << 8
            let cmtLen   = Int(cdData[pos+32]) | Int(cdData[pos+33]) << 8
            guard pos + 46 + nameLen <= cdData.count else { break }
            if let name = String(bytes: cdData[(pos+46)..<(pos+46+nameLen)], encoding: .utf8) {
                if name.contains(".app/") || name.hasPrefix("Payload/") { return true }
            }
            pos += 46 + nameLen + extraLen + cmtLen
        }
        return false
    }
}
