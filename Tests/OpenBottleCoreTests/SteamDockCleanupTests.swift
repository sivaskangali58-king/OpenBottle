import Foundation
import XCTest
@testable import OpenBottleCore

final class SteamDockCleanupTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let prefix = root.appendingPathComponent("Prefixes/Steam")
        let steam = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: steam.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data().write(to: steam)
        let log = root.appendingPathComponent("commands.txt")
        func executable(_ name: String, _ contents: String) throws {
            let file = bin.appendingPathComponent(name)
            try ("#!/bin/sh\n" + contents).write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        try executable("wine", "echo wine:\"$WINEPREFIX\":\"$2\" >> \"\(log.path)\"\nexit 0\n")
        try executable("wineserver", "echo server:\"$WINEPREFIX\":\"$1\" >> \"\(log.path)\"\nexit 0\n")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (prefix, bin.appendingPathComponent("wine"), steam, log)
    }
    func testQuitThenPrefixScopedCleanup() throws {
        let (prefix, wine, steam, log) = try fixture()
        let result = SteamDockCleanup.close(prefix: prefix, wine: wine, steam: steam, quitTimeout: 3, stopTimeout: 3)
        XCTAssertTrue(result.success, result.message)
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(lines[0]), "wine:\(prefix.path):-shutdown")
        XCTAssertEqual(String(lines[1]), "server:\(prefix.path):-k")
    }
    func testRejectSteamOutsidePrefix() throws {
        let (prefix, wine, _, log) = try fixture()
        let foreign = prefix.deletingLastPathComponent().appendingPathComponent("another/steam.exe")
        let result = SteamDockCleanup.close(prefix: prefix, wine: wine, steam: foreign)
        XCTAssertFalse(result.success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
    }
    func testNoDeletingPrefixOrSteam() throws {
        let (prefix, wine, steam, _) = try fixture()
        let result = SteamDockCleanup.close(prefix: prefix, wine: wine, steam: steam, quitTimeout: 3, stopTimeout: 3)
        XCTAssertTrue(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: steam.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prefix.path))
    }
}
