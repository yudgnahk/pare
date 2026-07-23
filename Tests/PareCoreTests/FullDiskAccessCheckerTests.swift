import XCTest
@testable import PareCore

final class FullDiskAccessCheckerTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    private var notFound: NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT), userInfo: nil)
    }

    func testUnknownWhenNoProbePathsExist() {
        let status = FullDiskAccessChecker.status(
            homeDirectory: home,
            relativePaths: ["Library/Safari", "Library/Mail"],
            fileExists: { _ in false },
            listDirectory: { _ in throw self.notFound }
        )
        XCTAssertEqual(status, .unknown)
    }

    func testGrantedWhenExistingProbesAreListable() {
        let status = FullDiskAccessChecker.status(
            homeDirectory: home,
            relativePaths: ["Library/Safari", "Library/Missing"],
            fileExists: { $0.path.hasSuffix("Library/Safari") },
            listDirectory: { url in
                if url.path.hasSuffix("Library/Missing") {
                    throw self.notFound
                }
                XCTAssertTrue(url.path.hasSuffix("Library/Safari"))
                return ["History.db"]
            }
        )
        XCTAssertEqual(status, .granted)
    }

    func testDeniedWhenAnyExistingProbeIsPermissionDenied() {
        let denied = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EACCES),
            userInfo: nil
        )
        let status = FullDiskAccessChecker.status(
            homeDirectory: home,
            relativePaths: ["Library/Safari", "Library/Mail"],
            fileExists: { _ in true },
            listDirectory: { url in
                if url.path.hasSuffix("Library/Mail") {
                    throw denied
                }
                return []
            }
        )
        XCTAssertEqual(status, .denied)
    }

    func testDeniedOnCocoaPermissionError() {
        let denied = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: nil
        )
        let status = FullDiskAccessChecker.status(
            homeDirectory: home,
            relativePaths: ["Library/Messages"],
            fileExists: { _ in true },
            listDirectory: { _ in throw denied }
        )
        XCTAssertEqual(status, .denied)
    }

    func testDeniedOnUnderlyingPOSIXPermissionError() {
        let posix = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EPERM),
            userInfo: nil
        )
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSUnderlyingErrorKey: posix]
        )
        let status = FullDiskAccessChecker.status(
            homeDirectory: home,
            relativePaths: ["Library/Safari"],
            fileExists: { _ in true },
            listDirectory: { _ in throw wrapped }
        )
        XCTAssertEqual(status, .denied)
    }

    func testDeniedWhenListFailsWithPermissionEvenIfFileExistsFalse() {
        // TCC can mask protected paths as non-existent while list still returns EPERM.
        let denied = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EPERM),
            userInfo: nil
        )
        let status = FullDiskAccessChecker.status(
            homeDirectory: home,
            relativePaths: ["Library/Safari"],
            fileExists: { _ in false },
            listDirectory: { _ in throw denied }
        )
        XCTAssertEqual(status, .denied)
    }

    func testNonPermissionErrorDoesNotForceDenied() {
        let other = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO), userInfo: nil)
        let status = FullDiskAccessChecker.status(
            homeDirectory: home,
            relativePaths: ["Library/Safari"],
            fileExists: { _ in true },
            listDirectory: { _ in throw other }
        )
        // Exists but only non-permission failure → unknown (not proof of missing FDA).
        XCTAssertEqual(status, .unknown)
    }

    func testSystemSettingsURLsArePresent() {
        XCTAssertFalse(FullDiskAccessChecker.systemSettingsURLs.isEmpty)
        XCTAssertTrue(
            FullDiskAccessChecker.systemSettingsURLs.contains {
                $0.absoluteString.contains("Privacy_AllFiles")
            }
        )
    }

    func testDefaultProbeListIsNonEmpty() {
        XCTAssertGreaterThanOrEqual(FullDiskAccessChecker.defaultProbeRelativePaths.count, 5)
    }
}
