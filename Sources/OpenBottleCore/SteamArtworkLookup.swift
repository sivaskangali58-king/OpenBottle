import Foundation

/// Discovers an installed Steam game's numeric AppID from Steam's own local ACF
/// manifest. It does not change games, Wine prefixes, or Steam configuration.
public enum SteamArtworkLookup {
    /// The AppID is read only from the steamapps directory containing the game.
    public static func appID(forExecutable relativePath: String, in prefix: URL) -> Int? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.first == "drive_c", !components.contains(".."),
              let index = components.firstIndex(where: { $0.lowercased() == "steamapps" }),
              index + 2 < components.count,
              components[index + 1].lowercased() == "common" else { return nil }
        let gameFolderName = components[index + 2]
        let steamapps = prefix.appendingPathComponent(components[0...index].joined(separator: "/"),
                                                    isDirectory: true)
        let prefixPath = prefix.resolvingSymlinksInPath().standardizedFileURL.path
        guard steamapps.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(prefixPath + "/") else { return nil }
        guard let files = try? FileManager.default.contentsOfDirectory(at: steamapps,
                             includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                             options: [.skipsHiddenFiles]) else { return nil }
        for manifest in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let filename = manifest.lastPathComponent.lowercased()
            guard filename.hasPrefix("appmanifest_"), filename.hasSuffix(".acf") else { continue }
            let values = try? manifest.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) < 1_000_000,
                  let text = try? String(contentsOf: manifest, encoding: .utf8) else { continue }
            let lines = text.split(whereSeparator: \.isNewline)
            var appID: Int?
            var directory: String?
            for line in lines {
                let fields = line.split(separator: "\"").map(String.init)
                guard fields.count >= 4 else { continue }
                switch fields[1].lowercased() {
                case "appid": appID = Int(fields[3])
                case "installdir": directory = fields[3]
                default: break
                }
                if appID != nil && directory != nil { break }
            }
            guard let directory, directory.caseInsensitiveCompare(gameFolderName) == .orderedSame,
                  let appID, appID > 0 else { continue }
            return appID
        }
        return nil
    }

    /// Known Steam identifiers for games with a proven title-to-ID mapping.
    /// This is only a fallback if a local ACF manifest cannot be read.
    public static func knownAppID(for title: String) -> Int? {
        let normalized = title.lowercased()
        if normalized.contains("guild") && normalized.contains("europa") && normalized.contains("1410") {
            return normalized.contains("demo") ? 4_693_080 : 2_977_260
        }
        return nil
    }

    /// Steam's publicly accessible artwork. A missing portrait can fall back to
    /// a store header. Never send personal Steam information or authentication.
    public static func portraitURLs(for appID: Int) -> [URL] {
        guard appID > 0 else { return [] }
        return [
            "https://shared.steamstatic.com/store_item_assets/steam/apps/\(appID)/library_600x900.jpg",
            "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg",
            "https://shared.steamstatic.com/store_item_assets/steam/apps/\(appID)/header.jpg",
            "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg"
        ].compactMap(URL.init(string:))
    }

    public static func downloadedArtworkURL(for appID: Int, in appSupport: URL) -> URL {
        appSupport.appendingPathComponent("Artwork", isDirectory: true)
            .appendingPathComponent("\(appID).jpg")
    }

    /// Steam has used both flat and per-game cache directories across versions.
    public static func localArtwork(for appID: Int, in prefix: URL) -> URL? {
        guard appID > 0 else { return nil }
        let roots = [
            "drive_c/Program Files (x86)/Steam/appcache/librarycache",
            "drive_c/Program Files/Steam/appcache/librarycache"
        ]
        let files = [
            "\(appID)/library_600x900.jpg", "\(appID)_library_600x900.jpg",
            "\(appID)/header.jpg", "\(appID)_header.jpg",
            "\(appID)/library_capsule.jpg", "\(appID)_library_capsule.jpg"
        ]
        for root in roots {
            for file in files {
                let url = prefix.appendingPathComponent(root, isDirectory: true)
                                .appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }
}
