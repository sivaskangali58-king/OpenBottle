import Foundation

/// Persists only application metadata. Each Wine prefix lives in a UUID-named directory.
public final class BottleStore {
    public let root: URL

    public init(root: URL = BottleStore.defaultRoot) {
        self.root = root.standardizedFileURL
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenBottle", isDirectory: true)
    }

    public var metadataURL: URL { root.appendingPathComponent("bottles.json") }
    public var metadataBackupURL: URL { root.appendingPathComponent("bottles-before-v05.json") }
    public var metadataBackupV06URL: URL { root.appendingPathComponent("bottles-before-v06.json") }
    public var prefixesDirectory: URL { root.appendingPathComponent("Prefixes", isDirectory: true) }
    public var gamePrefixesDirectory: URL { root.appendingPathComponent("GamePrefixes", isDirectory: true) }
    public func gamePrefix(for bottle: Bottle) -> URL {
        gamePrefixesDirectory.appendingPathComponent(bottle.id.uuidString, isDirectory: true)
    }
    public var metadataBackupV07URL: URL { root.appendingPathComponent("bottles-before-v07.json") }
    public var installersDirectory: URL { root.appendingPathComponent("Installers", isDirectory: true) }

    public func prefix(for bottle: Bottle) -> URL {
        if bottle.linkedPrefixName == "GPTK-Steam-Test" {
            return root.appendingPathComponent("GPTK-Steam-Test", isDirectory: true)
        }
        return prefixesDirectory.appendingPathComponent(bottle.id.uuidString, isDirectory: true)
    }

    public func preparePrefix(for bottle: Bottle) throws {
        if bottle.isLinked {
            guard bottle.linkedPrefixName == "GPTK-Steam-Test" else { throw BottleError.invalidLinkedPrefix }
            let path = prefix(for: bottle)
            let resolved = path.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path == root.appendingPathComponent("GPTK-Steam-Test").standardizedFileURL.path,
                  FileManager.default.fileExists(atPath: resolved.appendingPathComponent("drive_c").path)
            else { throw BottleError.missingLinkedPrefix }
            return
        }
        try FileManager.default.createDirectory(at: prefix(for: bottle), withIntermediateDirectories: true)
    }

    public func read() throws -> [Bottle] {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return [] }
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode([Bottle].self, from: data)
    }

    public func write(_ bottles: [Bottle]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // First v0.5 write: preserve the previous metadata so migration is reversible.
        if FileManager.default.fileExists(atPath: metadataURL.path),
           !FileManager.default.fileExists(atPath: metadataBackupURL.path) {
            try FileManager.default.copyItem(at: metadataURL, to: metadataBackupURL)
        }
        // Keep an additional v0.6 snapshot before the first new UI write.
        if FileManager.default.fileExists(atPath: metadataURL.path),
           !FileManager.default.fileExists(atPath: metadataBackupV06URL.path) {
            try FileManager.default.copyItem(at: metadataURL, to: metadataBackupV06URL)
        }
        if FileManager.default.fileExists(atPath: metadataURL.path),
           !FileManager.default.fileExists(atPath: metadataBackupV07URL.path) {
            try FileManager.default.copyItem(at: metadataURL, to: metadataBackupV07URL)
        }
        try encoder.encode(bottles).write(to: metadataURL, options: .atomic)
    }

    public func removeFiles(for bottle: Bottle) throws {
        let fm = FileManager.default
        // Linked prefixes are NEVER deleted, not even on metadata removal.
        let paths = bottle.isLinked ? [] : [prefix(for: bottle), gamePrefix(for: bottle),
                                               installersDirectory.appendingPathComponent(bottle.id.uuidString)]
        for directory in paths {
            if fm.fileExists(atPath: directory.path) {
                try fm.removeItem(at: directory)
            }
        }
    }

    public func linkedGPTKPrefixExists() -> Bool {
        let b = Bottle(name: "GPTK Test", engine: .gptk, linkedPrefixName: "GPTK-Steam-Test")
        return (try? preparePrefix(for: b)) != nil
    }

    public func copyInstaller(_ source: URL, for bottle: Bottle) throws -> URL {
        let extensionName = source.pathExtension.lowercased()
        guard ["exe", "msi"].contains(extensionName) else { throw BottleError.invalidProgramPath }
        let folder = installersDirectory.appendingPathComponent(bottle.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(UUID().uuidString + "." + extensionName)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    public func relativePath(of file: URL, in bottle: Bottle) throws -> String {
        let rootPath = prefix(for: bottle).resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = file.resolvingSymlinksInPath().standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/"), filePath.lowercased().hasSuffix(".exe") else {
            throw BottleError.invalidProgramPath
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    public func executableURL(for program: InstalledProgram, in bottle: Bottle) throws -> URL {
        try executableURL(relativePath: program.relativeExecutablePath, in: bottle)
    }

    public func executableURL(for game: GameShortcut, in bottle: Bottle) throws -> URL {
        try executableURL(relativePath: game.relativeExecutablePath, in: bottle)
    }

    public func artworkURL(for game: GameShortcut, in bottle: Bottle) -> URL? {
        guard let path = game.artworkRelativePath, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            return nil
        }
        let base = prefix(for: bottle).resolvingSymlinksInPath().standardizedFileURL
        let url = base.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Resolves a game only inside its isolated GPTK runtime; never falls back to Steam's Wine prefix.
    public func gptkExecutableURL(for game: GameShortcut, in bottle: Bottle) throws -> URL {
        guard bottle.profile == .steam, bottle.effectiveGameEngine == .gptk else {
            throw BottleError.invalidProgramPath
        }
        let raw = game.relativeExecutablePath
        guard !raw.hasPrefix("/"), !raw.split(separator: "/").contains(".."),
              raw.lowercased().hasSuffix(".exe") else { throw BottleError.invalidProgramPath }
        let prefix = gamePrefix(for: bottle).resolvingSymlinksInPath().standardizedFileURL
        let target = gamePrefix(for: bottle).appendingPathComponent(raw)
            .resolvingSymlinksInPath().standardizedFileURL
        guard target.path.hasPrefix(prefix.path + "/") else { throw BottleError.invalidProgramPath }
        guard FileManager.default.fileExists(atPath: target.path) else { throw BottleError.missingExecutable }
        return target
    }

    private func executableURL(relativePath path: String, in bottle: Bottle) throws -> URL {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              path.lowercased().hasSuffix(".exe") else {
            throw BottleError.invalidProgramPath
        }
        let rootPath = prefix(for: bottle).resolvingSymlinksInPath().standardizedFileURL.path
        let url = prefix(for: bottle).appendingPathComponent(path)
            .resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(rootPath + "/") else { throw BottleError.invalidProgramPath }
        guard FileManager.default.fileExists(atPath: url.path) else { throw BottleError.missingExecutable }
        return url
    }
}
