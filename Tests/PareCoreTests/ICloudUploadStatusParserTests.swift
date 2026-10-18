import XCTest
@testable import PareCore

/// `brctl` output is undocumented, so the parser reads it loosely and returns nil on drift.
final class ICloudUploadStatusParserTests: XCTestCase {

    // MARK: - Fixtures (sanitised; same shape as macOS 27 `brctl status`)

    static let esc = "\u{1B}"

    static func item(name: String, bytes: Int, lastHours: String, quota: Bool = true) -> String {
        let error = quota
            ? """
                    > upload{[ upload_error:<NSError:0x1(CKErrorDomain:25) - {
                        CKErrorDescription = "Error uploading asset: Quota exceeded";
                        ServerErrorDescription = "Quota exceeded";
                    }> \(esc)[31mpending-quota\(esc)[39m attempts:1 last:\(esc)[0;1;34m\(lastHours) ago\(esc)[0m next:ready cleanup:ready]}
            """
            : """
                    > upload{[ attempts:1 last:\(lastHours) ago next:ready]}
            """
        return """
                r:297 i:<3C785A39> al:1 ld{synced-all} up:\(esc)[31mneeds-upload\(esc)[39m uv:1 st{p:<A8B7D61B> n:"\(esc)[0;1m\(name)\(esc)[0m" doc m:rw- sc:docs} ct{mt:1787060022 sz:\(esc)[0;1;30m\(bytes / 1000) KB (\(bytes))\(esc)[0m n:"\(name)" sig:<file-pending>}
        \(error)
        """
    }

    static let status = """
    1 containers matching '*'
    <c{1}m.a{3}e.C{7}s[1] \(esc)[0;1;32mforeground\(esc)[0m {client:idle server:full-sync caught-up}>
        Client Truth Unclean Items:
        --------------------------
        Under /Desktop
    \(item(name: "M{27}o.txt", bytes: 2_840, lastHours: "1362.80h"))
    \(item(name: "S{31}7.png", bytes: 1_733_643, lastHours: "90.5h"))
        Under /Documents/Secret Project/Inner
    \(item(name: "P{14}d.app", bytes: 9_830_000_000, lastHours: "1366.43h"))
    \(item(name: "N{4}s.md", bytes: 4_000, lastHours: "2h", quota: false))

    Desktop & Documents: current=YES lastEnabled=(never) lastDisabled=(never)
    """

    // MARK: - Quota

    func testRemainingQuotaBytes() {
        let cases: [(output: String, bytes: Int64?)] = [
            ("0 bytes of quota remaining in personal account", 0),
            ("1.5 GB of quota remaining in personal account", 1_500_000_000),
            ("2,3 GB of quota remaining in personal account", 2_300_000_000),
            ("512 MB of quota remaining in personal account", 512_000_000),
            ("1,024 bytes of quota remaining in personal account", 1_024),
            ("\(Self.esc)[1m0 bytes\(Self.esc)[0m of quota remaining in personal account", 0),
            ("3 GB of quota remaining in personal account\n0 bytes of quota remaining in family account", 0),
            ("Not signed in to iCloud", nil),
            ("", nil),
        ]
        for testCase in cases {
            XCTAssertEqual(ICloudUploadStatusParser.remainingQuotaBytes(fromQuotaOutput: testCase.output), testCase.bytes, testCase.output)
        }
    }

    // MARK: - Status

    func testBacklogCountsOnlyQuotaBlockedItems() throws {
        let backlog = try XCTUnwrap(ICloudUploadStatusParser.backlog(fromStatusOutput: Self.status))

        XCTAssertEqual(backlog.itemCount, 3, "the needs-upload item without a quota error is not stuck on quota")
        XCTAssertEqual(backlog.totalBytes, 2_840 + 1_733_643 + 9_830_000_000)
        XCTAssertEqual(backlog.oldestPendingHours, 1366.43, accuracy: 0.001)
        XCTAssertEqual(backlog.topLevelFolders, ["Desktop", "Documents"])
    }

    func testBacklogKeepsOnlyTopLevelFolderNames() throws {
        let backlog = try XCTUnwrap(ICloudUploadStatusParser.backlog(fromStatusOutput: Self.status))
        let described = String(describing: backlog)

        for leaked in ["Secret Project", "Inner", "M{27}o.txt", "P{14}d.app", "A8B7D61B"] {
            XCTAssertFalse(described.contains(leaked), leaked)
        }
    }

    func testFoldersOutsideDesktopAndDocumentsAreICloudDrive() throws {
        let output = "    Under /Notes/x\n" + Self.item(name: "a", bytes: 1_000, lastHours: "10h")
        let backlog = try XCTUnwrap(ICloudUploadStatusParser.backlog(fromStatusOutput: output))

        XCTAssertEqual(backlog.topLevelFolders, ["iCloud Drive"])
    }

    func testAgeUnits() throws {
        let cases: [(last: String, hours: Double)] = [("90s", 0.025), ("30m", 0.5), ("5h", 5), ("2.5d", 60)]
        for testCase in cases {
            let output = "    Under /Desktop\n" + Self.item(name: "a", bytes: 1_000, lastHours: testCase.last)
            let backlog = try XCTUnwrap(ICloudUploadStatusParser.backlog(fromStatusOutput: output), testCase.last)
            XCTAssertEqual(backlog.oldestPendingHours, testCase.hours, accuracy: 0.0001, testCase.last)
        }
    }

    func testNothingStuckIsAnEmptyBacklog() throws {
        let output = "1 containers matching '*'\n<c{1}m.a{3}e.C{7}s[1] foreground {client:idle}>\n\nDesktop & Documents: current=YES"
        let backlog = try XCTUnwrap(ICloudUploadStatusParser.backlog(fromStatusOutput: output))

        XCTAssertEqual(backlog.itemCount, 0)
        XCTAssertEqual(backlog.totalBytes, 0)
    }

    func testFormatDriftIsNil() {
        let renamedSize = Self.status.replacingOccurrences(of: "sz:", with: "size=")
        XCTAssertNil(ICloudUploadStatusParser.backlog(fromStatusOutput: renamedSize), "stuck items without any readable size")
        XCTAssertNil(ICloudUploadStatusParser.backlog(fromStatusOutput: ""))
        XCTAssertNil(ICloudUploadStatusParser.backlog(fromStatusOutput: "   \n"))
    }

    func testStripANSI() {
        XCTAssertEqual(ICloudUploadStatusParser.stripANSI("a\(Self.esc)[0;1;34mb\(Self.esc)[0mc"), "abc")
    }
}
