#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpenBottleCore

private enum OBPage: String, CaseIterable, Identifiable {
    case overview, games, bottles, activity, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Ana Sayfa"
        case .games: return "Kütüphane"
        case .bottles: return "Şişeler"
        case .activity: return "Etkinlik"
        case .settings: return "Ayarlar"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .games: return "gamecontroller.fill"
        case .bottles: return "shippingbox.fill"
        case .activity: return "terminal.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// A single sheet coordinator avoids competing `.sheet` modifiers on the same view.
private enum OBModal: Identifiable {
    case settings
    case games(Bottle)
    case discovery(Bottle)
    case steamRepair(Bottle)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .games(let bottle): return "games-\(bottle.id.uuidString)"
        case .discovery(let bottle): return "discovery-\(bottle.id.uuidString)"
        case .steamRepair(let bottle): return "steam-repair-\(bottle.id.uuidString)"
        }
    }
}

private struct GameEntry: Identifiable {
    let bottle: Bottle
    let game: GameShortcut
    var id: UUID { game.id }
}

private struct ProgramEntry: Identifiable {
    let bottle: Bottle
    let program: InstalledProgram
    var id: UUID { program.id }
}

private struct GameArtworkView: View {
    let title: String
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [OB.accent.opacity(0.30), OB.purple.opacity(0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: min(width, height) * 0.28, weight: .light))
                        .foregroundStyle(OB.text.opacity(0.85))
                }
                .overlay(alignment: .bottomLeading) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OB.text.opacity(0.95))
                        .lineLimit(2)
                        .padding(8)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(OB.border.opacity(0.8), lineWidth: 1))
    }
}

struct MainView: View {
    @StateObject private var model = WorkspaceModel()
    @State private var page: OBPage = .overview
    @State private var search = ""
    @State private var showingNewBottle = false
    @State private var newName = "Windows 10"
    @State private var showingInstaller = false
    @State private var showingProgramPicker = false
    @State private var showingDelete = false
    @State private var showingRename = false
    @State private var showingSteamExitConfirmation = false
    @State private var renameText = ""
    @State private var confirmGPTKInstall = false
    @State private var activeModal: OBModal?
    @State private var showLogInBottle = false
    @State private var showBottleAdvanced = false
    @State private var showLibraryApps = false
    @State private var showSettingsAdvanced = false

