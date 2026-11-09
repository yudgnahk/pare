import XCTest
@testable import PareCore

/// Docker's settings files are undocumented, so the parser reads them loosely and returns nil on drift.
final class DockerDesktopSettingsParserTests: XCTestCase {

    static let ownerFile = """
    {"AutoDownloadUpdates":true,"AutoStart":false,"DesktopTerminalEnabled":false,"DisplayedOnboarding":true,
     "DockerAppLaunchPath":"/Applications/Docker.app","DockerBinInstallPath":"system","EnableCLIHints":true,
     "EnableDefaultDockerSocket":true,"EnableDockerAI":false,"EngineTypeMac":"apple-virtualization-framework",
     "LicenseTermsVersion":2,"SettingsVersion":48,"ShowInstallScreen":false,"UpdateInstallTime":1760000000,
     "UpdateInstallerPid":0,"UpdatePreviousVersion":"","UseContainerdSnapshotter":false,"UseVirtualizationFramework":true}
    """

    private func parse(_ text: String) -> DockerVMSettings? {
        DockerDesktopSettingsParser.parse(Data(text.utf8))
    }

    func testOwnerFileHasNoVMLimitKeys() {
        XCTAssertEqual(
            parse(Self.ownerFile),
            DockerVMSettings(memoryMiB: nil, resourceSaver: nil, kubernetes: nil, engine: "apple-virtualization-framework")
        )
    }

    func testPascalCaseAndCamelCaseBothParse() {
        let expected = DockerVMSettings(memoryMiB: 4096, resourceSaver: false, kubernetes: true, engine: "x")
        XCTAssertEqual(
            parse(#"{"MemoryMiB":4096,"UseResourceSaver":false,"KubernetesEnabled":true,"EngineTypeMac":"x"}"#), expected
        )
        XCTAssertEqual(
            parse(#"{"memoryMiB":4096,"useResourceSaver":false,"kubernetesEnabled":true,"engineTypeMac":"x"}"#), expected
        )
    }

    func testWrongTypesRejectTheWholeResult() {
        let cases = [
            #"{"MemoryMiB":"4096"}"#,
            #"{"MemoryMiB":true}"#,
            #"{"MemoryMiB":4096.5}"#,
            #"{"UseResourceSaver":1}"#,
            #"{"UseResourceSaver":"false"}"#,
            #"{"KubernetesEnabled":0}"#,
            #"{"EngineTypeMac":5}"#,
            #"{"MemoryMiB":4096,"UseResourceSaver":"no"}"#,
        ]
        for text in cases {
            XCTAssertNil(parse(text), text)
        }
    }

    func testGarbageAndNonObjectsAreNil() {
        for text in ["", "not json", "[]", "[{\"MemoryMiB\":4096}]", "{}", "42", "null"] {
            XCTAssertNil(parse(text), text)
        }
    }

    func testOversizedFileIsNil() {
        let padding = String(repeating: "a", count: 1_048_577)
        XCTAssertNil(parse(#"{"MemoryMiB":4096,"Pad":""# + padding + #""}"#))
    }

    func testNonPositiveMemoryIsNil() {
        XCTAssertNil(parse(#"{"MemoryMiB":0}"#))
        XCTAssertNil(parse(#"{"MemoryMiB":-1}"#))
        XCTAssertEqual(parse(#"{"MemoryMiB":1}"#)?.memoryMiB, 1)
    }
}
