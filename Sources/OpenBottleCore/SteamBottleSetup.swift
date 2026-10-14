import Foundation

public enum SteamBottleSetup {
    /// Official Windows Steam installer distributed by Valve's Steam CDN.
    public static let installerURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!
    public static let minimumInstallerBytes = 100_000
    public static let maximumInstallerBytes = 100_000_000

    public static func makeBottle(name: String = "Steam") -> Bottle {
        Bottle(name: name, engine: .wineStaging, profile: .steam, gameEngine: .gptk)
    }

    /// Returns the relative root of a Steam game's install directory, never an absolute path.
    /// Used to copy only a newly installed game into an existing GPTK test prefix.
    public static func relativeGameFolder(for executablePath: String) -> String? {
        let parts = executablePath.split(separator: "/").map(String.init)
        guard parts.count >= 7, parts.first == "drive_c", !parts.contains(".."),
              !executablePath.hasPrefix("/"), executablePath.lowercased().hasSuffix(".exe") else { return nil }
        guard let steamapps = parts.indices.first(where: {
            parts[$0].lowercased() == "steamapps" && $0 + 2 < parts.count &&
            parts[$0 + 1].lowercased() == "common"
        }), steamapps + 3 < parts.count else { return nil }
        return parts[...(steamapps + 2)].joined(separator: "/")
    }

    public static func steamExecutable(in prefix: URL) -> URL? {
        for path in ["drive_c/Program Files (x86)/Steam/Steam.exe",
                     "drive_c/Program Files/Steam/Steam.exe"] {
            let file = prefix.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    /// Check the PE header to avoid passing a broken HTML/network response to Wine.
    public static func isPlausibleInstaller(_ file: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue >= minimumInstallerBytes, size.intValue <= maximumInstallerBytes,
              let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) == Data([0x4D, 0x5A])
    }
}
