import XCTest
@testable import PareApp

final class DiskKindTests: XCTestCase {

    private struct Case {
        let label: String
        let pathExtension: String
        let isDirectory: Bool
        let isPackage: Bool
        let expected: DiskKind
    }

    private static let cases: [Case] = [
        Case(label: "plain folder", pathExtension: "", isDirectory: true, isPackage: false, expected: .folder),
        Case(label: "app bundle", pathExtension: "app", isDirectory: true, isPackage: true, expected: .application),
        Case(label: "non-app bundle (framework)", pathExtension: "framework", isDirectory: true, isPackage: true, expected: .folder),
        Case(label: "jpeg by extension", pathExtension: "jpg", isDirectory: false, isPackage: false, expected: .image),
        Case(label: "png by extension", pathExtension: "png", isDirectory: false, isPackage: false, expected: .image),
        Case(label: "quicktime movie", pathExtension: "mov", isDirectory: false, isPackage: false, expected: .video),
        Case(label: "mpeg-4 video", pathExtension: "mp4", isDirectory: false, isPackage: false, expected: .video),
        Case(label: "mp3 audio", pathExtension: "mp3", isDirectory: false, isPackage: false, expected: .audio),
        Case(label: "wav audio", pathExtension: "wav", isDirectory: false, isPackage: false, expected: .audio),
        Case(label: "pdf document", pathExtension: "pdf", isDirectory: false, isPackage: false, expected: .document),
        Case(label: "plain text document", pathExtension: "txt", isDirectory: false, isPackage: false, expected: .document),
        Case(label: "zip archive", pathExtension: "zip", isDirectory: false, isPackage: false, expected: .archive),
        Case(label: "gzip archive", pathExtension: "gz", isDirectory: false, isPackage: false, expected: .archive),
        // .dmg conforms to both .diskImage and .archive; diskImage must win.
        Case(label: "dmg disk image", pathExtension: "dmg", isDirectory: false, isPackage: false, expected: .diskImage),
        Case(label: "iso disk image", pathExtension: "iso", isDirectory: false, isPackage: false, expected: .diskImage),
        Case(label: "unknown extension", pathExtension: "xyz123notarealtype", isDirectory: false, isPackage: false, expected: .other),
        Case(label: "no extension file", pathExtension: "", isDirectory: false, isPackage: false, expected: .other),
    ]

    func testClassifiesEveryCase() {
        for testCase in Self.cases {
            let kind = DiskKind(
                isDirectory: testCase.isDirectory,
                isPackage: testCase.isPackage,
                pathExtension: testCase.pathExtension
            )
            XCTAssertEqual(kind, testCase.expected, testCase.label)
        }
    }

    func testAllCasesAreUniquelyNamed() {
        XCTAssertEqual(DiskKind.allCases.count, Set(DiskKind.allCases.map(\.rawValue)).count)
    }
}
