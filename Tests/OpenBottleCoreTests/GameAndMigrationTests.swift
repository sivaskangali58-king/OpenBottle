import Foundation
import XCTest
@testable import OpenBottleCore

final class GameAndMigrationTests: XCTestCase {
    var root: URL!
    var store: BottleStore!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenBottleV05-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = BottleStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testV04MetadataDecodesWithDefaults() throws {
        let id = UUID()
        let legacy = """
        [{"id":"\(id.uuidString)","name":"Steam","createdAt":0,"programs":[]}]
        """
        try Data(legacy.utf8).write(to: store.metadataURL)
        let bottles = try store.read()
        XCTAssertEqual(bottles.count, 1)
        XCTAssertEqual(bottles[0].id, id)
        XCTAssertEqual(bottles[0].engine, .wineStaging)
        XCTAssertTrue(bottles[0].games.isEmpty)
        XCTAssertNil(bottles[0].linkedPrefixName)
    }
    func testGPTKLinkNeverDeletesPrefix() throws {
        let external = root.appendingPathComponent("GPTK-Steam-Test/drive_c/Program Files (x86)/Steam/steamapps/common/The Guild - Europa 1410 Demo", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let exe = external.appendingPathComponent("Europa1410.exe")
        try Data("game".utf8).write(to: exe)
        let b = Bottle(name: "GPTK – The Guild", engine: .gptk, linkedPrefixName: "GPTK-Steam-Test")
        XCTAssertTrue(store.linkedGPTKPrefixExists())
        try store.preparePrefix(for: b)
        XCTAssertEqual(store.prefix(for: b).lastPathComponent, "GPTK-Steam-Test")
        try store.removeFiles(for: b)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exe.path), "Linked prefix must not be deleted")
    }
    func testGameFinderFindsEuropa1410AndIgnoresHelpers() throws {
        let b = Bottle(name: "Test")
        let common = store.prefix(for: b).appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/The Guild - Europa 1410 Demo", isDirectory: true)
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
        try Data().write(to: common.appendingPathComponent("Europa1410.exe"))
        try Data().write(to: common.appendingPathComponent("UnityCrashHandler64.exe"))
        let found = GameDiscovery.find(in: store.prefix(for: b))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.title, "The Guild - Europa 1410 Demo")
        XCTAssertEqual(found.first?.executableName, "Europa1410.exe")
        XCTAssertTrue(found.first?.relativeExecutablePath.hasSuffix("/Europa1410.exe") == true)
        XCTAssertTrue(GameDiscovery.find(in: store.prefix(for: b), excluding: [found[0].relativeExecutablePath]).isEmpty)
    }
    private func makeSteamGameFile(_ relativePath: String, bottle: Bottle) throws -> URL {
        let root = store.prefix(for: bottle)
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common", isDirectory: true)
        let file = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x4D, 0x5A]).write(to: file)
        return file
    }

    func testOneCardForUnrealRootAndShippingExecutable() throws {
        let bottle = Bottle(name: "Steam")
        try makeSteamGameFile("The Guild - Europa 1410 Demo/Europa1410/Binaries/Win64/Europa1410-Win64-Shipping.exe", bottle: bottle)
        try makeSteamGameFile("The Guild - Europa 1410 Demo/Europa1410.exe", bottle: bottle)
        let found = GameDiscovery.find(in: store.prefix(for: bottle))
        XCTAssertEqual(found.count, 1, "One Steam installation must display one game")
        XCTAssertEqual(found.first?.title, "The Guild - Europa 1410 Demo")
        XCTAssertEqual(found.first?.executableName, "Europa1410.exe", "Prefer the launcher tested successfully with GPTK")
    }

    func testAlreadyRegisteredSecondaryExecutableDoesNotCreateSecondCard() throws {
        let bottle = Bottle(name: "Steam")
        let rootExe = try makeSteamGameFile("The Guild - Europa 1410 Demo/Europa1410.exe", bottle: bottle)
        let shippingExe = try makeSteamGameFile("The Guild - Europa 1410 Demo/Europa1410/Binaries/Win64/Europa1410-Win64-Shipping.exe", bottle: bottle)
        let prefix = store.prefix(for: bottle).path + "/"
        for previouslyRegistered in [rootExe, shippingExe] {
            let rel = String(previouslyRegistered.path.dropFirst(prefix.count))
            let found = GameDiscovery.find(in: store.prefix(for: bottle), excluding: [rel])
            XCTAssertTrue(found.isEmpty, "An already registered game must not reappear with a different EXE")
        }
    }

    func testDifferentGameFoldersStillShowSeparateCards() throws {
        let bottle = Bottle(name: "Steam")
        try makeSteamGameFile("The Guild - Europa 1410 Demo/Europa1410.exe", bottle: bottle)
        try makeSteamGameFile("Another Game/Binaries/Win64/Another-Shipping.exe", bottle: bottle)
        let found = GameDiscovery.find(in: store.prefix(for: bottle))
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.map(\.title), ["Another Game", "The Guild - Europa 1410 Demo"])
        XCTAssertEqual(GameDiscovery.find(in: store.prefix(for: bottle), maxResults: 1).count, 1)
    }

    func testSteamworksSharedIsNotPresentedAsAGame() throws {
        let bottle = Bottle(name: "Steam")
        try makeSteamGameFile("Steamworks Shared/SupportInstaller.exe", bottle: bottle)
        XCTAssertTrue(GameDiscovery.find(in: store.prefix(for: bottle)).isEmpty)
    }

    func testGameShortcutPathValidation() throws {
        let b = Bottle(name: "Test")
        try store.preparePrefix(for: b)
        let good = store.prefix(for: b).appendingPathComponent("drive_c/Game/Game.exe")
        try FileManager.default.createDirectory(at: good.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: good)
        let game = GameShortcut(title: "Game", relativeExecutablePath: "drive_c/Game/Game.exe", showMetalHUD: true)
        XCTAssertEqual(try store.executableURL(for: game, in: b), good)
        XCTAssertThrowsError(try store.executableURL(for: GameShortcut(title: "Bad", relativeExecutablePath: "../../etc/passwd.exe"), in: b))
    }
    func testNewGameMetadataRoundTrip() throws {
        let game = GameShortcut(title: "The Guild", relativeExecutablePath: "drive_c/Game/Europa1410.exe", showMetalHUD: true)
        let bottle = Bottle(name: "GPTK", engine: .gptk, games: [game], linkedPrefixName: "GPTK-Steam-Test")
        try store.write([bottle])
        XCTAssertEqual(try store.read(), [bottle])
    }

    func testV06BacksUpMetadataBeforeFirstWrite() throws {
        let original = Bottle(name: "Steam", engine: .wineStaging)
        try store.write([original])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.metadataBackupV06URL.path))
        let changed = Bottle(id: original.id, name: "Steam Updated", createdAt: original.createdAt)
        try store.write([changed])
        let backup = try Data(contentsOf: store.metadataBackupV06URL)
        let saved = try JSONDecoder().decode([Bottle].self, from: backup)
        XCTAssertEqual(saved, [original])
        XCTAssertEqual(try store.read(), [changed])
        // Later writes must not replace the original v0.6 migration backup.
        try store.write([Bottle(name: "Another")])
        let unchanged = try Data(contentsOf: store.metadataBackupV06URL)
        XCTAssertEqual(unchanged, backup)
    }
}
