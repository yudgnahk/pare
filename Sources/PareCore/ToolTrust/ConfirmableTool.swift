import Darwin
import Foundation

/// Third-party tools a scan or cleanup runs on its own, and only from a path the user confirmed.
public enum ConfirmableTool: String, CaseIterable, Codable, Sendable {
    case go
    case uv
    case pnpm

    public var executableName: String { rawValue }
}

/// File identity that changes whenever the file is rewritten, replaced or renamed over.
public struct ExecutableFingerprint: Codable, Equatable, Sendable {
    public let device: Int64
    public let inode: UInt64
    public let size: Int64
    public let modifiedSeconds: Int
    public let modifiedNanoseconds: Int
    public let changedSeconds: Int
    public let changedNanoseconds: Int

    /// Nil unless `path` itself (not a symlink) is a regular file.
    public static func current(atPath path: String) -> ExecutableFingerprint? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return ExecutableFingerprint(
            device: Int64(info.st_dev),
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            modifiedSeconds: info.st_mtimespec.tv_sec,
            modifiedNanoseconds: info.st_mtimespec.tv_nsec,
            changedSeconds: info.st_ctimespec.tv_sec,
            changedNanoseconds: info.st_ctimespec.tv_nsec
        )
    }
}

/// A user-confirmed executable: the symlink-resolved path and its identity at confirmation time.
public struct ConfirmedTool: Codable, Equatable, Sendable {
    public let path: String
    public let fingerprint: ExecutableFingerprint

    public init(path: String, fingerprint: ExecutableFingerprint) {
        self.path = path
        self.fingerprint = fingerprint
    }

    /// True while the file at `path` is still the one the user confirmed.
    public var isUnchanged: Bool {
        ExecutableFingerprint.current(atPath: path) == fingerprint
    }
}
