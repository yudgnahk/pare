import Foundation

// MARK: - Marker search

extension ScanPolicy {

    /// Same answer as `markers.contains { (orSuffix && path.hasSuffix($0)) || path.contains($0) }`.
    /// ASCII text without CR/LF has one Character per byte, so a byte search agrees with
    /// the Character-based `contains`; any other path or marker takes the original call.
    static func containsAnyMarker(_ path: String, _ markers: [String], orSuffix: Bool = false) -> Bool {
        let asciiResult: Bool?? = path.utf8.withContiguousStorageIfAvailable { pathBytes -> Bool? in
            guard pathBytes.allSatisfy({ $0 < 0x80 }) else { return nil }
            return markers.contains { marker in
                asciiContains(pathBytes, marker) ?? fallbackContains(path, marker, orSuffix: orSuffix)
            }
        }
        if let asciiResult = asciiResult ?? nil { return asciiResult }
        return markers.contains { fallbackContains(path, $0, orSuffix: orSuffix) }
    }

    private static func fallbackContains(_ path: String, _ marker: String, orSuffix: Bool) -> Bool {
        (orSuffix && path.hasSuffix(marker)) || path.contains(marker)
    }

    /// nil when the marker is empty, non-ASCII or holds CR/LF (where `\r\n` is one Character).
    private static func asciiContains(_ haystack: UnsafeBufferPointer<UInt8>, _ marker: String) -> Bool? {
        let result: Bool?? = marker.utf8.withContiguousStorageIfAvailable { needle -> Bool? in
            guard let first = needle.first,
                  needle.allSatisfy({ $0 < 0x80 && $0 != 0x0A && $0 != 0x0D }) else { return nil }
            guard needle.count <= haystack.count else { return false }
            for start in 0...(haystack.count - needle.count) where haystack[start] == first {
                if memcmp(haystack.baseAddress! + start, needle.baseAddress!, needle.count) == 0 { return true }
            }
            return false
        }
        return result ?? nil
    }
}