    private var allGames: [GameEntry] {
        model.bottles.flatMap { bottle in
            bottle.games.map { GameEntry(bottle: bottle, game: $0) }
        }
    }
    private var allPrograms: [ProgramEntry] {
        model.bottles.flatMap { bottle in
            bottle.programs.map { ProgramEntry(bottle: bottle, program: $0) }
        }
    }
    private var visibleGames: [GameEntry] {
        allGames.filter { search.isEmpty || $0.game.title.localizedCaseInsensitiveContains(search)
            || $0.bottle.name.localizedCaseInsensitiveContains(search) }
    }
    private var visiblePrograms: [ProgramEntry] {
        allPrograms.filter { search.isEmpty || $0.program.title.localizedCaseInsensitiveContains(search)
            || $0.bottle.name.localizedCaseInsensitiveContains(search) }
    }
    private var featuredGame: GameEntry? {
        allGames.first(where: { $0.game.title.localizedCaseInsensitiveContains("guild") }) ?? allGames.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 212)
            Rectangle().fill(OB.border.opacity(0.75)).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                Rectangle().fill(OB.border.opacity(0.7)).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        switch page {
                        case .overview: overviewPage
                        case .games: gamesPage
                        case .bottles: bottlesPage
                        case .activity: activityPage
                        case .settings: settingsPage
                        }
                    }
                    .frame(maxWidth: 1250, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 29)
                    .frame(maxWidth: .infinity)
                }
                .background(OB.canvas)
            }
        }
        .frame(minWidth: 890, minHeight: 630)
        .background(OB.canvas)
        .preferredColorScheme(.dark)
        .tint(OB.accent)
        .alert("Yeni şişe", isPresented: $showingNewBottle) {
            TextField("Şişe adı", text: $newName)
            Button("Oluştur") { model.createBottle(newName); page = .bottles }
            Button("İptal", role: .cancel) {}
        } message: { Text("Her şişe ayrı bir Windows ortamıdır.") }
        .confirmationDialog(model.selectedBottle?.isLinked == true
                            ? "Bağlantı kaldırılsın mı? GPTK test dosyaları korunacak."
                            : "Bu şişe ve içindeki tüm dosyalar kalıcı olarak silinsin mi?",
                            isPresented: $showingDelete) {
            Button(model.selectedBottle?.isLinked == true ? "Bağlantıyı Kaldır" : "Şişeyi Sil", role: .destructive) {
                if let bottle = model.selectedBottle { model.deleteBottle(bottle) }
            }
        }
        .confirmationDialog("GPTK yükleme izni", isPresented: $confirmGPTKInstall) {
            Button("Homebrew üzerinden GPTK yükle") { model.installGPTKViaHomebrew() }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("OpenBottle, Homebrew aracılığıyla gcenx/wine/game-porting-toolkit paketini kurmayı deneyecek. Apple GPTK ayrı lisanslıdır ve bu uygulama paketine dahil değildir. Gerekirse Homebrew ek izin isteyebilir.")
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .settings:
                SettingsView(model: model)
            case .games(let bottle):
                GameDiscoverySheet(model: model, bottle: bottle)
            case .discovery(let bottle):
                ProgramDiscoverySheet(model: model, bottle: bottle)
            case .steamRepair(let bottle):
                SteamRepairSheet(model: model, bottle: bottle)
            }
        }
        .alert("Şişeyi yeniden adlandır", isPresented: $showingRename) {
            TextField("Şişe adı", text: $renameText)
            Button("Kaydet") {
                if let bottle = model.selectedBottle { model.renameBottle(bottle, to: renameText) }
            }
            Button("İptal", role: .cancel) {}
        }
        .fileImporter(isPresented: $showingInstaller, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let file):
                if let bottle = model.selectedBottle { model.install(file, in: bottle) }
            case .failure(let error): model.banner = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showingProgramPicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let file):
                if let bottle = model.selectedBottle { model.register(file, in: bottle) }
            case .failure(let error): model.banner = error.localizedDescription
            }
        }
        .alert("OpenBottle", isPresented: Binding(
            get: { model.banner != nil },
            set: { if !$0 { model.banner = nil } }
        )) {
            Button("Tamam", role: .cancel) { model.banner = nil }
        } message: { Text(model.banner ?? "") }
    }

    // MARK: - Navigation

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(OB.canvas)
                    .frame(width: 40, height: 40)
                    .background(OB.accent, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenBottle")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(OB.text)
                    Text("Windows, Mac'inde.")
                        .font(.system(size: 10))
                        .foregroundStyle(OB.muted)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 27)
            .padding(.bottom, 34)

            ForEach([OBPage.overview, .games, .bottles], id: \.self) { item in
                sidebarRow(item)
            }

            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 14) {
                if model.isBusy {
                    Label("İşlem devam ediyor", systemImage: "hourglass")
                        .font(.system(size: 11))
                        .foregroundStyle(OB.muted)
                }
                Button { page = .settings } label: {
                    Label("Ayarlar", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: page == .settings ? .semibold : .medium))
                .foregroundStyle(page == .settings ? OB.accent : OB.muted)
                .padding(.vertical, 10)
                .accessibilityLabel("Ayarları aç")
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .background(OB.sidebar)
    }

    private func sidebarRow(_ item: OBPage) -> some View {
        Button { page = item } label: {
            HStack(spacing: 14) {
                Image(systemName: item.icon).font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(item.title).font(.system(size: 13, weight: page == item ? .semibold : .medium))
                Spacer()
                if item == .games && !allGames.isEmpty {
                    Text("\(allGames.count)").font(.caption2)
                }
            }
            .foregroundStyle(page == item ? OB.accent : OB.muted)
            .padding(.horizontal, 15).padding(.vertical, 12)
            .background(page == item ? OB.accent.opacity(0.105) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay(alignment: .leading) {
                if page == item {
                    RoundedRectangle(cornerRadius: 3).fill(OB.accent)
                        .frame(width: 3, height: 23)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    private var topbar: some View {
        HStack(spacing: 14) {
            Text(page.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OB.text)
            Spacer()
            if page == .games {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(OB.muted)
                    TextField("Ara", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(OB.muted)
                        .accessibilityLabel("Aramayı temizle")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: 200)
                .background(OB.panel, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 7) {
                if model.isBusy { ProgressView().controlSize(.small) }
                else { Circle().fill(OB.green).frame(width: 7, height: 7) }
                Text(model.isBusy ? "Çalışıyor" : "Hazır")
                    .font(.system(size: 11))
                    .foregroundStyle(OB.muted)
            }
        }
        .padding(.horizontal, 30)
        .frame(height: 60)
        .background(OB.canvas)
    }

    // MARK: - Overview

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Oyunların, tek yerde.")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(OB.text)
                Text("Windows oyunlarını Mac'inde kolayca aç.")
                    .font(.system(size: 13))
                    .foregroundStyle(OB.muted)
            }
            featuredHero
            HStack {
                OBSectionTitle(title: "Kütüphanem", detail: allGames.isEmpty ? "Henüz oyun yok" : "\(allGames.count) oyun")
                Spacer()
                Button("Tümünü gör") { page = .games }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OB.accent)
                    .buttonStyle(.plain)
            }
            if allGames.isEmpty {
                emptyCollection(icon: "gamecontroller.fill", title: "Oyunların burada görünecek",
                                subtitle: "Steam'den bir oyun yükledikten sonra şişende oyunları bul.",
                                button: "Şişelere Git") { page = .bottles }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], spacing: 12) {
                    ForEach(Array(allGames.prefix(4))) { entry in gameCard(entry) }
                }
            }
            // Only show setup when the user has no Steam environment yet.
            if !model.bottles.contains(where: { $0.profile == .steam }) {
                OBPanel {
                    HStack(spacing: 18) {
                        OBIcon(name: "shippingbox.fill", tint: OB.accent, size: 46)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Steam kurmak ister misin?")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(OB.text)
                            Text("OpenBottle gerekli ortamı otomatik hazırlar.")
                                .font(.system(size: 11))
                                .foregroundStyle(OB.muted)
                        }
                        Spacer(minLength: 10)
                        Button { model.createSteamBottle(); page = .bottles } label: {
                            Label("Steam Kur", systemImage: "plus")
                        }
                        .buttonStyle(OBPrimaryButtonStyle())
                        .disabled(model.isBusy)
                    }
                }
            }
        }
    }

    // Decorative rings belong in the background, not the measuring ZStack.
    // The old 350pt circles inflated layout, while .frame(height: 230) clipped
    // the title and primary action. Keep the whole content in the card instead.
    private var featuredHero: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Circle().fill(OB.green).frame(width: 7, height: 7)
                    Text(featuredGame == nil ? "HER ŞEY HAZIR" : "OYUNA HAZIR")
                        .tracking(1.6)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(OB.accent)
                }

                Text(featuredGame?.game.title ?? "Oyun dünyan burada başlar")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(OB.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Text(featuredGame.map { entry in
                    "\(entry.bottle.name)  ·  \(entry.bottle.effectiveGameEngine == .gptk ? "Game Porting Toolkit" : "Wine Staging")"
                } ?? "Şişeni bağla ve ilk oyununu ekle.")
                    .font(.system(size: 12))
                    .foregroundStyle(OB.text.opacity(0.76))
                    .lineLimit(2)

                Spacer(minLength: 5)

                HStack(spacing: 10) {
                    Button {
                        if let entry = featuredGame { model.launchGame(entry.game, in: entry.bottle) }
                        else { page = .bottles }
                    } label: {
                        Label(featuredGame == nil ? "Şişelere Git" : "Oyunu Başlat",
                              systemImage: featuredGame == nil ? "shippingbox.fill" : "play.fill")
                    }
                    .buttonStyle(OBPrimaryButtonStyle())
                    .disabled(model.isBusy && featuredGame != nil)

                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if let featuredGame {
                GameArtworkView(title: featuredGame.game.title,
                                url: model.artworkURL(for: featuredGame.game, in: featuredGame.bottle),
                                width: 150, height: 200)
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 83, weight: .ultraLight))
                    .foregroundStyle(OB.accent.opacity(0.40))
                    .rotationEffect(.degrees(-12))
                    .frame(width: 130, height: 130)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 194, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x183F48), Color(hex: 0x1E2A48), Color(hex: 0x182130)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    GeometryReader { geometry in
                        ZStack {
                            Circle()
                                .stroke(OB.accent.opacity(0.12), lineWidth: 1)
                                .frame(width: 320, height: 320)
                                .position(x: geometry.size.width - 95, y: geometry.size.height / 2)
                            Circle()
                                .stroke(OB.accent.opacity(0.13), lineWidth: 1)
                                .frame(width: 230, height: 230)
                                .position(x: geometry.size.width - 95, y: geometry.size.height / 2)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .allowsHitTesting(false)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(OB.accent.opacity(0.18), lineWidth: 1))
    }

    private func engineRow(_ title: String, icon: String, ready: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 17).foregroundStyle(OB.muted)
            Text(title).font(.system(size: 12)).foregroundStyle(OB.text)
            Spacer()
            OBTag(title: ready ? "Bulundu" : "Bulunamadı", tint: ready ? OB.green : OB.amber)
        }
    }

    // MARK: - Library

    private var gamesPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageTitle("Kütüphanem", subtitle: "Oyunlarını ve uygulamalarını buradan çalıştır.")
            if visibleGames.isEmpty {
                emptyCollection(icon: "gamecontroller.fill",
                                title: allGames.isEmpty ? "Henüz oyun yok" : "Oyun bulunamadı",
                                subtitle: allGames.isEmpty ? "Şişene Steam'den bir oyun kurduktan sonra tarayabilirsin." : "Başka bir şey ara.",
                                button: allGames.isEmpty ? "Şişelere Git" : "Aramayı Temizle") {
                    if allGames.isEmpty { page = .bottles } else { search = "" }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 13)], spacing: 13) {
                    ForEach(visibleGames) { entry in gameCard(entry) }
                }
            }

            if !allPrograms.isEmpty {
                OBPanel {
                    DisclosureGroup(isExpanded: $showLibraryApps) {
                        VStack(spacing: 10) {
                            ForEach(visiblePrograms) { entry in
                                HStack(spacing: 11) {
                                    OBIcon(name: "app.fill", tint: OB.purple, size: 38)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.program.title).font(.system(size: 13, weight: .medium)).foregroundStyle(OB.text)
                                        Text(entry.bottle.name).font(.system(size: 11)).foregroundStyle(OB.muted)
                                    }
                                    Spacer()
                                    Button("Aç") { model.launch(entry.program, in: entry.bottle) }
                                        .buttonStyle(OBSecondaryButtonStyle())
                                        .disabled(model.isBusy)
                                }
                            }
                        }.padding(.top, 13)
                    } label: {
                        Label("Uygulamalar (\(allPrograms.count))", systemImage: "square.stack.3d.up")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(OB.text)
                    }
                }
            }
        }
    }

    private func gameCard(_ entry: GameEntry) -> some View {
        OBPanel(padding: 15) {
            HStack(alignment: .top, spacing: 13) {
                GameArtworkView(title: entry.game.title,
                                url: model.artworkURL(for: entry.game, in: entry.bottle),
                                width: 74, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.game.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OB.text)
                        .lineLimit(2)
                    Text(entry.bottle.name)
                        .font(.system(size: 11))
                        .foregroundStyle(OB.muted)
                        .lineLimit(1)
                    Text(entry.bottle.effectiveGameEngine == .gptk ? "GPTK ile çalıştırılır" : "Wine ile çalıştırılır")
                        .font(.system(size: 10))
                        .foregroundStyle(OB.muted)
                        .padding(.top, 2)

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        Button { model.launchGame(entry.game, in: entry.bottle) } label: {
                            Label("Oyna", systemImage: "play.fill")
                        }
                        .buttonStyle(OBPrimaryButtonStyle())
                        .disabled(model.isBusy)
                        .help("\(entry.game.title) oyununu başlat")
                        .accessibilityLabel("\(entry.game.title) oyununu başlat")

                        Menu {
                            Toggle("FPS göstergesi", isOn: Binding(
                                get: { entry.game.showMetalHUD },
                                set: { model.setHUD($0, for: entry.game, in: entry.bottle) }
                            ))
                            Button("Şişeyi Göster") { model.selectedID = entry.bottle.id; page = .bottles }
                            Button("Kapak görselini yenile") {
                                model.refreshArtwork(for: entry.game, in: entry.bottle)
                            }
                            Divider()
                            Button("Kütüphaneden Kaldır") { model.removeGame(entry.game, in: entry.bottle) }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .buttonStyle(OBSecondaryButtonStyle())
                        .menuStyle(.borderlessButton)
                        .help("Diğer oyun seçenekleri")
                        .accessibilityLabel("Diğer oyun seçenekleri")
                    }
                }
            }
        }
    }

    // MARK: - Bottles

    private var bottlesPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                pageTitle("Şişelerim", subtitle: "Oyunların ve programların için Windows ortamları.")
                Spacer(minLength: 20)
                Menu {
                    Button("Steam Şişesi Oluştur") { model.createSteamBottle() }
                        .disabled(model.isBusy)
                    Button("Boş Şişe Oluştur") { showingNewBottle = true }
                    if model.canLinkGPTKTest {
                        Divider()
                        Button("Mevcut GPTK Ortamını Bağla") { model.linkGPTKTest() }
                            .disabled(model.isBusy)
                    }
                } label: { Label("Yeni Şişe", systemImage: "plus") }
                    .buttonStyle(OBPrimaryButtonStyle())
            }
            if model.bottles.isEmpty {
                emptyCollection(icon: "shippingbox.fill", title: "Henüz şişen yok",
                                subtitle: "Steam için yeni bir ortam hazırlamakla başlayabilirsin.",
                                button: "Steam Kur") { model.createSteamBottle() }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(model.bottles) { bottle in
                            Button { model.selectedID = bottle.id; showBottleAdvanced = false } label: {
                                HStack(spacing: 10) {
                                    OBIcon(name: bottle.profile == .steam ? "gamecontroller.fill" : "shippingbox.fill",
                                           tint: bottle.profile == .steam ? OB.accent : OB.purple, size: 39)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bottle.name).font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(OB.text).lineLimit(1)
                                        Text(bottle.profile == .steam ? "Steam" : bottle.engine == .gptk ? "Oyun ortamı" : "Windows ortamı")
                                            .font(.system(size: 10)).foregroundStyle(OB.muted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .frame(width: 213, alignment: .leading)
                                .background(model.selectedID == bottle.id ? OB.panelLight : OB.panel,
                                            in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(model.selectedID == bottle.id ? OB.accent : OB.border, lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 2)
                }
                if let bottle = model.selectedBottle { bottleDetails(bottle) }
            }
        }
    }

    private func bottleDetails(_ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 19) {
            OBPanel(padding: 22) {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(spacing: 14) {
                        OBIcon(name: bottle.profile == .steam ? "gamecontroller.fill" : "shippingbox.fill",
                               tint: OB.accent, size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(bottle.name).font(.system(size: 22, weight: .bold)).foregroundStyle(OB.text)
                            Text(bottle.profile == .steam ? "Steam ve oyunların" : "Windows ortamı")
                                .font(.system(size: 11)).foregroundStyle(OB.muted)
                        }
                        Spacer(minLength: 0)
                        OBTag(title: model.wine(for: bottle) == nil ? "Motor eksik" : "Hazır",
                              tint: model.wine(for: bottle) == nil ? OB.amber : OB.green)
                        Menu {
                            Button("Yeniden Adlandır") { renameText = bottle.name; showingRename = true }
                            Button("Klasörü Aç") { model.openBottleFolder(bottle) }
                            if bottle.profile == .steam && model.steamInstalled(in: bottle) {
                                Button("Steam'den Çık ve Dock'u Temizle") {
                                    showingSteamExitConfirmation = true
                                }.disabled(model.isCleaningSteamDock)
                            }
                            Divider()
                            Button(bottle.isLinked ? "Bağlantıyı Kaldır" : "Şişeyi Sil", role: .destructive) {
                                showingDelete = true
                            }.disabled(model.isBusy)
                        } label: { Image(systemName: "ellipsis") }
                            .buttonStyle(OBSecondaryButtonStyle())
                            .menuStyle(.borderlessButton)
                            .confirmationDialog("Steam'den çıkıp Dock'u temizle?",
                                isPresented: $showingSteamExitConfirmation,
                                titleVisibility: .visible) {
                                Button("Steam'den Çık ve Temizle", role: .destructive) {
                                    model.exitSteamAndCleanDock(in: bottle)
                                }
                                Button("İptal", role: .cancel) {}
                            } message: {
                                Text("Bu Steam şişesindeki tüm Windows işlemleri kapanacak. İndirmelerin ve bulut eşitlemenin bitmesini bekle. Steam ve oyun dosyaları silinmez.")
                            }
                    }

                    if bottle.profile == .steam {
                        Text(model.steamSetupStatus[bottle.id] ??
                             (model.steamInstalled(in: bottle)
                              ? "Steam hazır. Oyunlar GPTK ile otomatik açılır."
                              : "Steam kurulumu tamamlandığında buradan başlatabilirsin."))
                            .font(.system(size: 12))
                            .foregroundStyle(OB.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        if bottle.profile == .steam {
                            if model.steamInstalled(in: bottle) {
                                Button { model.requestSteamLaunch(in: bottle) { activeModal = .steamRepair(bottle) } } label: {
                                    Label("Steam'i Aç", systemImage: "play.fill")
                                }.buttonStyle(OBPrimaryButtonStyle()).disabled(model.isBusy)
                                Button { activeModal = .steamRepair(bottle) } label: {
                                    Label("Siyah Ekran Sorunu", systemImage: "wrench.adjustable")
                                }.buttonStyle(OBSecondaryButtonStyle())
                            } else {
                                Button { model.downloadAndInstallSteam(in: bottle) } label: {
                                    Label("Steam'i Kur", systemImage: "arrow.down.to.line")
                                }.buttonStyle(OBPrimaryButtonStyle()).disabled(model.isBusy)
                            }
                            Button { activeModal = .games(bottle) } label: {
                                Label("Oyunları Bul", systemImage: "magnifyingglass")
                            }.buttonStyle(OBSecondaryButtonStyle()).disabled(model.isBusy)
                        } else {
                            Button { showingInstaller = true } label: {
                                Label("Program Yükle", systemImage: "square.and.arrow.down")
                            }.buttonStyle(OBPrimaryButtonStyle()).disabled(bottle.isLinked || model.isBusy)
                            Button { activeModal = .games(bottle) } label: {
                                Label("Oyunları Bul", systemImage: "magnifyingglass")
                            }.buttonStyle(OBSecondaryButtonStyle())
                        }
                    }

                    if bottle.profile == .steam && !model.gptkInstalled {
                        HStack(spacing: 11) {
                            Label("Oyun motoru (GPTK) eksik", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(OB.amber)
                            Spacer()
                            Button("Yükle") { confirmGPTKInstall = true }
                                .buttonStyle(OBSecondaryButtonStyle()).disabled(model.isBusy)
                        }
                    }
                }
            }

            if !bottle.games.isEmpty {
                HStack {
                    OBSectionTitle(title: "Oyunlar", detail: "\(bottle.games.count)")
                    Spacer()
                    Button("Oyunları Tara") { if let b = model.selectedBottle { activeModal = .games(b) } }
                        .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(OB.accent)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], spacing: 12) {
                    ForEach(bottle.games) { game in
                        gameCard(GameEntry(bottle: bottle, game: game))
                    }
                }
            }
            if !bottle.programs.isEmpty {
                OBPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        OBSectionTitle(title: "Uygulamalar", detail: "\(bottle.programs.count)")
                        ForEach(bottle.programs) { program in
                            HStack(spacing: 10) {
                                Image(systemName: "app.fill").foregroundStyle(OB.purple)
                                Text(program.title).font(.system(size: 12)).foregroundStyle(OB.text)
                                Spacer()
                                Button("Aç") { model.launch(program, in: bottle) }
                                    .buttonStyle(OBSecondaryButtonStyle()).disabled(model.isBusy)
                            }
                        }
                    }
                }
            }

            OBPanel {
                DisclosureGroup(isExpanded: $showBottleAdvanced) {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Normal kullanımda bu seçenekleri değiştirmen gerekmez.")
                            .font(.system(size: 11)).foregroundStyle(OB.muted)
                        HStack(spacing: 9) {
                            Button("EXE / MSI Yükle") { showingInstaller = true }
                                .disabled(bottle.isLinked || model.isBusy)
                            Button("Uygulamaları Tara") { if let b = model.selectedBottle { activeModal = .discovery(b) } }
                            Button("EXE Ekle") { showingProgramPicker = true }
                        }
                        .buttonStyle(OBSecondaryButtonStyle())
                        HStack(spacing: 9) {
                            Button("Wine Ayarları") { model.configure(bottle) }
                                .disabled(model.isBusy || bottle.isLinked)
                            Button("Prefix'i Hazırla") { model.initialize(bottle) }
                                .disabled(model.isBusy || bottle.isLinked)
                            Button("Not Defteri") { model.launchNotepad(in: bottle) }
                                .disabled(model.isBusy)
                        }
                        .buttonStyle(OBSecondaryButtonStyle())
                        HStack(spacing: 14) {
                            Text("Motor")
                                .font(.system(size: 12)).foregroundStyle(OB.muted)
                            Picker("Çalıştırma motoru", selection: Binding(
                                get: { bottle.engine },
                                set: { model.setEngine($0, for: bottle) }
                            )) {
                                ForEach(WineEngine.allCases) { engine in Text(engine.title).tag(engine) }
                            }
                            .labelsHidden().frame(maxWidth: 230)
                            .disabled(model.isBusy || bottle.isLinked || bottle.profile == .steam)
                        }
                        if bottle.profile == .steam {
                            Text("Steam için Wine Staging, oyunlar için GPTK otomatik kullanılır.")
                                .font(.system(size: 11)).foregroundStyle(OB.muted)
                        }
                        DisclosureGroup(isExpanded: $showLogInBottle) {
                            logContent.frame(height: 180)
                        } label: {
                            Label("İşlem günlüğü", systemImage: "terminal")
                                .font(.system(size: 12)).foregroundStyle(OB.text)
                        }
                    }.padding(.top, 15)
                } label: {
                    Label("Gelişmiş Seçenekler", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(OB.text)
                }
            }
        }
    }

    // MARK: - Activity and settings

    private var activityPage: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                pageTitle("İşlem Günlüğü", subtitle: "Wine süreçleri ve hata mesajları.")
                Spacer()
                Button("Ayarlara Dön") { page = .settings }
                    .buttonStyle(OBSecondaryButtonStyle())
            }
            OBPanel {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        OBSectionTitle(title: "Terminal çıktısı", detail: model.isBusy ? "İşlem sürüyor" : "Güncel")
                        Spacer()
                        Button { copyLog() } label: { Label("Günlüğü Kopyala", systemImage: "doc.on.doc") }
                            .buttonStyle(OBSecondaryButtonStyle())
                    }
                    logContent.frame(minHeight: 420)
                }
            }
        }
    }

    private var logContent: some View {
        ScrollView {
            Text(model.log)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(OB.green.opacity(0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(Color(hex: 0x090E15), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(OB.border))
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageTitle("Ayarlar", subtitle: "Motorları ve uygulamayı yönet.")
            OBPanel {
                VStack(alignment: .leading, spacing: 16) {
                    OBSectionTitle(title: "Sistem durumu")
                    engineRow("Wine", icon: "shippingbox.fill", ready: model.wine != nil)
                    engineRow("GPTK · DirectX 12", icon: "bolt.fill", ready: model.gptkInstalled)
                    Text("Motorlar otomatik algılanır. Her şey çalışıyorsa değişiklik yapmana gerek yok.")
                        .font(.system(size: 11)).foregroundStyle(OB.muted)
                }
            }
            OBPanel {
                DisclosureGroup(isExpanded: $showSettingsAdvanced) {
                    VStack(alignment: .leading, spacing: 14) {
                        Button("Wine Yolunu Değiştir") { activeModal = .settings }
                            .buttonStyle(OBSecondaryButtonStyle())
                        Text(model.wine?.path ?? "Wine bulunamadı")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(OB.muted)
                            .textSelection(.enabled)
                        if model.canLinkGPTKTest {
                            Button("GPTK Test Ortamını Bağla") { model.linkGPTKTest(); page = .bottles }
                                .buttonStyle(OBSecondaryButtonStyle()).disabled(model.isBusy)
                        }
                        Button("İşlem Günlüğünü Aç") { page = .activity }
                            .buttonStyle(OBSecondaryButtonStyle())
                        Text("D3DMetal, Wine ve oyun uyumluluğu deneysel özelliklerdir.")
                            .font(.system(size: 11)).foregroundStyle(OB.muted)
                    }.padding(.top, 12)
                } label: {
                    Label("Gelişmiş Ayarlar ve Günlükler", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(OB.text)
                }
            }
            OBPanel {
                VStack(alignment: .leading, spacing: 8) {
                    OBSectionTitle(title: "OpenBottle Hakkında")
                    Text("Sürüm \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Geliştirici derlemesi")")
                        .font(.system(size: 12)).foregroundStyle(OB.text)
                    Text("Açık kaynak (MIT). CrossOver / CodeWeavers ile ilişkili değildir. Wine ve D3DMetal ayrıca kurulur.")
                        .font(.system(size: 11)).foregroundStyle(OB.muted)
                }
            }
        }
    }

    // MARK: - Shared building blocks

    private func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 29, weight: .bold)).foregroundStyle(OB.text)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(OB.muted)
        }
    }

    private func emptyCollection(icon: String, title: String, subtitle: String,
                                 button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            OBIcon(name: icon, tint: OB.accent, size: 62)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(OB.text)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(OB.muted)
                .multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(OBPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34).padding(.horizontal, 15)
        .background(OB.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(OB.border))
    }

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.log, forType: .string)
    }
}
#endif
