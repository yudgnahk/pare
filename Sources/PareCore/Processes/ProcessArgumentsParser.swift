import Foundation

/// Decodes a `KERN_PROCARGS2` buffer: argc, exec path, NUL padding, then argc NUL-terminated strings.
enum ProcessArgumentsParser {
    /// Caps a corrupt or hostile argc.
    static let maxArguments = 4096

    static func parse(_ bytes: UnsafeRawBufferPointer) -> [String]? {
        guard bytes.count > MemoryLayout<Int32>.size else { return nil }
        let argc = Int(bytes.loadUnaligned(as: Int32.self))
        guard argc > 0, argc <= maxArguments else { return nil }

        var index = MemoryLayout<Int32>.size
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        var arguments: [String] = []
        arguments.reserveCapacity(argc)
        while arguments.count < argc, index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            arguments.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments.isEmpty ? nil : arguments
    }

    static func parse(_ bytes: [UInt8]) -> [String]? {
        bytes.withUnsafeBytes { parse($0) }
    }
}
