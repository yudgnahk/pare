import XCTest
@testable import PareCore

final class MachOLinkInspectorTests: XCTestCase {
    private static let loadDylib: UInt32 = 0xC
    private static let loadWeakDylib: UInt32 = 0x8000_0018
    private static let reexportDylib: UInt32 = 0x8000_001F
    private static let lazyLoadDylib: UInt32 = 0x20
    private static let loadUpwardDylib: UInt32 = 0x8000_0023
    private static let loadDylinker: UInt32 = 0xE
    private static let dyldEnvironment: UInt32 = 0x27

    private let systemLibraries: [(UInt32, String)] = [
        (MachOLinkInspectorTests.loadDylib, "/usr/lib/libSystem.B.dylib"),
        (MachOLinkInspectorTests.loadDylib, "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"),
    ]

    func testExecutableLinkingOnlySystemLibrariesPasses() {
        XCTAssertEqual(MachOLinkInspector.inspect(data: machO(libraries: systemLibraries)), .systemOnly)
    }

    func testAnyLibraryOutsideSystemIsRejectedWhateverTheLoadCommand() {
        let cases: [(UInt32, String)] = [
            (Self.loadDylib, "@rpath/libnode.147.dylib"),
            (Self.loadWeakDylib, "/opt/homebrew/opt/libuv/lib/libuv.1.dylib"),
            (Self.reexportDylib, "@loader_path/../lib/libx.dylib"),
            (Self.lazyLoadDylib, "@executable_path/libx.dylib"),
            (Self.loadUpwardDylib, "/usr/local/lib/libx.dylib"),
            (Self.loadDylib, "/usr/lib/../../opt/homebrew/lib/libx.dylib"),
            (Self.loadDylib, "/usr/libexec/x.dylib"),
        ]
        for (command, name) in cases {
            let data = machO(libraries: systemLibraries + [(command, name)])
            XCTAssertEqual(MachOLinkInspector.inspect(data: data), .nonSystemLibrary(name), name)
        }
    }

    func testCustomDylinkerAndDyldEnvironmentAreRejected() {
        XCTAssertEqual(MachOLinkInspector.inspect(data: machO(libraries: systemLibraries, dylinker: "/tmp/dyld")),
                       .nonSystemLibrary("/tmp/dyld"))
        let withEnvironment = machO(libraries: systemLibraries, extraCommands: [stringCommand(Self.dyldEnvironment, "DYLD_X=1", nameOffset: 12)])
        XCTAssertEqual(MachOLinkInspector.inspect(data: withEnvironment), .setsDyldEnvironment)
    }

    func testEverySliceOfAFatFileIsChecked() {
        let good = machO(libraries: systemLibraries)
        let bad = machO(libraries: [(Self.loadDylib, "@rpath/libnode.dylib")])
        XCTAssertEqual(MachOLinkInspector.inspect(data: fat([good, good])), .systemOnly)
        XCTAssertEqual(MachOLinkInspector.inspect(data: fat([good, bad])), .nonSystemLibrary("@rpath/libnode.dylib"))
    }

    func testScriptsAndNonExecutablesAreNotSystemOnly() {
        XCTAssertEqual(MachOLinkInspector.inspect(data: Data("#!/usr/bin/env node\n".utf8)), .script)
        XCTAssertEqual(MachOLinkInspector.inspect(data: Data("hello world, not a program".utf8)), .notMachO)
        // A Java class file shares the fat magic; its "slice count" is a version number.
        XCTAssertEqual(MachOLinkInspector.inspect(data: Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x34])), .notMachO)
        XCTAssertEqual(MachOLinkInspector.inspect(data: machO(libraries: systemLibraries, fileType: 0x6)), .malformed)
    }

    func testTruncatedLoadCommandsAreMalformed() {
        let full = machO(libraries: systemLibraries)
        XCTAssertEqual(MachOLinkInspector.inspect(data: full.prefix(full.count - 4)), .malformed)
    }

    func testRealSystemExecutablePasses() {
        XCTAssertEqual(MachOLinkInspector.inspect(fileAt: "/bin/ls"), .systemOnly)
        XCTAssertEqual(MachOLinkInspector.inspect(fileAt: "/usr/bin/env"), .systemOnly)
    }

    // MARK: - Builders

    private func machO(
        libraries: [(UInt32, String)],
        dylinker: String = "/usr/lib/dyld",
        extraCommands: [Data] = [],
        fileType: UInt32 = 0x2
    ) -> Data {
        let commands = [stringCommand(Self.loadDylinker, dylinker, nameOffset: 12)]
            + libraries.map { stringCommand($0.0, $0.1, nameOffset: 24) }
            + extraCommands
        let body = commands.reduce(Data(), +)
        var header = Data()
        for value: UInt32 in [0xFEED_FACF, 0x0100_000C, 0, fileType, UInt32(commands.count), UInt32(body.count), 0, 0] {
            header.append(littleEndian: value)
        }
        return header + body
    }

    /// A load command whose `lc_str` sits at `nameOffset`, NUL-terminated and padded to 8 bytes.
    private func stringCommand(_ command: UInt32, _ name: String, nameOffset: Int) -> Data {
        var string = Data(name.utf8) + Data([0])
        let size = (nameOffset + string.count + 7) / 8 * 8
        string.append(Data(count: size - nameOffset - string.count))
        var data = Data()
        data.append(littleEndian: command)
        data.append(littleEndian: UInt32(size))
        data.append(littleEndian: UInt32(nameOffset))
        data.append(Data(count: nameOffset - 12))
        return data + string
    }

    private func fat(_ slices: [Data]) -> Data {
        let alignment = 0x1000
        var data = Data()
        data.append(bigEndian: 0xCAFE_BABE)
        data.append(bigEndian: UInt32(slices.count))
        var offset = alignment
        var bodies = Data()
        for slice in slices {
            for value: UInt32 in [0x0100_000C, 0, UInt32(offset), UInt32(slice.count), 12] {
                data.append(bigEndian: value)
            }
            let padded = slice + Data(count: alignment - slice.count % alignment)
            bodies.append(padded)
            offset += padded.count
        }
        return data + Data(count: alignment - data.count) + bodies
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(bigEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
