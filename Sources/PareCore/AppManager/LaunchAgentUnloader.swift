import Foundation

public enum LaunchAgentUnloadOutcome: Sendable, Equatable {
    case unloaded
    case notLoaded
    case failed(String)
}

public protocol LaunchAgentUnloading: Sendable {
    func unload(plistAt url: URL) async -> LaunchAgentUnloadOutcome
}

/// Boots a per-user agent out of `gui/<uid>` before its plist is trashed; a loaded job whose plist
/// is gone keeps relaunching until logout.
public struct LaunchctlAgentUnloader: LaunchAgentUnloading {
    /// `launchctl print` exit status for "Could not find service" in the domain.
    static let serviceNotFoundExitCode: Int32 = 113
    static let launchctlPath = "/bin/launchctl"
    static let timeoutSeconds: TimeInterval = 5

    /// Runs `launchctl` with the arguments; nil means it could not launch or timed out.
    public typealias Runner = @Sendable ([String]) async -> Int32?

    private let uid: uid_t
    private let run: Runner

    public init(uid: uid_t = getuid(), run: Runner? = nil) {
        self.uid = uid
        self.run = run ?? Self.runLaunchctl
    }

    private static let runLaunchctl: Runner = { arguments in
        await ToolCommandRunner(timeoutSeconds: timeoutSeconds).run(
            executable: URL(fileURLWithPath: launchctlPath),
            arguments: arguments
        )?.exitCode
    }

    public func unload(plistAt url: URL) async -> LaunchAgentUnloadOutcome {
        guard let label = Self.label(ofPlistAt: url) else {
            return .failed("Couldn't read the launch agent's label")
        }
        let service = "gui/\(uid)/\(label)"
        guard let printStatus = await run(["print", service]) else {
            return .failed("launchctl did not respond")
        }
        if printStatus == Self.serviceNotFoundExitCode { return .notLoaded }
        guard printStatus == 0 else { return .failed("launchctl print exited with \(printStatus)") }
        guard let code = await run(["bootout", service]) else {
            return .failed("launchctl did not respond")
        }
        return code == 0 ? .unloaded : .failed("launchctl bootout exited with \(code)")
    }

    static func label(ofPlistAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String,
              !label.isEmpty, !label.contains("/") else { return nil }
        return label
    }
}
