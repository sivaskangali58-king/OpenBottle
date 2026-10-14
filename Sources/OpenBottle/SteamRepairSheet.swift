#if os(macOS)
import SwiftUI
import OpenBottleCore

/// An explicit, reversible, user-invoked repair assistant.
/// A black window cannot be reliably detected just by checking the Wine process.
struct SteamRepairSheet: View {
    @ObservedObject var model: WorkspaceModel
    let bottle: Bottle
    @Environment(\.dismiss) private var dismiss

    @State private var inspection: SteamRepairCheck?
    @State private var inspecting = false
    private enum Confirmation {
        case repair, restore, compilerInstall
    }
    @State private var confirmation: Confirmation?
    @State private var working = false
    @State private var feedback: String?

    private var confirmationVisible: Binding<Bool> {
        Binding(get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } })
    }
    private var confirmationTitle: String {
        switch confirmation {
        case .repair: return "Steam siyah ekran düzeltmesi uygulansın mı?"
        case .restore: return "Orijinal dosya geri yüklensin mi?"
        case .compilerInstall: return "Derleyici kurulsun mu?"
        case nil: return "Steam onarımı"
        }
    }
    private var confirmationMessage: String {
        switch confirmation {
        case .repair, .restore:
            return "OpenBottle önce yalnızca bu şişenin Wine işlemlerini durdurur. Steam yardımcı dosyası yedeklenir veya geri alınır."
        case .compilerInstall:
            return "Homebrew üzerinden mingw-w64 kurulacak, ardından yalnızca bu Steam şişesinde onarım uygulanacak. İnternet gerekir."
        case nil: return ""
        }
    }

    private var statusTitle: String {
        switch inspection?.phase {
        case .active: return "Düzeltme zaten etkin"
        case .ready: return "Düzeltme uygulanabilir"
        case .changed: return "Steam güncellemesi düzeltmeyi değiştirmiş"
        case .waiting: return "Steam yardımcı dosyası henüz hazır değil"
        case .unavailable: return "Önce Steam kurulumunu tamamla"
        case .conflict: return "Başka bir düzeltme tespit edildi"
        case .damaged: return "Önceki düzeltme eksik"
        default: return "Durum henüz doğrulanamadı"
        }
    }

    private var statusInfo: String {
        switch inspection?.phase {
        case .active:
            return "Orijinal steamwebhelper.exe güvenli yedekte. Steam'i yeniden başlatıp görüntüyü test edebilirsin."
        case .ready:
            return "Steam'in CEF bileşenini alternatif grafik ayarlarıyla çalıştıran geri alınabilir düzeltme hazır."
        case .changed:
            return "Steam güncellemesinden sonra yardımcı dosya değişmiş. Güncel sürüm yedeklenerek düzeltme yeniden uygulanabilir."
        case .waiting:
            return "Steam ilk açılış/güncelleme adımını bitirdikten sonra tekrar kontrol et."
        case .unavailable:
            return "Bu şişede gerekli Steam.exe ve CEF klasörü bulunamadı. Kurulum tamamlanınca yeniden kontrol et."
        case .conflict:
            return "Orijinal dosya adına sahip bir yedek var fakat OpenBottle kaydı yok. Başka bir düzeltmenin dosyalarını değiştirmeyeceğiz."
        case .damaged:
            return "Düzeltme kaydı var ama dosyalar eksik. Otomatik olarak üzerine yazmak güvenli değil."
        default:
            return "Steam klasörü kontrol edilemedi. İşlem günlüğündeki hatayı incele."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(OB.accent)
                    .frame(width: 48, height: 48)
                    .background(OB.panelLight, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steam Siyah Ekran Yardımcısı")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(OB.text)
                    Text("\(bottle.name)  •  Wine Staging")
                        .font(.system(size: 12)).foregroundStyle(OB.muted)
                }
                Spacer()
                Button("Kapat") { dismiss() }
                    .buttonStyle(OBSecondaryButtonStyle())
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: inspection?.phase == .active ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(inspection?.phase == .active ? OB.green : OB.accent)
                    Text(statusTitle).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OB.text)
                    Spacer()
                    if inspecting { ProgressView().controlSize(.small) }
                }
                Text(statusInfo)
                    .font(.system(size: 12)).foregroundStyle(OB.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if inspection?.hasCompiler == false && inspection?.hasSteam == true {
                    Label("Düzeltmeyi derlemek için mingw-w64 gerekiyor. Homebrew ile kurulum onayı isteyeceğiz.", systemImage: "hammer")
                        .font(.system(size: 12)).foregroundStyle(OB.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OB.panelLight, in: RoundedRectangle(cornerRadius: 13))

            Text("Steam siyah ekranda kalırsa onay vererek düzelt. Steam hâlâ çalışıyorsa OpenBottle ilgili Wine ortamını önce kendisi güvenle kapatır; elle durdurmana gerek yok.")
                .font(.system(size: 12)).foregroundStyle(OB.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let feedback {
                Label(feedback, systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(OB.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            HStack(spacing: 9) {
                Button { refresh() } label: {
                    Label("Yeniden Kontrol Et", systemImage: "arrow.clockwise")
                }
                .buttonStyle(OBSecondaryButtonStyle())
                .disabled(model.isBusy || inspecting || working)

                Spacer()

                if inspection?.canRestore == true {
                    Button("Geri Al") { confirmation = .restore }
                        .buttonStyle(OBSecondaryButtonStyle())
                        .disabled(inspecting || working)
                }
                if inspection?.phase == .active {
                    Button { model.launchSteam(in: bottle) } label: {
                        Label("Steam'i Başlat", systemImage: "play.fill")
                    }.buttonStyle(OBPrimaryButtonStyle())
                        .disabled(model.isBusy || inspecting)
                } else {
                    Button {
                        guard !working, !inspecting else { return }
                        guard inspection?.canApply == true else {
                            feedback = statusInfo + " 'Yeniden Kontrol Et' ile tekrar dene."
                            return
                        }
                        feedback = nil
                        confirmation = inspection?.hasCompiler == true ? .repair : .compilerInstall
                    } label: {
                        Label(working ? "Onarılıyor…" : "Siyah Ekranı Düzelt", systemImage: "wand.and.stars")
                    }.buttonStyle(OBPrimaryButtonStyle())
                        .disabled(inspecting || working)
                }
            }
            Divider().overlay(OB.border)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(OB.muted)
                Text("Onayından sonra yalnızca bu Steam şişesindeki Wine işlemleri kapatılır. Orijinal dosya yedeklenir; geri alma seçeneği korunur. Diğer şişeler ve oyunlar değiştirilmez.")
                    .font(.system(size: 11)).foregroundStyle(OB.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(26)
        .frame(width: 620)
        .background(OB.canvas)
        .preferredColorScheme(.dark)
        .onAppear { refresh() }
        .confirmationDialog(confirmationTitle, isPresented: confirmationVisible,
                            titleVisibility: .visible) {
            switch confirmation {
            case .repair:
                Button("Düzeltmeyi Uygula") { applyFix() }
            case .restore:
                Button("Orijinal Dosyayı Geri Yükle") {
                    working = true
                    model.steamUIFix("restore", in: bottle) { success in
                        working = false
                        feedback = success ? "Orijinal Steam dosyası geri yüklendi." :
                            (model.banner ?? "Geri alma başarısız. İşlem günlüğünü incele.")
                        refresh()
                    }
                }
            case .compilerInstall:
                Button("mingw-w64 Yükle ve Düzelt") {
                    working = true
                    feedback = "Derleyici kuruluyor; bu işlem birkaç dakika sürebilir."
                    model.installRepairCompilerAndFix(in: bottle) { success in
                        working = false
                        feedback = success ? "Düzeltme uygulandı. Steam'i yeniden deneyebilirsin." :
                            (model.banner ?? "Derleyici kurulumu veya onarım başarısız. Günlüğü incele.")
                        refresh()
                    }
                }
            case nil: EmptyView()
            }
            Button("İptal", role: .cancel) {}
        } message: { Text(confirmationMessage) }
    }

    private func applyFix() {
        working = true
        feedback = "Steam kapatılıyor ve onarım hazırlanıyor…"
        model.steamUIFix("install", in: bottle) { success in
            working = false
            feedback = success ? "Düzeltme uygulandı. Steam'i yeniden başlatabilirsin." :
                (model.banner ?? "Düzeltme yapılamadı. Günlüğü incele.")
            refresh()
        }
    }

    private func refresh() {
        inspecting = true
        model.inspectSteamUI(in: bottle) { result in
            inspection = result
            inspecting = false
        }
    }
}
#endif
