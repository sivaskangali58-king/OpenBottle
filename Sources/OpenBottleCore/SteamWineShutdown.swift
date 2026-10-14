import Foundation

/// Stops ONLY the supplied WINEPREFIX before editing a Steam helper binary.
/// No global killall/pkill is used, and there is no automatic Steam relaunch.
public enum SteamWineShutdown {
    public struct Result: Equatable {
        public let success: Bool
        public let message: String
        public let method: String?

        public init(success: Bool, message: String, method: String?) {
            self.success = success
            self.message = message
            self.method = method
        }
    }

    private struct CommandResult {
        let code: Int32?
        let detail: String
        let timedOut: Bool
    }

    public static func stop(prefix: URL, wine: URL, timeout: TimeInterval = 25) -> Result {
        guard WineLocator.isValidExecutable(wine.path) else {
            return Result(success: false, message: "Wine çalıştırılabilir dosyası yok: \(wine.path)", method: nil)
        }
        guard FileManager.default.fileExists(atPath: prefix.path) else {
            return Result(success: false, message: "Şişe klasörü bulunamadı: \(prefix.path)", method: nil)
        }

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        let bin = wine.deletingLastPathComponent()
        env["PATH"] = "\(bin.path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")

        var messages: [String] = []
        let server = bin.appendingPathComponent("wineserver")
        if WineLocator.isValidExecutable(server.path) {
            let outcome = run(server, args: ["-k"], environment: env, timeout: timeout)
            if outcome.code == 0 {
                return Result(success: true, message: "Wine sunucusu kapatıldı (wineserver -k).", method: "wineserver")
            }
            messages.append("wineserver: " + explanation(outcome))
        } else {
            messages.append("wineserver yardımcı programı bulunamadı")
        }

        // wineboot -k uses the same Wine installation as the launch and targets
        // exactly the same prefix, making it a safer fallback than process-name kills.
        let fallback = run(wine, args: ["wineboot", "-k"], environment: env, timeout: timeout)
        if fallback.code == 0 {
            return Result(success: true,
                          message: "Şişe wineboot -k ile kapatıldı. Önceki deneme: \(messages.joined(separator: "; ")).",
                          method: "wineboot")
        }
        messages.append("wineboot: " + explanation(fallback))
        return Result(success: false, message: messages.joined(separator: "; "), method: nil)
    }

    private static func explanation(_ r: CommandResult) -> String {
        if r.timedOut { return "zaman aşımı" + (r.detail.isEmpty ? "" : " (\(r.detail))") }
        return "çıkış kodu \(r.code.map(String.init) ?? "başlatılamadı")" +
            (r.detail.isEmpty ? "" : " (\(r.detail))")
    }

    private static func run(_ executable: URL, args: [String],
                            environment: [String: String], timeout: TimeInterval) -> CommandResult {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("openbottle-stop-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: temp.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: temp) }
        guard let handle = try? FileHandle(forWritingTo: temp) else {
            return CommandResult(code: nil, detail: "Günlük dosyası açılamadı", timedOut: false)
        }
        defer { try? handle.close() }
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = args
        proc.environment = environment
        proc.standardOutput = handle
        proc.standardError = handle
        let done = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in done.signal() }
        do { try proc.run() }
        catch { return CommandResult(code: nil, detail: error.localizedDescription, timedOut: false) }
        let timedOut = done.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            if proc.isRunning { proc.terminate() }
            _ = done.wait(timeout: .now() + 3)
        }
        let data = (try? Data(contentsOf: temp)) ?? Data()
        let detail = String(decoding: data.suffix(1500), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " | ")
        return CommandResult(code: timedOut ? nil : proc.terminationStatus,
                             detail: String(detail.prefix(350)), timedOut: timedOut)
    }
}
