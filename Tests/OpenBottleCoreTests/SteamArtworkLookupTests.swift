import Foundation
import XCTest
@testable import OpenBottleCore

final class SteamArtworkLookupTests: XCTestCase {
    private var prefix: URL!

    override func setUpWithError() throws {
        prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenBottleArtworkTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: prefix)
    }

    private let gamePath = "drive_c/Program Files (x86)/Steam/steamapps/common/The Guild - Europa 1410 Demo/Europa1410.exe"

    private func makeManifest(appID: Int = 4693080, folder: String = "The Guild - Europa 1410 Demo") throws {
        let steamapps = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps")
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        let file = steamapps.appendingPathComponent("appmanifest_\(appID).acf")
        let manifest = """
        "AppState"
        {
            "appid"  "\(appID)"
            "name"   "The Guild 1 Remake: Europa 1410 Demo"
            "installdir" "\(folder)"
        }
        """
        try Data(manifest.utf8).write(to: file)
    }

    func testExistingGameFindsSteamAppIDFromManifest() throws {
        try makeManifest()
        XCTAssertEqual(SteamArtworkLookup.appID(forExecutable: gamePath, in: prefix), 4693080)
    }

    func testNoManifestDoesNotGuessID() throws {
        XCTAssertNil(SteamArtworkLookup.appID(forExecutable: gamePath, in: prefix))
    }

    func testDifferentGameFolderDoesNotMisidentifyArtwork() throws {
        try makeManifest(folder: "Some Different Game")
        XCTAssertNil(SteamArtworkLookup.appID(forExecutable: gamePath, in: prefix))
    }

    func testUnsafePathIsRejected() throws {
        try makeManifest()
        XCTAssertNil(SteamArtworkLookup.appID(forExecutable: "../../steamapps/common/Fake/Fake.exe", in: prefix))
        XCTAssertNil(SteamArtworkLookup.appID(forExecutable: "drive_c/steamapps/common/Fake/../../Fake.exe", in: prefix))
    }

    func testPublicArtworkURLsContainSteamAppIDAndFallback() throws {
        let urls = SteamArtworkLookup.portraitURLs(for: 4693080)
        XCTAssertEqual(urls.count, 4)
        XCTAssertTrue(urls.allSatisfy { $0.scheme == "https" && $0.absoluteString.contains("4693080") })
        XCTAssertTrue(urls.first!.path.contains("library_600x900.jpg"))
        XCTAssertTrue(urls.last!.path.contains("header.jpg"))
        XCTAssertTrue(SteamArtworkLookup.portraitURLs(for: -1).isEmpty)
    }

    func testTheGuildDemoHasKnownFallbackWhenManifestMissing() {
        XCTAssertEqual(SteamArtworkLookup.knownAppID(for: "The Guild - Europa 1410 Demo"), 4693080)
        XCTAssertEqual(SteamArtworkLookup.knownAppID(for: "The Guild 1 Remake: Europa 1410"), 2977260)
        XCTAssertNil(SteamArtworkLookup.knownAppID(for: "Other Game"))
    }

    func testLocalSteamArtworkIsPreferredWithoutDownload() throws {
        let image = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/appcache/librarycache/4693080/library_600x900.jpg")
        try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF]).write(to: image)
        XCTAssertEqual(SteamArtworkLookup.localArtwork(for: 4693080, in: prefix), image)
    }

    func testOlderSavedGameShortcutsDecodeWithoutArtworkFields() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","title":"The Guild", "relativeExecutablePath":"drive_c/Game.exe", "showMetalHUD":false}
        """
        let game = try JSONDecoder().decode(GameShortcut.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(game.steamAppID)
        XCTAssertNil(game.artworkRelativePath)
    }
}
