#if os(macOS)
import SwiftUI
import OpenBottleCore

struct GameDiscoverySheet: View {
    @ObservedObject var model: WorkspaceModel
    let bottle: Bottle
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var query = ""

    private var filtered: [GameCandidate] {
        if query.isEmpty { return model.discoveredGames }
        return model.discoveredGames.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.executableName.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 27)).foregroundStyle(OB.accent)
                VStack(alignment: .leading) {
                    Text("Steam Oyunlarını Bul").font(.title2.bold())
                    Text(bottle.name).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Yeniden Tara") { model.scanGames(in: bottle) }
                    .disabled(model.isScanningGames)
            }
            TextField("Oyun ara", text: $query)
                .textFieldStyle(.roundedBorder)
            if model.isScanningGames {
                HStack { ProgressView(); Text("Steam klasörleri taranıyor…") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.discoveredGames.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "gamecontroller").font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Yeni oyun bulunamadı").font(.headline)
                    Text("Steam klasörlerinde yeni oyun bulunamadı.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { game in
                        Toggle(isOn: Binding(
                            get: { selection.contains(game.id) },
                            set: { yes in
                                if yes { selection.insert(game.id) }
                                else { selection.remove(game.id) }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(game.title).font(.headline)
                                Text("Başlatıcı otomatik seçildi")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }.toggleStyle(.checkbox)
                    }
                }.listStyle(.inset)
            }
            HStack {
                Text("\(model.discoveredGames.count) oyun bulundu · \(selection.count) seçildi")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Kapat") { dismiss() }
                Button("Oyunları Ekle") {
                    model.registerGames(selection, in: bottle)
                    dismiss()
                }.buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty || model.isScanningGames)
            }
        }
        .padding(24)
        .frame(width: 780, height: 550)
        .background(OB.canvas)
        .preferredColorScheme(.dark)
        .tint(OB.accent)
        .onAppear { model.scanGames(in: bottle) }
    }
}
#endif
