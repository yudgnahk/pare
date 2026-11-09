import Darwin
import Foundation

/// Filesystem facts that git's answers about a candidate folder cannot be trusted without.
enum GitCandidateChecks {
    /// A `.git` inside the candidate makes it a repository of its own; any error but "no such entry" counts as present.
    static func holdsOwnGitEntry(_ directory: String) -> Bool {
        var info = stat()
        return lstat(directory + "/.git", &info) == 0 || errno != ENOENT
    }

    /// False when git's toplevel plus prefix (a `core.worktree` can point anywhere) is not this very folder.
    static func isInside(top: String, relative: String, directory: String) -> Bool {
        guard let expected = realPath(top + "/" + relative), let actual = realPath(directory) else { return false }
        return expected == actual
    }

    private static func realPath(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }
}
