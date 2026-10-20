import Darwin
import Foundation

/// Which running processes belong to macOS and what the user calls the rest.
public enum ProcessPolicy {
    static let systemPathPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"]
    /// Apple's bundled apps (Mail, Notes) can be quit and reopened like any other app.
    static let userFacingSystemPrefixes = ["/System/Applications/"]
    private static let pathBufferSize = 4 * Int(MAXPATHLEN) // PROC_PIDPATHINFO_MAXSIZE

    public static func isSystemExecutable(path: String) -> Bool {
        systemPathPrefixes.contains { path.hasPrefix($0) }
            && !userFacingSystemPrefixes.contains { path.hasPrefix($0) }
    }

    /// The outermost `.app` bundle's name, so Chrome's nested helpers read as "Google Chrome".
    public static func appDisplayName(path: String) -> String? {
        path.split(separator: "/").first { $0.hasSuffix(".app") }.map { String($0.dropLast(".app".count)) }
    }

    /// The process's executable path, or nil when it has exited or is not readable.
    public static func executablePath(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: pathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }
}
