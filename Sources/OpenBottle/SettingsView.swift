#if os(macOS)
import AppKit
import SwiftUI
import OpenBottleCore

struct SettingsView: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(spacing: 12) {
                OBIcon(name: "slider.horizontal.3", tint: OB.accent, size: 49)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wine Ayarları").font(.system(size: 22, weight: .bold)).foregroundStyle(OB.text)
                    Text("Wine motorunu nereden çalıştıracağımızı seç.")
                        .font(.system(size: 12)).foregroundStyle(OB.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(OBSecondaryButtonStyle())
            }
            OBPanel {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Wine yürütülebilir dosyası")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(OB.text)
                    HStack(spacing: 9) {
                        TextField("/Applications/Wine Staging.app/.../bin/wine", text: $path)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Gözat…") { chooseWineExecutable() }
                            .buttonStyle(OBSecondaryButtonStyle())
                        Button("Otomatik Bul") { path = "" }
                            .buttonStyle(OBSecondaryButtonStyle())
                    }
                    if let wine = WineLocator.find(custom: path) {
                        Label("Bulundu: \(wine.path)", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(OB.green)
                            .textSelection(.enabled)
                    } else {
                        Label("Wine bulunamadı. Yolu kontrol et.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(OB.amber)
                    }
                    Text("Yolu boş bırakırsan OpenBottle bilinen Wine uygulamalarını otomatik tarar.")
                        .font(.system(size: 11)).foregroundStyle(OB.muted)
                }
            }
            Text("Motoru değiştirmek mevcut şişeleri silmez. Ancak farklı Wine sürümlerinin aynı prefix'i kullanması uyumluluk sorunlarına yol açabilir.")
                .font(.system(size: 11)).foregroundStyle(OB.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Button("WineHQ sitesi") {
                    if let url = URL(string: "https://www.winehq.org/") { NSWorkspace.shared.open(url) }
                }.buttonStyle(.plain).foregroundStyle(OB.accent)
                Spacer()
                Button("İptal") { dismiss() }.buttonStyle(OBSecondaryButtonStyle())
                Button("Kaydet") { model.updateWinePath(path); dismiss() }
                    .buttonStyle(OBPrimaryButtonStyle())
            }
        }
        .padding(26)
        .frame(width: 735, height: 420)
        .background(OB.canvas)
        .preferredColorScheme(.dark)
        .onAppear { path = model.wineOverride }
    }

    private func chooseWineExecutable() {
        let panel = NSOpenPanel()
        panel.message = "Wine veya wine64 yürütülebilir dosyasını seç"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}
#endif
