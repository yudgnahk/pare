import Darwin
import Foundation

/// Direct children of a directory from `readdir`, typed by `d_type`: no per-entry attribute fetch.
/// Listing-only walks spent most of a scan in `getattrlistbulk` reading attributes they never used.
public enum DirectoryListing {
    public enum Kind: Sendable, Equatable {
        case directory, regularFile, symbolicLink, other
    }

    public struct Entry: Sendable, Equatable {
        public let name: String
        public let kind: Kind

        public init(name: String, kind: Kind) {
            self.name = name
            self.kind = kind
        }
    }

    public struct Listing: Sendable {
        /// The listed directory with symlinks resolved, as `FileManager` spells its children.
        public let directory: URL
        public let entries: [Entry]

        public func url(of entry: Entry) -> URL {
            directory.appendingPathComponent(entry.name, isDirectory: entry.kind == .directory)
        }
    }

    /// All children except `.` and `..`, in directory order; nil when `forEach` would return nil.
    public static func contents(of directory: URL) -> Listing? {
        var entries: [Entry] = []
        guard let resolved = forEach(in: directory, { entries.append($0); return true }) else { return nil }
        return Listing(directory: resolved, entries: entries)
    }

    /// Calls `body` per child until it returns false, and returns the resolved directory. Matches `FileManager`:
    /// nil when `directory` is itself a symlink or cannot be opened; `/var/…` resolves to `/private/var/…`.
    @discardableResult
    public static func forEach(in directory: URL, _ body: (Entry) -> Bool) -> URL? {
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        guard let stream = fdopendir(descriptor) else {
            close(descriptor)
            return nil
        }
        defer { closedir(stream) }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        let resolved = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let prefix = resolved.hasSuffix("/") ? resolved : resolved + "/"
        while let pointer = readdir(stream) {
            let length = Int(pointer.pointee.d_namlen)
            let name = withUnsafePointer(to: &pointer.pointee.d_name) { tuple in
                String(decoding: UnsafeRawBufferPointer(start: tuple, count: length), as: UTF8.self)
            }
            guard name != ".", name != ".." else { continue }
            let kind = kind(of: pointer.pointee.d_type) ?? lstatKind(prefix + name)
            guard body(Entry(name: name, kind: kind)) else { break }
        }
        return URL(fileURLWithPath: resolved, isDirectory: true)
    }

    private static func kind(of type: UInt8) -> Kind? {
        switch Int32(type) {
        case DT_DIR: return .directory
        case DT_REG: return .regularFile
        case DT_LNK: return .symbolicLink
        case DT_UNKNOWN: return nil
        default: return .other
        }
    }

    // Some filesystems (SMB, FUSE) report no type; `lstat` keeps symlinks un-followed, as the URL keys did.
    private static func lstatKind(_ path: String) -> Kind {
        var info = stat()
        guard lstat(path, &info) == 0 else { return .other }
        switch info.st_mode & S_IFMT {
        case S_IFDIR: return .directory
        case S_IFREG: return .regularFile
        case S_IFLNK: return .symbolicLink
        default: return .other
        }
    }
}
