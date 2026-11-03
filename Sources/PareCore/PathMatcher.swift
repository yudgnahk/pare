/// Substring tests over a lowercased path; ASCII paths use a byte search, others the grapheme-aware `String.contains`.
struct PathMatcher {
    private let text: String
    private let asciiBytes: [UInt8]?

    init(_ lowered: String) {
        text = lowered
        let bytes = Array(lowered.utf8)
        asciiBytes = bytes.allSatisfy { $0 < 0x80 } ? bytes : nil
    }

    func has(_ needle: StaticString) -> Bool {
        guard let asciiBytes else { return text.contains(String(describing: needle)) }
        return needle.withUTF8Buffer { Self.containsBytes(asciiBytes, $0) }
    }

    private static func containsBytes(_ haystack: [UInt8], _ needle: UnsafeBufferPointer<UInt8>) -> Bool {
        let needleCount = needle.count
        guard needleCount > 0 else { return true }
        guard haystack.count >= needleCount else { return false }
        let first = needle[0]
        let lastStart = haystack.count - needleCount
        var start = 0
        while start <= lastStart {
            if haystack[start] == first {
                var offset = 1
                while offset < needleCount, haystack[start + offset] == needle[offset] { offset += 1 }
                if offset == needleCount { return true }
            }
            start += 1
        }
        return false
    }
}
