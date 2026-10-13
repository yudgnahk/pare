import XCTest
@testable import PareCore

final class MarkerSearchTests: XCTestCase {

    private static let paths: [String] = [
        "",
        "/users/k/library/caches/com.apple.spotlight/x",
        "/users/k/library/application support/code/user/workspacestorage/abc/state.vscdb",
        "/users/k/library/caches/go-build/ab/cd",
        "/users/k/.ssh/id_ed25519",
        "/private/var/folders/ab/t/tmp.123",
        "/users/k/library/caches/caf\u{E9}/cache.db",
        "/users/k/library/caches/cafe\u{301}/cache.db",
        "/users/k/library/caches\u{301}/x",
        "/users/k/library/cache\u{301}s/x",
        "/users/k/\u{600}/library/caches/x",
        "/users/k/tmp\r\n/library/caches/x",
        "/users/k/a\r/library/caches/\nb",
        "/users/k/\u{1F468}\u{200D}\u{1F4BB}/library/caches/x",
        "/users/k/library/caches/x\u{200D}",
        "/users/k/library/caches/i\u{307}stanbul",
        "library/caches",
        "/library/caches/",
    ]

    private static let edgeMarkers: [String] = [
        "", "/library/caches", "/library/caches/", "caches", "caf\u{E9}", "cafe\u{301}",
        "\u{E9}", "s", "\r", "\n", "\r\n", "a\r", "\nb", "/tmp\r", "/users/k/library/caches/x",
    ]

    private static var markerLists: [(name: String, markers: [String])] {
        [
            ("searchIndexSensitivePathMarkers", ScanPolicy.searchIndexSensitivePathMarkers),
            ("lowImpactMarkers", ScanPolicy.lowImpactMarkers),
            ("protectedPathMarkers", ScanPolicy.protectedPathMarkers),
            ("sensitiveDataMarkers", ScanPolicy.sensitiveDataMarkers),
            ("appStateSensitiveMarkers", ScanPolicy.appStateSensitiveMarkers),
            ("developerReviewPathMarkers", ScanPolicy.developerReviewPathMarkers),
            ("personaProtectedPathOverrides", ScanPolicy.personaProtectedPathOverrides),
            ("vscodeReviewStateMarkers", ScanPolicy.vscodeReviewStateMarkers),
            ("developerReviewExclusionMarkers", ScanPolicy.developerReviewExclusionMarkers),
            ("reconstructibleCachePathMarkers", ScanPolicy.reconstructibleCachePathMarkers),
        ] + edgeMarkers.map { ("edge \($0.debugDescription)", [$0]) }
    }

    func testMatchesCharacterBasedContainsForEveryMarker() {
        for list in Self.markerLists {
            for marker in list.markers {
                for path in Self.paths + Self.markerPaths(marker) {
                    for orSuffix in [false, true] {
                        let expected = (orSuffix && path.hasSuffix(marker)) || path.contains(marker)
                        XCTAssertEqual(
                            ScanPolicy.containsAnyMarker(path, [marker], orSuffix: orSuffix), expected,
                            "\(list.name) \(marker.debugDescription) in \(path.debugDescription) orSuffix=\(orSuffix)"
                        )
                    }
                }
            }
        }
    }

    func testMatchesCharacterBasedContainsForWholeLists() {
        for list in Self.markerLists {
            for path in Self.paths + list.markers.flatMap(Self.markerPaths) {
                XCTAssertEqual(
                    ScanPolicy.containsAnyMarker(path, list.markers),
                    list.markers.contains { path.contains($0) },
                    "\(list.name) in \(path.debugDescription)"
                )
                XCTAssertEqual(
                    ScanPolicy.containsAnyMarker(path, list.markers, orSuffix: true),
                    list.markers.contains { path.hasSuffix($0) || path.contains($0) },
                    "\(list.name) orSuffix in \(path.debugDescription)"
                )
            }
        }
    }

    // A marker embedded as a suffix, mid-path, and next to a combining mark or CR/LF.
    private static func markerPaths(_ marker: String) -> [String] {
        [
            "/users/k" + marker,
            "/users/k" + marker + "/x",
            "/users/k" + marker + "\u{301}/x",
            "/users/k\u{600}" + marker,
            "/users/k\r" + marker,
            "/users/k" + marker + "\n",
            marker,
        ]
    }
}
