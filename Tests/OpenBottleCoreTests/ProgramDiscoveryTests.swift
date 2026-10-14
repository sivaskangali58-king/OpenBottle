import XCTest
import Foundation
@testable import OpenBottleCore

final class ProgramDiscoveryTests: XCTestCase {
    var root: URL!
    var prefix: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenBottleDiscovery-\(UUID().uuidString)")
        prefix = root.appendingPathComponent("prefix")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeEXE(_ relative: String) throws -> URL {
        let file = prefix.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x4D, 0x5A]).write(to: file)
        return file
    }

    func testFindsProgramsNotWindowsSystemEXEs() throws {
        try makeEXE("drive_c/Program Files/Example/App.exe")
        try makeEXE("drive_c/Program Files/Example/unins000.exe")
        try makeEXE("drive_c/windows/system32/cmd.exe")
        let programs = ProgramDiscovery.find(in: prefix)
        XCTAssertEqual(programs.map(\.relativeExecutablePath), ["drive_c/Program Files/Example/App.exe"])
    }
    func testUsersLocalProgramsAndRegisteredAreExcluded() throws {
        try makeEXE("drive_c/users/bob/AppData/Local/Programs/Foo/Foo.exe")
        let found = ProgramDiscovery.find(in: prefix)
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(ProgramDiscovery.find(in: prefix, excluding: Set(found.map(\.relativeExecutablePath))).isEmpty)
    }
    func testMaxResultAndSorted() throws {
        try makeEXE("drive_c/Program Files/Test/Zeta.exe")
        try makeEXE("drive_c/Program Files/Test/Alpha.exe")
        XCTAssertEqual(ProgramDiscovery.find(in: prefix).map(\.title), ["Alpha", "Zeta"])
        XCTAssertEqual(ProgramDiscovery.find(in: prefix, maxResults: 1).count, 1)
    }
    func testSymlinkOutsideIsNotShown() throws {
        let outside = root.appendingPathComponent("external.exe")
        try Data([0x4D, 0x5A]).write(to: outside)
        let folder = prefix.appendingPathComponent("drive_c/Program Files/Test")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("evil.exe"), withDestinationURL: outside)
        XCTAssertTrue(ProgramDiscovery.find(in: prefix).isEmpty)
    }
    func testWineFoldersNeverCountAsExecutables() throws {
        let fakeWineFolder = root.appendingPathComponent("wine")
        try FileManager.default.createDirectory(at: fakeWineFolder, withIntermediateDirectories: true)
        XCTAssertFalse(WineLocator.isValidExecutable(fakeWineFolder.path))
        let candidates = WineLocator.candidates(custom: "/custom/wine", environmentPath: "", applications: "/Applications")
        XCTAssertEqual(candidates.first, "/custom/wine")
        XCTAssertTrue(candidates.contains("/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine"))
    }
}
