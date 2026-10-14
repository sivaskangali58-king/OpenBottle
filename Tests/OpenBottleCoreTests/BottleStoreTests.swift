import XCTest
import Foundation
@testable import OpenBottleCore

final class BottleStoreTests: XCTestCase {
    var directory: URL!
    var store: BottleStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenBottleTests-\(UUID())")
        store = BottleStore(root: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }
    func testEmptyStore() throws { XCTAssertTrue(try store.read().isEmpty) }
    func testMetadataRoundTrip() throws {
        let bottle = Bottle(name: "Oyunlar", programs: [InstalledProgram(title: "Test", relativeExecutablePath: "drive_c/test.exe")])
        try store.write([bottle])
        XCTAssertEqual(try store.read(), [bottle])
    }
    func testDifferentPrefixes() throws {
        XCTAssertNotEqual(store.prefix(for: Bottle(name: "A")), store.prefix(for: Bottle(name: "A")))
    }
    func testProgramMustBeInsidePrefix() throws {
        let bottle = Bottle(name: "Game")
        try store.preparePrefix(for: bottle)
        let exe = store.prefix(for: bottle).appendingPathComponent("drive_c/example.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: exe)
        let rel = try store.relativePath(of: exe, in: bottle)
        XCTAssertEqual(rel, "drive_c/example.exe")
        XCTAssertEqual(try store.executableURL(for: InstalledProgram(title: "Test", relativeExecutablePath: rel), in: bottle), exe)
        XCTAssertThrowsError(try store.relativePath(of: directory.appendingPathComponent("evil.exe"), in: bottle))
        XCTAssertThrowsError(try store.executableURL(for: InstalledProgram(title: "Bad", relativeExecutablePath: "../evil.exe"), in: bottle))
    }
    func testDeleteFiles() throws {
        let bottle = Bottle(name: "Delete")
        try store.preparePrefix(for: bottle)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.prefix(for: bottle).path))
        try store.removeFiles(for: bottle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.prefix(for: bottle).path))
    }
    func testInstallerCopiedUnderDedicatedDirectory() throws {
        let b = Bottle(name: "Install")
        let file = directory.appendingPathComponent("setup.msi")
        try Data("installer".utf8).write(to: file)
        let copied = try store.copyInstaller(file, for: b)
        XCTAssertEqual(copied.pathExtension, "msi")
        XCTAssertEqual(try Data(contentsOf: copied), Data("installer".utf8))
        XCTAssertThrowsError(try store.copyInstaller(directory.appendingPathComponent("x.txt"), for: b))
    }

    func testSymlinkCannotEscapePrefix() throws {
        let b = Bottle(name: "Security")
        try store.preparePrefix(for: b)
        let external = directory.appendingPathComponent("outside.exe")
        try Data("bad".utf8).write(to: external)
        let link = store.prefix(for: b).appendingPathComponent("linked.exe")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertThrowsError(try store.relativePath(of: link, in: b))
        XCTAssertThrowsError(try store.executableURL(
            for: InstalledProgram(title: "linked", relativeExecutablePath: "linked.exe"), in: b))
    }

}
