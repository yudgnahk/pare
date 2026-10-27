import Darwin
import Foundation

/// Why a candidate cannot be confirmed; `message` is the short Settings copy.
public enum ToolRejection: Error, Equatable, Sendable {
    case notFound
    case notExecutable
    case script
    case notMachO
    case unreadable
    case loadsNonSystemLibrary(String)
    case setsDyldEnvironment

    public var message: String {
        switch self {
        case .notFound: return "Not found"
        case .notExecutable: return "Not an executable file"
        // A script loads files (node modules, corepack downloads) that a fingerprint cannot cover.
        case .script: return "Script launcher — install the standalone binary"
        case .notMachO: return "Not a macOS program"
        case .unreadable: return "Can't read this file"
        case .loadsNonSystemLibrary(let library):
            return "Loads \(URL(fileURLWithPath: library).lastPathComponent) from outside macOS"
        case .setsDyldEnvironment: return "Changes how macOS loads its libraries"
        }
    }
}

/// Decides whether an executable may be confirmed: a regular Mach-O file loading only system libraries.
public enum ToolVetting {
    public static func vet(path: String) -> Result<ConfirmedTool, ToolRejection> {
        guard let real = realpath(path, nil) else { return .failure(.notFound) }
        let resolved = String(cString: real)
        free(real)
        guard let fingerprint = ExecutableFingerprint.current(atPath: resolved),
              access(resolved, X_OK) == 0 else { return .failure(.notExecutable) }
        switch MachOLinkInspector.inspect(fileAt: resolved) {
        case .systemOnly: break
        case .script: return .failure(.script)
        case .notMachO: return .failure(.notMachO)
        case .malformed: return .failure(.unreadable)
        case .nonSystemLibrary(let library): return .failure(.loadsNonSystemLibrary(library))
        case .setsDyldEnvironment: return .failure(.setsDyldEnvironment)
        }
        let tool = ConfirmedTool(path: resolved, fingerprint: fingerprint)
        // Rewritten while we read it: the bytes we inspected may not be the bytes on disk.
        return tool.isUnchanged ? .success(tool) : .failure(.unreadable)
    }
}
