import Darwin
import Foundation

/// Filesystem proof that no repository encloses a directory. Git can't give it: its exit 128, and even its
/// "not a git repository" text, also cover corrupt, unreadable or half-deleted repositories.
enum GitRepositoryAbsence {
    private enum Entry {
        case absent, present, unknown
    }

    /// True only when `directory` exists and nothing on its physical path to `/` is, or may be, a repository.
    static func isProven(at directory: String) -> Bool {
        guard let real = realpath(directory, nil) else { return false }
        defer { free(real) }
        var current = String(cString: real)
        while true {
            guard holdsNoRepository(current) else { return false }
            if current == "/" { return true }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    private static func holdsNoRepository(_ directory: String) -> Bool {
        guard entry(directory + "/.git") == .absent else { return false }
        // A bare repository, or the inside of a git directory, has no `.git` entry of its own.
        let layout = ["HEAD", "objects", "refs"].map { entry(directory + "/" + $0) }
        guard !layout.contains(.unknown) else { return false }
        return layout[0] == .absent || (layout[1] == .absent && layout[2] == .absent)
    }

    /// `lstat`, so a dangling `.git` symlink still counts; any error but "no such entry" proves nothing.
    private static func entry(_ path: String) -> Entry {
        var info = stat()
        if lstat(path, &info) == 0 { return .present }
        return errno == ENOENT ? .absent : .unknown
    }
}
