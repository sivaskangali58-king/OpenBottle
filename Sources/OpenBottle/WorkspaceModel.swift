#if os(macOS)
import AppKit
import Foundation
import OpenBottleCore
import SwiftUI

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []
    @Published var selectedID: UUID?
    @Published private(set) var log = "OpenBottle hazır.\n"
    @Published private(set) var isBusy = false
    @Published var wineOverride: String = UserDefaults.standard.string(forKey: "wineExecutable") ?? ""
    @Published var banner: String?
    @Published private(set) var steamSetupStatus: [UUID: String] = [:]
    var gptkInstalled: Bool { EngineLocator.executable(for: .gptk) != nil }
    func steamInstalled(in bottle: Bottle) -> Bool {
        SteamBottleSetup.steamExecutable(in: store.prefix(for: bottle)) != nil
    }

    @Published private(set) var discoveredPrograms: [ProgramCandidate] = []
    @Published private(set) var isScanning = false
    private var scannedBottleID: UUID?
    @Published private(set) var discoveredGames: [GameCandidate] = []
    @Published private(set) var isScanningGames = false
    private var scannedGamesBottleID: UUID?

    private let store = BottleStore()
    private let runner = WineRunner()
    private var steamLaunchGate = SteamLaunchGate()
    private var activeWineBottleID: UUID?
    /// Steam repair may interrupt an installer or Steam client in this *one* prefix.
    private var expectedSteamInterruption: Set<UUID> = []
    private var steamMaintenanceInProgress = false
    @Published private(set) var isCleaningSteamDock = false
    @Published private(set) var artworkRevision = 0
    @Published private(set) var isRefreshingArtwork = false

    init() {
        do {
            bottles = try store.read()
            selectedID = bottles.first?.id
            // Works for games registered by older OpenBottle versions, too.
            Task { [weak self] in await self?.refreshLibraryArtwork() }
        } catch {
            banner = "Kaydedilmiş şişeler okunamadı: \(error.localizedDescription)"
        }
    }

    var selectedBottle: Bottle? { bottles.first(where: { $0.id == selectedID }) }
    var wine: URL? { WineLocator.find(custom: wineOverride) }
    func wine(for bottle: Bottle) -> URL? { EngineLocator.executable(for: bottle.engine, customWine: wineOverride) }
    var canLinkGPTKTest: Bool { store.linkedGPTKPrefixExists() }

    func linkGPTKTest() {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return }
        guard store.linkedGPTKPrefixExists() else { banner = BottleError.missingLinkedPrefix.localizedDescription; return }
        if let existing = bottles.first(where: { $0.linkedPrefixName == "GPTK-Steam-Test" }) {
            selectedID = existing.id; return
        }
        let bottle = Bottle(name: "GPTK – The Guild", engine: .gptk, linkedPrefixName: "GPTK-Steam-Test")
        bottles.append(bottle)
        do { try persist(); selectedID = bottle.id; appendLog("Mevcut GPTK-Steam-Test ortamı bağlandı; dosyalar kopyalanmadı.") }
        catch { bottles.removeAll(where: { $0.id == bottle.id }); banner = "Bağlantı kaydedilemedi: \(error.localizedDescription)" }
    }

    func setEngine(_ engine: WineEngine, for bottle: Bottle) {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return }
        guard bottle.profile != .steam else {
            banner = "Steam şişesinde istemci Wine Staging, oyunlar GPTK ile çalışır. Motor otomatik seçilir."
            return
        }
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].engine = engine
        do { try persist(); appendLog("Motor seçildi: \(engine.title). Şişe dosyaları değişmedi.") }
        catch { banner = error.localizedDescription }
    }

    func scanGames(in bottle: Bottle) {
        guard !isScanningGames else { return }
        isScanningGames = true
        discoveredGames = []
        scannedGamesBottleID = bottle.id
        let prefix = store.prefix(for: bottle)
        let existing = Set(bottle.games.map { $0.relativeExecutablePath })
        let bottleID = bottle.id
        Task.detached(priority: .userInitiated) { [weak self] in
            let games = GameDiscovery.find(in: prefix, excluding: existing)
            await MainActor.run { [weak self] in
                guard let self, self.scannedGamesBottleID == bottleID else { return }
                self.discoveredGames = games
                self.isScanningGames = false
            }
        }
    }

    func registerGames(_ paths: Set<String>, in bottle: Bottle) {
        guard scannedGamesBottleID == bottle.id,
              let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        var count = 0
        for candidate in discoveredGames where paths.contains(candidate.id) {
            guard !bottles[index].games.contains(where: {
                $0.relativeExecutablePath.lowercased() == candidate.relativeExecutablePath.lowercased()
            }) else { continue }
            let item = GameShortcut(title: candidate.title,
                                    relativeExecutablePath: candidate.relativeExecutablePath,
                                    steamAppID: candidate.steamAppID,
                                    artworkRelativePath: candidate.artworkRelativePath)
            guard (try? store.executableURL(for: item, in: bottle)) != nil else { continue }
            bottles[index].games.append(item); count += 1
        }
        do {
            try persist()
            appendLog("Oyun kütüphanesine \(count) oyun eklendi.")
            Task { [weak self] in await self?.refreshLibraryArtwork() }
        } catch { banner = error.localizedDescription }
    }

    func setHUD(_ enabled: Bool, for game: GameShortcut, in bottle: Bottle) {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }),
              let gameIndex = bottles[index].games.firstIndex(where: { $0.id == game.id }) else { return }
        bottles[index].games[gameIndex].showMetalHUD = enabled
        do { try persist() } catch { banner = error.localizedDescription }
    }

    func removeGame(_ game: GameShortcut, in bottle: Bottle) {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].games.removeAll(where: { $0.id == game.id })
        do { try persist(); appendLog("Kısayol kaldırıldı; oyun dosyaları silinmedi.") }
        catch { banner = error.localizedDescription }
    }

    func launchGame(_ game: GameShortcut, in bottle: Bottle) {
        // Steam remains on a Wine Staging prefix. GPTK games use a private APFS clone.
        if bottle.profile == .steam && bottle.effectiveGameEngine == .gptk {
            launchSteamGameWithGPTK(game, in: bottle)
            return
        }
        do {
            let exe = try store.executableURL(for: game, in: bottle)
            let env = ["MTL_HUD_ENABLED": game.showMetalHUD ? "1" : "0"]
            run([exe.path], in: bottle, workingDirectory: exe.deletingLastPathComponent(), extraEnvironment: env)
        } catch { banner = error.localizedDescription }
    }

    private func launchSteamGameWithGPTK(_ game: GameShortcut, in bottle: Bottle) {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return }
        guard gptkInstalled else {
            banner = "GPTK bulunamadı. Şişeler sayfasından GPTK yükle; elle başlatman gerekmiyor."
            return
        }
        // Ensure user didn't select an EXE that no longer exists in the Steam bottle.
        guard (try? store.executableURL(for: game, in: bottle)) != nil else {
            banner = "Steam şişesindeki oyun dosyası bulunamadı. Oyunları yeniden tara."
            return
        }
        let prefix = store.gamePrefix(for: bottle)
        if FileManager.default.fileExists(atPath: prefix.appendingPathComponent("drive_c").path) {
            if (try? store.gptkExecutableURL(for: game, in: bottle)) != nil {
                startGPTKGame(game, in: bottle)
                return
            }
            // Steam installed this game after the GPTK prefix was cloned.
            // Add just the missing installation directory; do not replace the user's GPTK prefix.
            isBusy = true
            appendLog("Yeni Steam oyunu GPTK ortamına aktarılıyor (mevcut oyunlar korunuyor)…")
            let source = store.prefix(for: bottle)
            Task.detached(priority: .utility) { [weak self] in
                let result = Result {
                    try GamePrefixBuilder.addMissingGame(game.relativeExecutablePath,
                                                         steamPrefix: source, gamePrefix: prefix)
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isBusy = false
                    switch result {
                    case .success: self.startGPTKGame(game, in: bottle)
                    case .failure(let error): self.banner = "Oyun GPTK ortamına alınamadı: \(error.localizedDescription)"
                    }
                }
            }
            return
        }
        guard !FileManager.default.fileExists(atPath: prefix.path) else {
            banner = "Eksik GPTK oyun ortamı bulundu. İçeriği silmeden önce yedekle; Etkinlik günlüğünü kontrol et."
            return
        }
        isBusy = true
        appendLog("GPTK oyun ortamı otomatik hazırlanıyor. Steam şişesi olduğu gibi korunacak…")
        let source = store.prefix(for: bottle)
        Task.detached(priority: .utility) { [weak self] in
            let result = Result { try GamePrefixBuilder.prepare(source: source, destination: prefix) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isBusy = false
                switch result {
                case .success:
                    self.appendLog("GPTK oyun ortamı hazır: \(prefix.lastPathComponent)")
                    self.startGPTKGame(game, in: bottle)
                case .failure(let error):
                    self.banner = "GPTK oyun ortamı oluşturulamadı: \(error.localizedDescription)"
                }
            }
        }
    }

    private func startGPTKGame(_ game: GameShortcut, in bottle: Bottle) {
        do {
            let executable = try store.gptkExecutableURL(for: game, in: bottle)
            let env = ["MTL_HUD_ENABLED": game.showMetalHUD ? "1" : "0"]
            run([executable.path], in: bottle, workingDirectory: executable.deletingLastPathComponent(),
                extraEnvironment: env, prefixOverride: store.gamePrefix(for: bottle), engineOverride: .gptk)
        } catch {
            banner = "Oyun GPTK ortamında bulunamadı. Bu oyun Steam'den GPTK klonu oluşturulduktan sonra yüklenmiş olabilir. Mevcut kayıtları korumak için otomatik üzerine yazılmadı."
        }
    }

    func artworkURL(for game: GameShortcut, in bottle: Bottle) -> URL? {
        // Reading this revision makes newly downloaded artwork invalidate SwiftUI cards.
        _ = artworkRevision
        let id = game.steamAppID ?? SteamArtworkLookup.appID(
            forExecutable: game.relativeExecutablePath, in: store.prefix(for: bottle)) ??
            SteamArtworkLookup.knownAppID(for: game.title)
        if let id {
            let downloaded = SteamArtworkLookup.downloadedArtworkURL(for: id, in: store.root)
            if FileManager.default.fileExists(atPath: downloaded.path) { return downloaded }
            if let local = SteamArtworkLookup.localArtwork(for: id, in: store.prefix(for: bottle)) {
                return local
            }
        }
        return store.artworkURL(for: game, in: bottle)
    }

    func refreshArtwork(for game: GameShortcut, in bottle: Bottle) {
        Task { [weak self] in
            guard let self else { return }
            let id = game.steamAppID ?? SteamArtworkLookup.appID(
                forExecutable: game.relativeExecutablePath, in: self.store.prefix(for: bottle)) ??
                SteamArtworkLookup.knownAppID(for: game.title)
            guard let id else {
                self.banner = "Bu oyunun Steam kimliği (AppID) bulunamadı. Steam kurulum dosyalarını kontrol et."
                return
            }
            if await self.downloadArtwork(for: id, force: true) {
                self.appendLog("Oyun kapağı yenilendi: \(game.title)")
            } else {
                self.banner = "Oyun kapağı indirilemedi. İnternet bağlantısını veya Steam kapak kaynağını kontrol et."
            }
        }
    }

    /// Fetches missing images in the background without blocking game launching.
    /// Existing shortcuts are enriched without removing them or changing their EXE.
    func refreshLibraryArtwork() async {
        guard !isRefreshingArtwork else { return }
        isRefreshingArtwork = true
        defer { isRefreshingArtwork = false }
        var ids = Set<Int>()
        var metadataChanged = false
        for bottleIndex in bottles.indices {
            let prefix = store.prefix(for: bottles[bottleIndex])
            for gameIndex in bottles[bottleIndex].games.indices {
                let game = bottles[bottleIndex].games[gameIndex]
                let appID = game.steamAppID ?? SteamArtworkLookup.appID(
                    forExecutable: game.relativeExecutablePath, in: prefix) ??
                    SteamArtworkLookup.knownAppID(for: game.title)
                guard let appID else { continue }
                ids.insert(appID)
                if game.steamAppID == nil {
                    bottles[bottleIndex].games[gameIndex].steamAppID = appID
                    metadataChanged = true
                }
            }
        }
        if metadataChanged {
            do { try persist() }
            catch { appendLog("Oyun görsel bilgisi kaydedilemedi: \(error.localizedDescription)") }
        }
        for id in ids.sorted() {
            // Local Steam assets work offline; don't download duplicates.
            let stored = SteamArtworkLookup.downloadedArtworkURL(for: id, in: store.root)
            if FileManager.default.fileExists(atPath: stored.path) { continue }
            if bottles.contains(where: { bottle in
                bottle.games.contains(where: { $0.steamAppID == id }) &&
                SteamArtworkLookup.localArtwork(for: id, in: store.prefix(for: bottle)) != nil
            }) { continue }
            _ = await downloadArtwork(for: id, force: false)
        }
        artworkRevision &+= 1
    }

    @discardableResult
    private func downloadArtwork(for appID: Int, force: Bool) async -> Bool {
        let output = SteamArtworkLookup.downloadedArtworkURL(for: appID, in: store.root)
        if !force && FileManager.default.fileExists(atPath: output.path) { return true }
        for url in SteamArtworkLookup.portraitURLs(for: appID) {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 12
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      response.statusCode == 200, data.count > 2_000, data.count < 7_000_000,
                      let image = NSBitmapImageRep(data: data),
                      image.pixelsWide >= 120, image.pixelsHigh >= 75 else { continue }
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: output, options: .atomic)
                artworkRevision &+= 1
                return true
            } catch { continue }
        }
        appendLog("Steam kapağı alınamadı (AppID: \(appID)).")
        return false
    }

    var bottleCount: Int { bottles.count }
    var programCount: Int { bottles.reduce(0) { $0 + $1.programs.count } }

    func updateWinePath(_ path: String) {
        wineOverride = path.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(wineOverride, forKey: "wineExecutable")
        appendLog("Wine konumu güncellendi.")
    }

    func createBottle(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { banner = BottleError.emptyName.localizedDescription; return }
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return }
        let bottle = Bottle(name: name)
        do {
            try store.preparePrefix(for: bottle)
            bottles.append(bottle)
            try persist()
            selectedID = bottle.id
            appendLog("Yeni şişe oluşturuldu: \(name)")
            // Creating a prefix is useful even when Wine isn't installed yet.
            if wine != nil { run(["wineboot", "-u"], in: bottle) }
            else { banner = "Şişe hazır, fakat Wine bulunamadı. Wine konumunu Ayarlar'dan seç." }
        } catch { banner = error.localizedDescription }
    }

    /// One-click Steam workflow. Wine Staging runs Steam; GPTK is selected for games.
    /// No copying of Apple-proprietary D3DMetal files into the prefix.
    func createSteamBottle() {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return }
        guard wine != nil else {
            banner = "Wine Staging bulunamadı. Steam kurulumu için önce Wine yükle."
            return
        }
        let b = SteamBottleSetup.makeBottle()
        do {
            try store.preparePrefix(for: b)
            bottles.append(b)
            try persist()
            selectedID = b.id
            steamSetupStatus[b.id] = "Windows ortamı hazırlanıyor…"
            appendLog("Steam şişesi oluşturuldu: Wine Staging (Steam) + GPTK (oyunlar).")
            if !gptkInstalled { appendLog("GPTK henüz yüklü değil; Steam kurulabilir fakat DX12 oyunları için GPTK gerekecek.") }
            run(["wineboot", "-u"], in: b, onSuccess: { [weak self] in
                self?.downloadAndInstallSteam(in: b)
            })
        } catch {
            bottles.removeAll { $0.id == b.id }
            banner = "Steam şişesi oluşturulamadı: \(error.localizedDescription)"
        }
    }

    /// Downloads the official Windows installer after the user's explicit Steam-bottle action.
    /// Download validation avoids passing an HTML error page to Wine as an executable.
    func downloadAndInstallSteam(in bottle: Bottle) {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return }
        guard bottle.profile == .steam, !bottle.isLinked else { return }
        isBusy = true
        steamSetupStatus[bottle.id] = "SteamSetup.exe Valve sunucusundan indiriliyor…"
        appendLog("Steam kurulum dosyası indiriliyor: Valve CDN")
        Task { [weak self] in
            guard let self else { return }
            do {
                let (downloaded, response) = try await URLSession.shared.download(from: SteamBottleSetup.installerURL)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw NSError(domain: "OpenBottle", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Steam indirilemedi (HTTP yanıtı başarısız)."])
                }
                let folder = self.store.installersDirectory.appendingPathComponent(bottle.id.uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let installer = folder.appendingPathComponent("SteamSetup.exe")
                if FileManager.default.fileExists(atPath: installer.path) { try FileManager.default.removeItem(at: installer) }
                try FileManager.default.copyItem(at: downloaded, to: installer)
                guard SteamBottleSetup.isPlausibleInstaller(installer) else {
                    try? FileManager.default.removeItem(at: installer)
                    throw NSError(domain: "OpenBottle", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "İndirilen dosya geçerli bir Windows kurulum dosyasına benzemiyor."])
                }
                self.isBusy = false
                self.steamSetupStatus[bottle.id] = "Steam yükleyicisi açık. Son adımda ‘Steam’i çalıştır’ seçeneğini kapat; ardından OpenBottle’dan başlat."
                self.appendLog("SteamSetup.exe doğrulandı. Kurulum başlıyor.")
                self.run([installer.path], in: bottle, onSuccess: { [weak self] in
                    guard let self else { return }
                    if self.steamInstalled(in: bottle) {
                        self.steamSetupStatus[bottle.id] = "Steam kuruldu. Steam'i başlatabilirsin."
                        self.appendLog("Steam bulundu. Gerekirse Steam UI düzeltmesini uygula.")
                    } else {
                        self.steamSetupStatus[bottle.id] = "Steam dosyası bulunamadı. Kurulum iptal edilmiş olabilir; tekrar dene."
                        self.appendLog("Steam kurulum işlemi çıktı fakat Steam.exe henüz görünmüyor.")
                    }
                })
            } catch {
                self.isBusy = false
                self.steamSetupStatus[bottle.id] = "Steam kurulumu beklemede — tekrar dene."
                self.banner = "Steam indirilemedi: \(error.localizedDescription)"
                self.appendLog("Steam indirme hatası: \(error.localizedDescription)")
            }
        }
    }

    /// Optional in-app Homebrew install, always initiated by explicit user confirmation.
    /// Never invokes sudo and never downloads proprietary binaries for redistribution.
    func installGPTKViaHomebrew() {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return }
        guard !gptkInstalled else { banner = "Game Porting Toolkit zaten yüklü."; return }
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brew = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            banner = "Homebrew bulunamadı. Önce Homebrew kurulmalı; GPTK için Apple lisans koşulları geçerlidir."
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: brew)
        task.arguments = ["install", "--cask", "gcenx/wine/game-porting-toolkit"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        isBusy = true
        appendLog("Kullanıcı onayıyla GPTK Homebrew kurulumu başlıyor.")
        do {
            try task.run()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    if let text = String(data: data, encoding: .utf8) {
                        Task { @MainActor in self?.appendLog(text) }
                    }
                }
                task.waitUntilExit()
                let status = task.terminationStatus
                Task { @MainActor in
                    self?.isBusy = false
                    self?.appendLog("GPTK kurulumu çıktı kodu: \(status)")
                    if status != 0 { self?.banner = "GPTK yüklenemedi. Homebrew çıktılarını Etkinlik sayfasından incele." }
                    else if self?.gptkInstalled == false { self?.banner = "Homebrew tamamlandı ancak GPTK motoru bulunamadı." }
                }
            }
        } catch {
            isBusy = false
            banner = "GPTK kurulum başlatılamadı: \(error.localizedDescription)"
        }
    }

    func renameBottle(_ bottle: Bottle, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { banner = BottleError.emptyName.localizedDescription; return }
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].name = name
        do { try persist(); appendLog("Şişe yeniden adlandırıldı: \(name)") }
        catch { banner = "Şişe adı kaydedilemedi: \(error.localizedDescription)" }
    }

    func scanPrograms(in bottle: Bottle) {
        guard !isScanning else { return }
        isScanning = true
        discoveredPrograms = []
        scannedBottleID = bottle.id
        let prefixURL = store.prefix(for: bottle)
        let existing = Set(bottle.programs.map { $0.relativeExecutablePath })
        let bottleID = bottle.id
        Task.detached(priority: .userInitiated) { [weak self] in
            let candidates = ProgramDiscovery.find(in: prefixURL, excluding: existing)
            await MainActor.run { [weak self] in
                guard let self, self.scannedBottleID == bottleID else { return }
                self.discoveredPrograms = candidates
                self.isScanning = false
            }
        }
    }

    func addDiscoveredPrograms(_ selectedPaths: Set<String>, in bottle: Bottle) {
        guard scannedBottleID == bottle.id,
              let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        var added = 0
        for candidate in discoveredPrograms where selectedPaths.contains(candidate.id) {
            guard !bottles[index].programs.contains(where: {
                $0.relativeExecutablePath.lowercased() == candidate.relativeExecutablePath.lowercased()
            }) else { continue }
            let program = InstalledProgram(title: candidate.title,
                relativeExecutablePath: candidate.relativeExecutablePath)
            guard (try? store.executableURL(for: program, in: bottle)) != nil else { continue }
            bottles[index].programs.append(program)
            added += 1
        }
        do {
            try persist()
            appendLog("Program kütüphanesine \(added) uygulama eklendi.")
        } catch { banner = "Programlar kaydedilemedi: \(error.localizedDescription)" }
    }

    func launchNotepad(in bottle: Bottle) { run(["notepad"], in: bottle) }


    /// Stops only this bottle's Wine processes before modifying Steam's helper.
    /// Steam itself can restart CEF after a crash; stopping the prefix breaks that
    /// loop. Nothing is relaunched after maintenance; launch requires a new click.
    private func withSteamClosed(in bottle: Bottle,
                                 completion: @escaping @MainActor (Bool) -> Void) {
        guard !steamMaintenanceInProgress else {
            banner = "Steam onarımı zaten hazırlanıyor. Lütfen bekle."
            completion(false); return
        }
        guard !isBusy || activeWineBottleID == bottle.id else {
            banner = "Başka bir işlem çalışıyor. Önce tamamlanmasını bekle."
            completion(false); return
        }
        guard let wineExecutable = wine(for: bottle) else {
            banner = BottleError.missingWine.localizedDescription
            completion(false); return
        }
        steamMaintenanceInProgress = true
        expectedSteamInterruption.insert(bottle.id)
        appendLog("Steam onarımı için yalnızca \(bottle.name) şişesindeki Wine işlemleri durduruluyor…")
        let prefix = store.prefix(for: bottle)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Some macOS Wine bundles return a nonzero status for wineserver -k
            // even when Wine can correctly stop the prefix through wineboot -k.
            // Try both without involving other bottles or killing macOS processes.
            let result = SteamWineShutdown.stop(prefix: prefix, wine: wineExecutable)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appendLog("Steam kapatma sonucu: \(result.message)")
                guard result.success else {
                    self.expectedSteamInterruption.remove(bottle.id)
                    self.steamMaintenanceInProgress = false
                    self.banner = "Steam işlemleri kapatılamadı: \(result.message) Steam dosyaları değiştirilmedi."
                    completion(false)
                    return
                }
                // WineRunner's exit callback arrives asynchronously after wineserver -k.
                // Wait briefly, rather than running repair while Wine still holds CEF files.
                for _ in 0..<100 {
                    if !self.isBusy { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                self.expectedSteamInterruption.remove(bottle.id)
                self.steamMaintenanceInProgress = false
                guard !self.isBusy else {
                    self.banner = "Steam zamanında kapanmadı; dosyalar değiştirilmedi."
                    completion(false); return
                }
                self.steamSetupStatus[bottle.id] = "Steam şişesi kapatıldı; siyah ekran onarımı hazırlanıyor."
                self.appendLog("Steam şişesi durduruldu. Onarım kullanıcı onayıyla devam ediyor.")
                completion(true)
            }
        }
    }

    /// On first run a missing/updated helper is inspected BEFORE launching Steam.
    /// The user can repair it without entering the black-screen/restart loop.
    func requestSteamLaunch(in bottle: Bottle, presentRepair: @escaping @MainActor () -> Void) {
        guard !steamMaintenanceInProgress && !isCleaningSteamDock else {
            banner = "Steam bakım işlemi tamamlanmadan başlatılamaz."
            return
        }
        guard !isBusy else {
            banner = "Steam zaten çalışıyor veya kurulumu sürüyor. Onarım için Siyah Ekran Sorunu'nu aç."
            return
        }
        inspectSteamUI(in: bottle) { [weak self] check in
            guard let self else { return }
            switch check.phase {
            case .ready, .changed, .conflict, .damaged, .unknown:
                self.appendLog("Steam başlatılmadan önce CEF durumu kontrol edildi: \(check.phase).")
                presentRepair()
            default:
                // Steam bootstrap may need to run before cef.win64 exists.
                self.launchSteam(in: bottle)
            }
        }
    }

    /// Reads the current status without touching Steam files. Runs off the UI thread.
    func inspectSteamUI(in bottle: Bottle, completion: @escaping @MainActor (SteamRepairCheck) -> Void) {
        guard let resources = Bundle.main.resourceURL else {
            completion(.init(phase: .unknown, hasCompiler: false, hasSteam: false))
            return
        }
        let script = resources.appendingPathComponent("steam-ui-fix.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            completion(.init(phase: .unknown, hasCompiler: false, hasSteam: false))
            return
        }
        let prefix = store.prefix(for: bottle).path
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [script.path, "probe", "--prefix", prefix]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            task.environment = env
            let output = Pipe()
            task.standardOutput = output
            task.standardError = output
            let probe: SteamRepairCheck
            do {
                try task.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                probe = task.terminationStatus == 0
                    ? .parse(String(decoding: data, as: UTF8.self))
                    : .init(phase: .unknown, hasCompiler: false, hasSteam: false)
            } catch {
                probe = .init(phase: .unknown, hasCompiler: false, hasSteam: false)
            }
            Task { @MainActor in completion(probe) }
        }
    }

    /// Compiles the local shim and installs it with the bundled, reversible script.
    /// The action is always confirmed in the UI; patching is not done just because Steam opened.
    func steamUIFix(_ action: String, in bottle: Bottle,
                    completion: (@MainActor (Bool) -> Void)? = nil) {
        guard !bottle.isLinked, bottle.engine == .wineStaging else {
            banner = "Steam UI düzeltmesi yalnızca normal Wine Staging şişelerinde kullanılabilir."
            completion?(false); return
        }
        guard ["install", "restore", "status"].contains(action) else {
            banner = "Bilinmeyen Steam onarım işlemi."
            completion?(false); return
        }
        if action == "install" || action == "restore" {
            withSteamClosed(in: bottle) { [weak self] stopped in
                guard let self else { return }
                if stopped { self.runSteamUIFixScript(action, in: bottle, completion: completion) }
                else { completion?(false) }
            }
            return
        }
        runSteamUIFixScript(action, in: bottle, completion: completion)
    }

    /// Repairs happen only after Wine processes in this Steam prefix are stopped.
    /// The user does not need a separate "Stop Steam" button.
    private func runSteamUIFixScript(_ action: String, in bottle: Bottle,
                                    completion: (@MainActor (Bool) -> Void)? = nil) {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; completion?(false); return }
        guard let resource = Bundle.main.resourceURL else {
            banner = "OpenBottle kaynak klasörü bulunamadı."
            completion?(false); return
        }
        let script = resource.appendingPathComponent("steam-ui-fix.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            banner = "Düzeltme betiği bulunamadı. .app paketini scripts/build-macos.sh ile tekrar oluştur."
            completion?(false); return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [script.path, action, "--prefix", store.prefix(for: bottle).path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        isBusy = true
        appendLog("Steam UI düzeltmesi: \(action)")
        do {
            try task.run()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    if let line = String(data: data, encoding: .utf8) {
                        Task { @MainActor in self?.appendLog(line) }
                    }
                }
                task.waitUntilExit()
                let code = task.terminationStatus
                Task { @MainActor in
                    self?.isBusy = false
                    self?.appendLog("Steam UI işlemi tamamlandı (kod: \(code)).")
                    if code != 0 {
                        self?.banner = "Steam düzeltmesi uygulanamadı. İşlem günlüğünü kontrol et."
                    } else if action == "install" {
                        self?.appendLog("Steam UI düzeltmesi uygulandı. Steam yeniden başlatılabilir.")
                    }
                    completion?(code == 0)
                }
            }
        } catch {
            isBusy = false
            banner = "Steam düzeltmesi başlatılamadı: \(error.localizedDescription)"
            completion?(false)
        }
    }

    /// Optional dependency installation after explicit confirmation. Never uses sudo.
    /// When Homebrew completes successfully, finishes the Steam repair automatically.
    func installRepairCompilerAndFix(in bottle: Bottle, completion: @escaping @MainActor (Bool) -> Void) {
        // Stop Steam BEFORE downloading the compiler. This also breaks the
        // steamwebhelper crash loop without a separate manual Stop button.
        withSteamClosed(in: bottle) { [weak self] stopped in
            guard let self else { completion(false); return }
            if stopped { self.runRepairCompilerInstall(in: bottle, completion: completion) }
            else { completion(false) }
        }
    }

    private func runRepairCompilerInstall(in bottle: Bottle,
                                          completion: @escaping @MainActor (Bool) -> Void) {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; completion(false); return }
        guard let brewPath = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            banner = "Homebrew bulunamadı. mingw-w64 kurulu değil; düzeltme henüz uygulanmadı."
            completion(false)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["install", "mingw-w64"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        isBusy = true
        appendLog("Steam düzeltmesi için mingw-w64 kuruluyor (kullanıcı onayıyla)…")
        do {
            try process.run()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                        Task { @MainActor in self?.appendLog(text) }
                    }
                }
                process.waitUntilExit()
                let code = process.terminationStatus
                Task { @MainActor in
                    self?.isBusy = false
                    if code == 0 {
                        self?.appendLog("mingw-w64 hazır. Düzeltme uygulanıyor…")
                        self?.steamUIFix("install", in: bottle, completion: completion)
                    } else {
                        self?.banner = "mingw-w64 kurulamadı (kod \(code)). Günlüğü incele."
                        completion(false)
                    }
                }
            }
        } catch {
            isBusy = false
            banner = "Derleyici yüklenemedi: \(error.localizedDescription)"
            completion(false)
        }
    }


    /// A confirmed Steam exit also clears stale Steam/Wine Dock tiles.
    /// Never invoked during normal launch, downloads or game startup.
    func exitSteamAndCleanDock(in bottle: Bottle) {
        guard bottle.profile == .steam, !bottle.isLinked else {
            banner = "Dock temizliği yalnızca Steam şişelerinde kullanılabilir."
            return
        }
        guard !isCleaningSteamDock && !steamMaintenanceInProgress else {
            banner = "Steam bakım işlemi zaten devam ediyor."
            return
        }
        guard !isBusy || activeWineBottleID == bottle.id else {
            banner = "Başka bir şişede işlem sürüyor. Önce tamamlanmasını bekle."
            return
        }
        guard let wineExecutable = wine(for: bottle) else {
            banner = BottleError.missingWine.localizedDescription
            return
        }
        let prefix = store.prefix(for: bottle)
        guard let steamExecutable = SteamBottleSetup.steamExecutable(in: prefix) else {
            banner = "Steam.exe bulunamadı."
            return
        }
        isCleaningSteamDock = true
        expectedSteamInterruption.insert(bottle.id)
        appendLog("Steam'e çıkış isteği gönderiliyor; yalnızca seçilen şişedeki süreçler temizlenecek…")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = SteamDockCleanup.close(prefix: prefix, wine: wineExecutable, steam: steamExecutable)
            Task { @MainActor [weak self] in
                guard let self else { return }
                for _ in 0..<70 {
                    if !self.isBusy || self.activeWineBottleID != bottle.id { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                self.expectedSteamInterruption.remove(bottle.id)
                self.isCleaningSteamDock = false
                self.steamLaunchGate.finish(for: bottle.id)
                self.appendLog(result.message)
                self.banner = result.message
            }
        }
    }

    func launchSteam(in bottle: Bottle) {
        guard !steamMaintenanceInProgress && !isCleaningSteamDock else { banner = "Steam bakım işlemi sürüyor; lütfen bekle."; return }
        guard !bottle.isLinked, bottle.engine == .wineStaging else {
            banner = "GPTK test ortamında Steam arayüzü çökebiliyor. Oyunları doğrudan Oyun Kütüphanesi'nden başlat."; return
        }
        let dirs = ["Program Files (x86)/Steam/Steam.exe", "Program Files/Steam/Steam.exe"]
        let prefix = store.prefix(for: bottle)
        guard let exe = dirs.map({ prefix.appendingPathComponent("drive_c/" + $0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            banner = "Bu şişede Steam.exe bulunamadı."; return
        }
        guard steamLaunchGate.beginUserLaunch(for: bottle.id) else {
            banner = "Steam bu şişede zaten başlatıldı. İkinci kez açılmayacak."
            return
        }
        // One explicit click = one launch. On exit (including crash) NO retry.
        // Steam's own internal helper-restart logic is separate from OpenBottle.
        let didStart = run([exe.path, "-noverifyfiles"], in: bottle,
                           onFinish: { [weak self] _ in self?.steamLaunchGate.finish(for: bottle.id) })
        if !didStart { steamLaunchGate.finish(for: bottle.id) }
    }

    func deleteBottle(_ bottle: Bottle) {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return }
        // Delete contents before metadata so that a filesystem error does not silently orphan files.
        do {
            try store.removeFiles(for: bottle) // Linked prefix remains untouched.
            bottles.removeAll(where: { $0.id == bottle.id })
            selectedID = bottles.first?.id
            try persist()
            appendLog(bottle.isLinked ? "Harici şişe bağlantısı kaldırıldı (dosyalar korundu): \(bottle.name)" : "Şişe ve dosyaları silindi: \(bottle.name)")
        } catch { banner = "Silinemedi: \(error.localizedDescription)" }
    }

    func initialize(_ bottle: Bottle) {
        guard !bottle.isLinked else { banner = "Bağlı GPTK ortamında yeniden wineboot çalıştırılmıyor."; return }
        run(["wineboot", "-u"], in: bottle)
    }
    func configure(_ bottle: Bottle) {
        guard !bottle.isLinked else { banner = "Bağlı GPTK test ortamının ayarları korunuyor."; return }
        run(["winecfg"], in: bottle)
    }

    func install(_ url: URL, in bottle: Bottle) {
        guard !bottle.isLinked else {
            banner = "Bağlı GPTK test ortamına yeni kurulum yapılmıyor; ayrı bir şişe oluştur."; return
        }
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try store.copyInstaller(url, for: bottle)
            let args = file.pathExtension.lowercased() == "msi"
                ? ["msiexec", "/i", file.path] : [file.path]
            run(args, in: bottle)
        } catch { banner = "Kurulum dosyası açılamadı: \(error.localizedDescription)" }
    }

    func register(_ file: URL, in bottle: Bottle) {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        do {
            let relative = try store.relativePath(of: file, in: bottle)
            guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
            guard !bottles[index].programs.contains(where: { $0.relativeExecutablePath == relative }) else {
                banner = "Bu program zaten listede."; return
            }
            let program = InstalledProgram(title: file.deletingPathExtension().lastPathComponent,
                                           relativeExecutablePath: relative)
            bottles[index].programs.append(program)
            try persist()
            appendLog("Program eklendi: \(program.title)")
        } catch { banner = error.localizedDescription }
    }

    func removeProgram(_ program: InstalledProgram, from bottle: Bottle) {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].programs.removeAll(where: { $0.id == program.id })
        do { try persist() } catch { banner = error.localizedDescription }
        appendLog("Program listeden çıkarıldı: \(program.title) (dosyalar silinmedi)")
    }

    func launch(_ program: InstalledProgram, in bottle: Bottle) {
        do {
            let executable = try store.executableURL(for: program, in: bottle)
            run([executable.path], in: bottle)
        } catch { banner = error.localizedDescription }
    }

    func openBottleFolder(_ bottle: Bottle) {
        do {
            try store.preparePrefix(for: bottle)
            NSWorkspace.shared.open(store.prefix(for: bottle))
        } catch { banner = error.localizedDescription }
    }

    @discardableResult
    func run(_ args: [String], in bottle: Bottle,
             workingDirectory: URL? = nil, extraEnvironment: [String: String] = [:],
             prefixOverride: URL? = nil, engineOverride: WineEngine? = nil,
             onSuccess: (() -> Void)? = nil,
             onFinish: ((Int32) -> Void)? = nil) -> Bool {
        guard !isBusy else { banner = BottleError.operationInProgress.localizedDescription; return false }
        guard let wine = EngineLocator.executable(for: engineOverride ?? bottle.engine, customWine: wineOverride) else {
            banner = BottleError.missingWine.localizedDescription; return false
        }
        do {
            try store.preparePrefix(for: bottle)
            isBusy = true
            activeWineBottleID = bottle.id
            appendLog("▶ \(wine.lastPathComponent) \(args.joined(separator: " "))")
            try runner.run(wine: wine, prefix: prefixOverride ?? store.prefix(for: bottle), arguments: args,
                workingDirectory: workingDirectory, extraEnvironment: extraEnvironment,
                output: { [weak self] text in self?.appendLog(text) },
                completion: { [weak self] code in
                    guard let self else { return }
                    let interruptedForRepair = self.expectedSteamInterruption.contains(bottle.id)
                    self.activeWineBottleID = nil
                    self.isBusy = false
                    self.appendLog("İşlem tamamlandı (çıkış kodu: \(code)).")
                    onFinish?(code)
                    if interruptedForRepair {
                        self.appendLog("İşlem Steam onarımı için kontrollü olarak durduruldu; yeniden başlatılmayacak.")
                    } else if code != 0 {
                        self.banner = "Wine işleminden hata kodu \(code) döndü. Günlüğü kontrol et."
                    } else { onSuccess?() }
                })
            return true
        } catch {
            activeWineBottleID = nil
            isBusy = false
            banner = "Wine başlatılamadı: \(error.localizedDescription)"
            appendLog("HATA: \(error.localizedDescription)")
            return false
        }
    }

    private func persist() throws { try store.write(bottles) }
    private func appendLog(_ text: String) {
        log += (log.hasSuffix("\n") ? "" : "\n") + text
        // Cap log size for a long-lived session.
        if log.count > 45_000 { log = String(log.suffix(30_000)) }
    }
}
#endif
