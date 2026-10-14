import Foundation

public struct GameCandidate: Identifiable, Hashable, Sendable {
    public var id: String { relativeExecutablePath }
    public let title: String
    public let relativeExecutablePath: String
    public let executableName: String
    public let steamAppID: Int?
    public let artworkRelativePath: String?
}

/// Lists at most one suggested launcher per installed Steam game folder.
/// The game remains untouched; users can still select another EXE using manual add.
public enum GameDiscovery {
    private static let skip: Set<String> = [
        "uninstall", "unins000", "setup", "installer", "update", "updater",
        "crashreporter", "crashhandler", "crashpad_handler", "unitycrashhandler64",
        "unitycrashhandler32", "vc_redist.x64", "vc_redist.x86", "dxsetup",
        "vcredist_x64", "vcredist_x86", "steamworks.shared", "steam.exe"
    ]

    private struct RankedExecutable {
        let candidate: GameCandidate
        let depth: Int
        let score: Int
    }

    private struct SteamManifest {
        let appID: Int
        let name: String
        let installDir: String
    }

    private static func parseQuotedValue(_ line: String, key: String) -> String? {
        let tokens = line.split(separator: "\"").map(String.init)
        guard tokens.count >= 4, tokens[1].lowercased() == key.lowercased() else { return nil }
        return tokens[3]
    }

