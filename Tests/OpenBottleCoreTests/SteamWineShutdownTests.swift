import Foundation
import XCTest
@testable import OpenBottleCore

final class SteamWineShutdownTests: XCTestCase {
    private func fixture(serverBody: String?, wineBody: String) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let prefix = dir.appendingPathComponent("Prefix")
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        func executable(_ name: String, _ contents: String) throws {
            let file = bin.appendingPathComponent(name)
            try ("#!/bin/sh\n" + contents + "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        try executable("wine", wineBody)
        if let serverBody { try executable("wineserver", serverBody) }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return (prefix, bin.appendingPathComponent("wine"))
    }

    func testWineServerSuccessUsesFirstMethod() throws {
        let (prefix, wine) = try fixture(serverBody: "exit 0", wineBody: "exit 9")
        let result = SteamWineShutdown.stop(prefix: prefix, wine: wine)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, "wineserver")
    }

    func testWineBootFallbackAfterServerFails() throws {
        let (prefix, wine) = try fixture(serverBody: "echo 'server unavailable' >&2; exit 7", wineBody: "[ \"$1\" = wineboot ] && [ \"$2\" = -k ] || exit 2; exit 0")
        let result = SteamWineShutdown.stop(prefix: prefix, wine: wine)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, "wineboot")
        XCTAssertTrue(result.message.contains("server unavailable"))
    }

    func testMissingServerUsesWineBoot() throws {
        let (prefix, wine) = try fixture(serverBody: nil, wineBody: "exit 0")
        let result = SteamWineShutdown.stop(prefix: prefix, wine: wine)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, "wineboot")
    }

    func testBothMethodsFailWithDiagnostics() throws {
        let (prefix, wine) = try fixture(serverBody: "echo 'server problem' >&2; exit 5", wineBody: "echo 'boot problem' >&2; exit 8")
        let result = SteamWineShutdown.stop(prefix: prefix, wine: wine)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("server problem"))
        XCTAssertTrue(result.message.contains("boot problem"))
    }
}
