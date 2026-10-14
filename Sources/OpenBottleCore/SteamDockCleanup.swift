import Foundation

/// Exits Steam in the selected bottle, then cleans up leftover Wine processes.
/// NEVER called on its own: UI requires explicit user confirmation because
/// active Steam downloads and any other Windows apps in this prefix will stop.
/// Wine processes are not the OpenBottle macOS app process.
public enum SteamDockCleanup {
    public struct Result: Equatable {
        public let success: Bool
        public let message: String
        public init(success: Bool, message: String) {
            self.success = success; self.message = message
        }
    }

    public static func close(prefix: URL, wine: URL, steam: URL,
                             quitTimeout: TimeInterval = 12,
                             stopTimeout: TimeInterval = 20) -> Result {
        guard WineLocator.isValidExecutable(wine.path) else {
            return .init(success: false, message: "Wine motoru bulunamadı.")
        }
        guard FileManager.default.fileExists(atPath: prefix.appendingPathComponent("drive_c").path) else {
            return .init(success: false, message: "Steam şişesi bulunamadı.")
        }
        let standardizedPrefix = prefix.standardizedFileURL.path
        guard steam.standardizedFileURL.path.hasPrefix(standardizedPrefix + "/drive_c/") else {
            return .init(success: false, message: "Steam çalıştırılabilir dosyası seçilen şişeye ait değil.")
        }

        var note = ""
        if FileManager.default.fileExists(atPath: steam.path) {
            let graceful = requestQuit(wine: wine, prefix: prefix, steam: steam, timeout: quitTimeout)
            note = graceful ? "Steam'e çıkış isteği gönderildi. " : "Steam çıkış isteği yanıtlamadı. "
        }
        // Scope every shutdown command to the selected WINEPREFIX: do not use
        // killall, pkill, global Dock restarts or modification of Wine.app.
        let cleanup = SteamWineShutdown.stop(prefix: prefix, wine: wine, timeout: stopTimeout)
        return .init(success: cleanup.success,
                     message: note + (cleanup.success
                         ? "Bu şişedeki Wine süreçleri temizlendi. Dock simgeleri kaybolmalıdır."
                         : "Wine süreçleri temizlenemedi: " + cleanup.message))
    }

    private static func requestQuit(wine: URL, prefix: URL, steam: URL,
                                    timeout: TimeInterval) -> Bool {
        let task = Process()
        task.executableURL = wine
        task.arguments = [steam.path, "-shutdown"]
        task.currentDirectoryURL = steam.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        env["PATH"] = wine.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        task.environment = env
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        do { try task.run() } catch { return false }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            if task.isRunning { task.terminate() }
            _ = done.wait(timeout: .now() + 2)
            return false
        }
        return task.terminationStatus == 0
    }
}