    private static func loadSteamManifests(in steamAppsRoot: URL) -> [String: SteamManifest] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: steamAppsRoot,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [:] }
        var manifests: [String: SteamManifest] = [:]
        for url in urls where url.lastPathComponent.lowercased().hasPrefix("appmanifest_") && url.pathExtension.lowercased() == "acf" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var appID: Int?
            var name: String?
            var installDir: String?
            for line in text.split(whereSeparator: \.isNewline) {
                let line = String(line)
                if appID == nil, let value = parseQuotedValue(line, key: "appid") { appID = Int(value) }
                if name == nil, let value = parseQuotedValue(line, key: "name") { name = value }
                if installDir == nil, let value = parseQuotedValue(line, key: "installdir") { installDir = value }
            }
            if let appID, let installDir {
                let title = name ?? installDir
                manifests[installDir.lowercased()] = SteamManifest(appID: appID, name: title, installDir: installDir)
            }
        }
        return manifests
    }

    private static func artworkRelativePath(appID: Int, driveC: URL) -> String? {
        let fm = FileManager.default
        let candidates = [
            "Program Files (x86)/Steam/appcache/librarycache/\(appID)_library_600x900.jpg",
            "Program Files (x86)/Steam/appcache/librarycache/\(appID)_header.jpg",
            "Program Files (x86)/Steam/appcache/librarycache/\(appID)_library_capsule.jpg",
            "Program Files (x86)/Steam/appcache/librarycache/\(appID)_hero_capsule.jpg",
            "Program Files/Steam/appcache/librarycache/\(appID)_library_600x900.jpg",
            "Program Files/Steam/appcache/librarycache/\(appID)_header.jpg",
            "Program Files/Steam/appcache/librarycache/\(appID)_library_capsule.jpg",
            "Program Files/Steam/appcache/librarycache/\(appID)_hero_capsule.jpg"
        ]
        for relative in candidates {
            if fm.fileExists(atPath: driveC.appendingPathComponent(relative).path) { return "drive_c/\(relative)" }
        }
        return nil
    }

    /// Steam game folders can have both a root launcher and an Unreal Engine
    /// `Binaries/Win64/*-Shipping.exe`; prefer the launcher Steam normally starts.
    private static func launcherScore(name: String, relativeDepth: Int, gameFolder: String) -> Int {
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.lowercased()
        let title = gameFolder.lowercased().filter { $0.isLetter || $0.isNumber }
        let normalizedStem = stem.filter { $0.isLetter || $0.isNumber }
        var score = relativeDepth == 1 ? 100 : 0
        score += max(0, 40 - relativeDepth * 8)
        if normalizedStem.count >= 4 && title.contains(normalizedStem) { score += 25 }
        if stem.hasSuffix("-shipping") || stem.contains("win64-shipping") { score -= 70 }
        if stem.contains("launcher") || stem.contains("bootstrap") { score += 5 }
        return score
    }

    public static func find(in prefix: URL, excluding registeredPaths: Set<String> = [],
                            maxResults: Int = 100) -> [GameCandidate] {
        guard maxResults > 0 else { return [] }
        let fm = FileManager.default
        let base = prefix.resolvingSymlinksInPath().standardizedFileURL
        let driveC = base.appendingPathComponent("drive_c", isDirectory: true)
        let roots = ["Program Files (x86)/Steam/steamapps/common", "Program Files/Steam/steamapps/common",
                     "SteamLibrary/steamapps/common", "Games/SteamLibrary/steamapps/common"]
            .map { driveC.appendingPathComponent($0, isDirectory: true) }
        let steamManifestMaps: [String: [String: SteamManifest]] = [
            "Program Files (x86)/Steam/steamapps/common": loadSteamManifests(in: driveC.appendingPathComponent("Program Files (x86)/Steam/steamapps", isDirectory: true)),
            "Program Files/Steam/steamapps/common": loadSteamManifests(in: driveC.appendingPathComponent("Program Files/Steam/steamapps", isDirectory: true))
        ]
        let excluded = Set(registeredPaths.map { $0.lowercased() })
        var found = [GameCandidate]()
        var seenGameFolders = Set<String>()
        var visited = 0
        for root in roots {
            guard let games = try? fm.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]) else { continue }
            for folder in games.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let folderVals = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard folderVals?.isDirectory == true, folderVals?.isSymbolicLink != true else { continue }
                guard !["steamworks shared", "steamworks common redistributables"].contains(folder.lastPathComponent.lowercased()) else { continue }
                let manifest = steamManifestMaps.first(where: { root.path.hasSuffix($0.key) })?.value[folder.lastPathComponent.lowercased()]
                let folderURL = folder.resolvingSymlinksInPath().standardizedFileURL
                guard folderURL.path.hasPrefix(base.path + "/") else { continue }
                let folderRelative = String(folderURL.path.dropFirst(base.path.count + 1))
                guard seenGameFolders.insert(folderRelative.lowercased()).inserted else { continue }

                // A registered executable anywhere inside this installation means the
                // game is already in the library. Do not offer its second EXE again.
                let gamePrefix = folderRelative.lowercased() + "/"
                if excluded.contains(where: { $0.hasPrefix(gamePrefix) }) { continue }

                guard let enumerator = fm.enumerator(at: folder,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }) else { continue }
                var best: RankedExecutable?
                while let file = enumerator.nextObject() as? URL {
                    visited += 1
                    if visited > 25_000 { break }
                    let depth = file.pathComponents.count - folder.pathComponents.count
                    if depth > 5 { enumerator.skipDescendants(); continue }
                    let vals = try? file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                    if vals?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    if vals?.isDirectory == true {
                        if ["_commonredist", "redist", "redistributables", "support", "directx", "engine", "crashreporter"].contains(file.lastPathComponent.lowercased()) {
                            enumerator.skipDescendants()
                        }
                        continue
                    }
                    guard vals?.isRegularFile == true, file.pathExtension.lowercased() == "exe" else { continue }
                    let stem = file.deletingPathExtension().lastPathComponent.lowercased()
                    guard !skip.contains(stem), !stem.hasPrefix("unins"), !stem.hasPrefix("crash") else { continue }
                    let resolved = file.resolvingSymlinksInPath().standardizedFileURL
                    guard resolved.path.hasPrefix(folderURL.path + "/") else { continue }
                    let relative = String(resolved.path.dropFirst(base.path.count + 1))
                    let candidate = GameCandidate(title: manifest?.name ?? folder.lastPathComponent,
                        relativeExecutablePath: relative, executableName: file.lastPathComponent,
                        steamAppID: manifest?.appID,
                        artworkRelativePath: manifest.flatMap { artworkRelativePath(appID: $0.appID, driveC: driveC) })
                    let ranked = RankedExecutable(candidate: candidate, depth: depth,
                        score: launcherScore(name: file.lastPathComponent, relativeDepth: depth,
                                             gameFolder: folder.lastPathComponent))
                    if let current = best {
                        if ranked.score > current.score || (ranked.score == current.score &&
                             candidate.relativeExecutablePath.localizedStandardCompare(current.candidate.relativeExecutablePath) == .orderedAscending) {
                            best = ranked
                        }
                    } else {
                        best = ranked
                    }
                }
                if let best { found.append(best.candidate) }
                if visited > 25_000 || found.count >= maxResults { break }
            }
            if visited > 25_000 || found.count >= maxResults { break }
        }
        return found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
