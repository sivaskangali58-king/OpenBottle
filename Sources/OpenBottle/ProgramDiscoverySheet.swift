#if os(macOS)
import SwiftUI
import OpenBottleCore

/// Lets the user review potential apps before they become launch shortcuts.
struct ProgramDiscoverySheet: View {
    @ObservedObject var model: WorkspaceModel
    let bottle: Bottle
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPaths: Set<String> = []
    @State private var query = ""

    private var filtered: [ProgramCandidate] {
        guard !query.isEmpty else { return model.discoveredPrograms }
        return model.discoveredPrograms.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.relativeExecutablePath.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 26)).foregroundStyle(OB.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Programları Bul").font(.title2.bold())
                    Text("\(bottle.name) şişesindeki kurulu EXE dosyaları")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.scanPrograms(in: bottle) } label: {
                    Label("Yeniden Tara", systemImage: "arrow.clockwise")
                }.disabled(model.isScanning)
            }
            TextField("Program adı veya dosya yolu ara", text: $query)
                .textFieldStyle(.roundedBorder)
            if model.isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Program klasörleri taranıyor…")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.discoveredPrograms.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Yeni program bulunamadı").font(.headline)
                    Text("Önce EXE/MSI yükleyici çalıştırabilir veya Program Ekle ile dosyayı elle seçebilirsin.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { candidate in
                        Toggle(isOn: Binding(
                            get: { selectedPaths.contains(candidate.id) },
                            set: { active in
                                if active { selectedPaths.insert(candidate.id) }
                                else { selectedPaths.remove(candidate.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.title).font(.headline)
                                Text(candidate.relativeExecutablePath)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2).textSelection(.enabled)
                            }.padding(.vertical, 5)
                        }.toggleStyle(.checkbox)
                    }
                }.listStyle(.inset)
            }
            HStack {
                Text("\(model.discoveredPrograms.count) aday · \(selectedPaths.count) seçildi")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Kapat") { dismiss() }
                Button("Seçilenleri Ekle") {
                    model.addDiscoveredPrograms(selectedPaths, in: bottle)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isScanning || selectedPaths.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 720, height: 535)
        .background(OB.canvas)
        .preferredColorScheme(.dark)
        .tint(OB.accent)
        .onAppear { model.scanPrograms(in: bottle) }
    }
}
#endif
