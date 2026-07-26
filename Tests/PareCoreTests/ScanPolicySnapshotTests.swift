import XCTest
@testable import PareCore

/// R1.7 guard: the ScanPolicy file split must be pure movement — these digests
/// pin every marker collection's exact contents. If a split (or any later edit)
/// changes a list, the digest changes and this test fails loudly.
final class ScanPolicySnapshotTests: XCTestCase {

    /// FNV-1a over the sorted, newline-joined entries — stable across processes.
    private func digest(_ entries: [String]) -> String {
        let joined = entries.sorted().joined(separator: "\n")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in joined.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash) + ":\(entries.count)"
    }

    private var collections: [(name: String, entries: [String])] {
        [
            ("reconstructibleCachePathMarkers", ScanPolicy.reconstructibleCachePathMarkers),
            ("searchIndexSensitivePathMarkers", ScanPolicy.searchIndexSensitivePathMarkers),
            ("searchIndexSensitiveCacheFolderNames", Array(ScanPolicy.searchIndexSensitiveCacheFolderNames)),
            ("userCachesExcludedTopLevelFolderNames", Array(ScanPolicy.userCachesExcludedTopLevelFolderNames)),
            ("vscodeReviewStateMarkers", ScanPolicy.vscodeReviewStateMarkers),
            ("jetBrainsReviewRequiredMarkerPairs", ScanPolicy.jetBrainsReviewRequiredMarkerPairs.map { $0.ide + "|" + $0.subtree }),
            ("projectDiscoveryExcludedPathComponents", ScanPolicy.projectDiscoveryExcludedPathComponents),
            ("designerSafePathMarkers", ScanPolicy.designerSafePathMarkers),
            ("designerReviewPathMarkers", ScanPolicy.designerReviewPathMarkers),
            ("videoBuilderSafePathMarkers", ScanPolicy.videoBuilderSafePathMarkers),
            ("videoBuilderReviewPathMarkers", ScanPolicy.videoBuilderReviewPathMarkers),
            ("developerSafePathMarkers", ScanPolicy.developerSafePathMarkers),
            ("aiToolSafePathMarkers", ScanPolicy.aiToolSafePathMarkers),
            ("installerExtensions", Array(ScanPolicy.installerExtensions)),
            ("developerReviewPathMarkers", ScanPolicy.developerReviewPathMarkers),
            ("developerDockerReviewPathMarkers", ScanPolicy.developerDockerReviewPathMarkers),
            ("developerDockerSafePathMarkers", ScanPolicy.developerDockerSafePathMarkers),
            ("developerDockerAdvancedPathMarkers", ScanPolicy.developerDockerAdvancedPathMarkers),
            ("browserExtendedSafePathMarkers", ScanPolicy.browserExtendedSafePathMarkers),
            ("browserReviewDataPathMarkers", ScanPolicy.browserReviewDataPathMarkers),
            ("mobileSyncBackupPathMarkers", ScanPolicy.mobileSyncBackupPathMarkers),
            ("productivitySafePathMarkers", ScanPolicy.productivitySafePathMarkers),
            ("productivityReviewPathMarkers", ScanPolicy.productivityReviewPathMarkers),
            ("launchAgentPathMarkers", ScanPolicy.launchAgentPathMarkers),
            ("browserExtendedReviewPathMarkers", ScanPolicy.browserExtendedReviewPathMarkers),
            ("projectDependencyDirectoryNames", Array(ScanPolicy.projectDependencyDirectoryNames)),
            ("projectLocalArtifactDirectoryNames", Array(ScanPolicy.projectLocalArtifactDirectoryNames)),
            ("developerPackageCacheMarkers", ScanPolicy.developerPackageCacheMarkers),
            ("projectRootMarkerFileNames", ScanPolicy.projectRootMarkerFileNames),
            ("developerReviewExclusionMarkers", ScanPolicy.developerReviewExclusionMarkers),
            ("windowsExecutableExtensions", Array(ScanPolicy.windowsExecutableExtensions)),
            ("linuxExecutableExtensions", Array(ScanPolicy.linuxExecutableExtensions)),
            ("nonMacPlatformDirectoryNames", Array(ScanPolicy.nonMacPlatformDirectoryNames)),
            ("macPlatformDirectoryNames", Array(ScanPolicy.macPlatformDirectoryNames)),
            ("wrongPlatformScanRootRelativePaths", ScanPolicy.wrongPlatformScanRootRelativePaths),
        ]
    }

    /// Set GENERATE=1 to print the expected-digest table for regeneration.
    func testMarkerCollectionsMatchSnapshot() {
        if ProcessInfo.processInfo.environment["GENERATE_SCANPOLICY_SNAPSHOT"] == "1" {
            for c in collections {
                print("SNAPSHOT \"\(c.name)\": \"\(digest(c.entries))\",")
            }
            return
        }

        for c in collections {
            guard let expectedDigest = Self.expected[c.name] else {
                XCTFail("No snapshot recorded for \(c.name) — regenerate the table")
                continue
            }
            XCTAssertEqual(
                digest(c.entries), expectedDigest,
                "\(c.name) content changed — if intentional, regenerate the snapshot table"
            )
        }
        XCTAssertEqual(collections.count, Self.expected.count, "collection list and snapshot table out of sync")
    }

    private static let expected: [String: String] = [
        "reconstructibleCachePathMarkers": "3910e7fdc10ae240:17",
        "searchIndexSensitivePathMarkers": "ac84191a36afc32d:9",
        "searchIndexSensitiveCacheFolderNames": "1737a9b796cd51c1:4",
        "userCachesExcludedTopLevelFolderNames": "069a2f01a3418d96:22",
        "vscodeReviewStateMarkers": "482a7e5f4534ce6b:2",
        "jetBrainsReviewRequiredMarkerPairs": "5308136415fc9116:3",
        "projectDiscoveryExcludedPathComponents": "bf22ca4eb106f8ac:10",
        "designerSafePathMarkers": "bf2ef8148db8d02e:6",
        "designerReviewPathMarkers": "cf0e25253da2a0d9:3",
        "videoBuilderSafePathMarkers": "f1552664f44c2a7d:5",
        "videoBuilderReviewPathMarkers": "0a67ad09c4b0762c:5",
        "developerSafePathMarkers": "8de6508225c65e82:4",
        "aiToolSafePathMarkers": "ec9311aaccd7135d:10",
        "installerExtensions": "ac036c6fb36af3b3:4",
        "developerReviewPathMarkers": "4e4b2d2406ddd263:17",
        "developerDockerReviewPathMarkers": "007eb9443682cca8:2",
        "developerDockerSafePathMarkers": "328649fc99388bdb:3",
        "developerDockerAdvancedPathMarkers": "5e4194b6b3b1dd25:3",
        "browserExtendedSafePathMarkers": "61e538fd8f83626d:12",
        "browserReviewDataPathMarkers": "a93d580895cac6d8:29",
        "mobileSyncBackupPathMarkers": "cd517c2b83fdb9bc:1",
        "productivitySafePathMarkers": "c7e57a338e0f7160:14",
        "productivityReviewPathMarkers": "b35a18fe9efc599a:1",
        "launchAgentPathMarkers": "9a83f54eeb03d9e8:1",
        "browserExtendedReviewPathMarkers": "51b1ec4db03e22e3:20",
        "projectDependencyDirectoryNames": "3571220bfbcb3fc7:4",
        "projectLocalArtifactDirectoryNames": "292d813868da67ad:17",
        "developerPackageCacheMarkers": "1bc7bd2abe3d3197:21",
        "projectRootMarkerFileNames": "1a8503ec31fdcde0:11",
        "developerReviewExclusionMarkers": "3a6c7b4459b1d383:6",
        "windowsExecutableExtensions": "650e196d02e9232c:3",
        "linuxExecutableExtensions": "a5e94159c9f04267:3",
        "nonMacPlatformDirectoryNames": "81fedb75dd69777b:12",
        "macPlatformDirectoryNames": "e12ced4ef61e7ace:14",
        "wrongPlatformScanRootRelativePaths": "c2c450e4bf70fee3:6",
    ]
}
