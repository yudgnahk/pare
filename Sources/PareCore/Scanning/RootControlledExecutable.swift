import Darwin
import Foundation

/// An executable only root can replace: it and every ancestor directory are root-owned and not group-
/// or world-writable. Same-user code cannot swap such a binary to borrow Pare's Full Disk Access.
public enum RootControlledExecutable {
    /// The symlink-resolved path to launch, or nil when the file is missing or anyone but root could change it.
    public static func resolve(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        let resolved = String(cString: real)
        var info = stat()
        guard stat(resolved, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o111 != 0,
              isRootControlled(info) else { return nil }
        var directory = URL(fileURLWithPath: resolved).deletingLastPathComponent()
        while true {
            guard stat(directory.path, &info) == 0, isRootControlled(info) else { return nil }
            if directory.path == "/" { return resolved }
            directory = directory.deletingLastPathComponent()
        }
    }

    private static func isRootControlled(_ info: stat) -> Bool {
        info.st_uid == 0 && info.st_mode & (S_IWGRP | S_IWOTH) == 0
    }
}
