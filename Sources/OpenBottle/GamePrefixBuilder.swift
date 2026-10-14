#if os(macOS)
import Foundation
import OpenBottleCore

/// Makes an independent copy of a Steam prefix for the GPTK Wine runtime.
/// Does not mutate the working Wine Staging Steam environment.
enum GamePrefixBuilder {
    static func prepare(source: URL, destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.appendingPathComponent("drive_c").path) else {
            throw NSError(domain: "OpenBottle", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Steam ortamı henüz hazırlanmamış."])
        }
        guard !fm.fileExists(atPath: destination.path) else { return }
        try cloneDirectory(source: source, destination: destination)
    }

    /// Copies only a new Steam game into an already existing GPTK prefix.
    /// Never overwrites a game's existing files or save data.
    static func addMissingGame(_ gameRelativePath: String, steamPrefix: URL, gamePrefix: URL) throws {
        guard let relative = OpenBottleCore.SteamBottleSetup.relativeGameFolder(for: gameRelativePath) else {
            throw NSError(domain: "OpenBottle", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Bu EXE Steam oyun klasöründe değil. Yeniden taramayı dene."])
        }
        let source = steamPrefix.appendingPathComponent(relative)
        let dest = gamePrefix.appendingPathComponent(relative)
        let safeRoot = gamePrefix.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedParent = dest.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        guard resolvedParent.hasPrefix(safeRoot + "/") else {
            throw NSError(domain: "OpenBottle", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Hedef klasör şişenin dışına yönleniyor."])
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw NSError(domain: "OpenBottle", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "Oyunun kurulum klasörü bulunamadı."])
        }
        try cloneDirectory(source: source, destination: dest)
    }

    private static func cloneDirectory(source: URL, destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { return }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".preparing-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["--clone", source.path, temporary.path]
        let pipe = Pipe()
        task.standardError = pipe
        try task.run()
        // Avoid deadlock on full pipes by draining while the child is running.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let details = String(data: data, encoding: .utf8) ?? "Klonlama başarısız."
            throw NSError(domain: "OpenBottle", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "GPTK ortamı oluşturulamadı: " + details])
        }
        guard fm.fileExists(atPath: temporary.appendingPathComponent("drive_c").path) else {
            throw NSError(domain: "OpenBottle", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "GPTK test kopyası eksik oluşturuldu."])
        }
        // Move into place only after cloning finishes. Never overwrite existing prefixes.
        if !fm.fileExists(atPath: destination.path) { try fm.moveItem(at: temporary, to: destination) }
    }
}
#endif
