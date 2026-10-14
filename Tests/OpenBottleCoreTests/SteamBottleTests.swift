import Foundation
import XCTest
@testable import OpenBottleCore

final class SteamBottleTests: XCTestCase {
    var root: URL!
    var store: BottleStore!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OBSteam-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = BottleStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testSteamProfileAssignsWineAndGPTKAutomatically() {
        let b = SteamBottleSetup.makeBottle()
        XCTAssertEqual(b.name, "Steam")
        XCTAssertEqual(b.profile, .steam)
        XCTAssertEqual(b.engine, .wineStaging)
        XCTAssertEqual(b.effectiveGameEngine, .gptk)
        XCTAssertFalse(b.isLinked)
    }

    func testSteamMetadataRoundTripsWithoutChangingOldBottles() throws {
        let old = Bottle(name: "Original", engine: .gptk)
        let steam = SteamBottleSetup.makeBottle()
        try store.write([old, steam])
        let restored = try store.read()
        XCTAssertEqual(restored, [old, steam])
        XCTAssertEqual(restored[0].profile, .standard)
        XCTAssertEqual(restored[0].effectiveGameEngine, .gptk)
    }

    func testLegacyMetadataDefaultsWithoutProfileOrGameEngine() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","name":"Old Steam","createdAt":0,"programs":[],"engine":"wineStaging"}]
        """
        try Data(legacy.utf8).write(to: store.metadataURL)
        let b = try XCTUnwrap(store.read().first)
        XCTAssertEqual(b.profile, .standard)
        XCTAssertNil(b.gameEngine)
        XCTAssertEqual(b.effectiveGameEngine, .wineStaging)
    }

    func testGamePrefixSeparateFromSteamAndOldGPTKTest() {
        let b = SteamBottleSetup.makeBottle()
        XCTAssertNotEqual(store.prefix(for: b), store.gamePrefix(for: b))
        XCTAssertTrue(store.gamePrefix(for: b).path.contains("/GamePrefixes/"))
        XCTAssertNotEqual(store.gamePrefix(for: b).lastPathComponent, "GPTK-Steam-Test")
    }

    func testDeletingNormalSteamBottleRemovesOnlyItsOwnGamePrefix() throws {
        let steam = SteamBottleSetup.makeBottle()
        let other = SteamBottleSetup.makeBottle()
        let marker = store.gamePrefix(for: steam).appendingPathComponent("drive_c/marker")
        let unrelated = store.gamePrefix(for: other).appendingPathComponent("drive_c/other")
        let original = root.appendingPathComponent("GPTK-Steam-Test/drive_c/original")
        for f in [marker, unrelated, original] {
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("test".utf8).write(to: f)
        }
        try store.removeFiles(for: steam)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testGPTKGameExecutableConstrainedToCopiedPrefix() throws {
        let b = SteamBottleSetup.makeBottle()
        let exe = store.gamePrefix(for: b).appendingPathComponent("drive_c/Games/Example.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: exe)
        let good = GameShortcut(title: "Example", relativeExecutablePath: "drive_c/Games/Example.exe")
        XCTAssertEqual(try store.gptkExecutableURL(for: good, in: b), exe)
        XCTAssertThrowsError(try store.gptkExecutableURL(for: GameShortcut(title: "Bad", relativeExecutablePath: "../../etc/false.exe"), in: b))
        let wrong = Bottle(name: "Normal", engine: .gptk)
        XCTAssertThrowsError(try store.gptkExecutableURL(for: good, in: wrong))
    }

    func testSteamExecutableDiscovery() throws {
        let b = SteamBottleSetup.makeBottle()
        XCTAssertNil(SteamBottleSetup.steamExecutable(in: store.prefix(for: b)))
        let exe = store.prefix(for: b).appendingPathComponent("drive_c/Program Files (x86)/Steam/Steam.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: exe)
        XCTAssertEqual(SteamBottleSetup.steamExecutable(in: store.prefix(for: b)), exe)
    }

    func testDownloadedSteamInstallerNeedsPEHeaderAndValidSize() throws {
        XCTAssertEqual(SteamBottleSetup.installerURL.scheme, "https")
        let file = root.appendingPathComponent("SteamSetup.exe")
        try Data("<html>bad response</html>".utf8).write(to: file)
        XCTAssertFalse(SteamBottleSetup.isPlausibleInstaller(file))
        var data = Data([0x4D, 0x5A])
        data.append(Data(repeating: 0, count: 100_000))
        try data.write(to: file)
        XCTAssertTrue(SteamBottleSetup.isPlausibleInstaller(file))
    }

    func testV07BackupPreservesPreMigrationMetadata() throws {
        let b = Bottle(name: "Old")
        try store.write([b])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.metadataBackupV07URL.path))
        let steam = SteamBottleSetup.makeBottle()
        try store.write([b, steam])
        let backup = try JSONDecoder().decode([Bottle].self,
                from: Data(contentsOf: store.metadataBackupV07URL))
        XCTAssertEqual(backup, [b])
    }
}

extension SteamBottleTests {
    func testSteamGameFolderExtractedWithoutExeSuffix() {
        let path = "drive_c/Program Files (x86)/Steam/steamapps/common/The Guild - Europa 1410 Demo/Europa1410.exe"
        XCTAssertEqual(SteamBottleSetup.relativeGameFolder(for: path),
          "drive_c/Program Files (x86)/Steam/steamapps/common/The Guild - Europa 1410 Demo")
        XCTAssertNil(SteamBottleSetup.relativeGameFolder(for: "../../Steam/steamapps/common/Fake/file.exe"))
        XCTAssertNil(SteamBottleSetup.relativeGameFolder(for: "/opt/Steam/steamapps/common/Game/file.exe"))
        XCTAssertNil(SteamBottleSetup.relativeGameFolder(for: "drive_c/Program Files (x86)/Steam/Steam.exe"))
    }
}
