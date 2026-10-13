import Foundation

/// Decoding shared by every `lsof -F` parser, so path keys match the paths findings use.
enum LsofFieldName {
    /// Without a UTF-8 locale (an app launched from Finder) lsof prints non-ASCII bytes as `\xNN`
    /// and a backslash as `\\`. Undecodable input is returned unchanged.
    static func unescaped(_ value: String) -> String {
        guard value.contains("\\") else { return value }
        let simple: [UInt8: UInt8] = [
            UInt8(ascii: "\\"): UInt8(ascii: "\\"), UInt8(ascii: "n"): 0x0A, UInt8(ascii: "t"): 0x09,
            UInt8(ascii: "r"): 0x0D, UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C,
        ]
        let input = Array(value.utf8)
        var bytes: [UInt8] = []
        var index = 0
        while index < input.count {
            let byte = input[index]
            guard byte == UInt8(ascii: "\\"), index + 1 < input.count else {
                bytes.append(byte)
                index += 1
                continue
            }
            let next = input[index + 1]
            if next == UInt8(ascii: "x"), index + 3 < input.count,
               let hex = UInt8(String(decoding: input[(index + 2)...(index + 3)], as: UTF8.self), radix: 16) {
                bytes.append(hex)
                index += 4
            } else if let mapped = simple[next] {
                bytes.append(mapped)
                index += 2
            } else {
                bytes.append(byte)
                index += 1
            }
        }
        return String(bytes: bytes, encoding: .utf8) ?? value
    }
}
