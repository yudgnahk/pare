import Foundation

/// Reads a Mach-O executable's load commands (every slice of a fat file) to tell whether it loads
/// only SIP-protected system libraries, so nothing user-writable runs inside it.
public enum MachOLinkInspector {
    public enum Verdict: Equatable, Sendable {
        case systemOnly
        case script
        case notMachO
        case malformed
        case nonSystemLibrary(String)
        case setsDyldEnvironment
    }

    /// Reads `length` bytes at `offset`, or nil when the file is shorter.
    typealias Reader = (_ offset: UInt64, _ length: Int) -> Data?

    static let systemLibraryPrefixes = ["/usr/lib/", "/System/Library/"]
    static let dyldPath = "/usr/lib/dyld"
    static let maxLoadCommandBytes = 4 << 20
    static let maxFatSlices = 16

    private static let fatMagic: UInt32 = 0xCAFE_BABE
    private static let fatMagic64: UInt32 = 0xCAFE_BABF
    private static let machMagic: UInt32 = 0xFEED_FACE
    private static let machMagic64: UInt32 = 0xFEED_FACF
    private static let executeFileType: UInt32 = 0x2
    private static let dylibCommands: Set<UInt32> = [0xC, 0x20, 0x8000_0018, 0x8000_001F, 0x8000_0023]
    private static let loadDylinker: UInt32 = 0xE
    private static let dyldEnvironment: UInt32 = 0x27

    public static func inspect(fileAt path: String) -> Verdict {
        guard let handle = FileHandle(forReadingAtPath: path) else { return .malformed }
        defer { try? handle.close() }
        return inspect { offset, length in
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: length), data.count == length else { return nil }
            return data
        }
    }

    static func inspect(data: Data) -> Verdict {
        inspect { offset, length in
            let start = Int(clamping: offset)
            guard start <= data.count, length <= data.count - start else { return nil }
            return data.subdata(in: data.startIndex + start ..< data.startIndex + start + length)
        }
    }

    static func inspect(_ read: Reader) -> Verdict {
        guard let head = read(0, 8) else { return .notMachO }
        if head.prefix(2) == Data("#!".utf8) { return .script }
        switch head.uint32(at: 0, bigEndian: true) {
        case fatMagic: return inspectFat(read, wide: false, sliceCount: head.uint32(at: 4, bigEndian: true))
        case fatMagic64: return inspectFat(read, wide: true, sliceCount: head.uint32(at: 4, bigEndian: true))
        default: return inspectSlice(read, at: 0)
        }
    }

    private static func inspectFat(_ read: Reader, wide: Bool, sliceCount: UInt32) -> Verdict {
        // Java class files share the fat magic; their "count" is a version number far above any real slice count.
        guard sliceCount > 0, sliceCount <= maxFatSlices else { return .notMachO }
        let entrySize = wide ? 32 : 20
        guard let table = read(8, Int(sliceCount) * entrySize) else { return .malformed }
        for index in 0 ..< Int(sliceCount) {
            let base = index * entrySize
            let offset = wide ? table.uint64(at: base + 8) : UInt64(table.uint32(at: base + 8, bigEndian: true))
            let verdict = inspectSlice(read, at: offset)
            guard verdict == .systemOnly else { return verdict == .notMachO ? .malformed : verdict }
        }
        return .systemOnly
    }

    private static func inspectSlice(_ read: Reader, at offset: UInt64) -> Verdict {
        guard let header = read(offset, 28) else { return .notMachO }
        let magic = header.uint32(at: 0, bigEndian: false)
        guard magic == machMagic || magic == machMagic64 else { return .notMachO }
        guard header.uint32(at: 12, bigEndian: false) == executeFileType else { return .malformed }
        let commandCount = Int(header.uint32(at: 16, bigEndian: false))
        let commandBytes = Int(header.uint32(at: 20, bigEndian: false))
        guard commandBytes <= maxLoadCommandBytes,
              let commands = read(offset + (magic == machMagic64 ? 32 : 28), commandBytes) else { return .malformed }
        return inspectLoadCommands(commands, count: commandCount)
    }

    private static func inspectLoadCommands(_ commands: Data, count: Int) -> Verdict {
        var cursor = 0
        for _ in 0 ..< count {
            guard cursor + 8 <= commands.count else { return .malformed }
            let command = commands.uint32(at: cursor, bigEndian: false)
            let size = Int(commands.uint32(at: cursor + 4, bigEndian: false))
            guard size >= 8, size % 4 == 0, cursor + size <= commands.count else { return .malformed }
            let body = commands.subdata(in: commands.startIndex + cursor ..< commands.startIndex + cursor + size)
            if command == dyldEnvironment { return .setsDyldEnvironment }
            if dylibCommands.contains(command) || command == loadDylinker {
                guard let name = body.loadCommandString() else { return .malformed }
                let allowed = command == loadDylinker ? name == dyldPath : isSystemLibrary(name)
                if !allowed { return .nonSystemLibrary(name) }
            }
            cursor += size
        }
        return .systemOnly
    }

    static func isSystemLibrary(_ path: String) -> Bool {
        systemLibraryPrefixes.contains { path.hasPrefix($0) }
            && !path.split(separator: "/").contains { $0 == ".." || $0 == "." }
    }
}

private extension Data {
    func uint32(at offset: Int, bigEndian: Bool) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let value = self[startIndex + offset ..< startIndex + offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return bigEndian ? value : value.byteSwapped
    }

    func uint64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        return self[startIndex + offset ..< startIndex + offset + 8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    /// The `lc_str` at offset 8 of a dylib or dylinker command, NUL-terminated inside the command.
    func loadCommandString() -> String? {
        let nameOffset = Int(uint32(at: 8, bigEndian: false))
        guard nameOffset >= 12, nameOffset < count else { return nil }
        let bytes = self[(startIndex + nameOffset)...].prefix { $0 != 0 }
        guard startIndex + nameOffset + bytes.count < endIndex else { return nil }
        return String(data: Data(bytes), encoding: .utf8)
    }
}
