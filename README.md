# OpenBottle v0.8.7 — Tek oyun, tek kart

Steam klasörlerindeki farklı `.exe` dosyalarını tek tek göstermek yerine **Oyunları Bul** artık bir kurulu oyun klasörü için tek kart önerir. Örneğin `The Guild - Europa 1410 Demo` için **Europa1410.exe** seçilir; `Europa1410-Win64-Shipping.exe` ayrı kart olarak listelenmez.

Steam, The Guild, Wine Staging, GPTK, GPTK oyun şişeleri ve Steam siyah ekran düzeltmesi olduğu gibi kalır. **Şişeleri silmen veya oyunları tekrar indirmen gerekmez.**

## MacBook'unda derleme

1. Önce OpenBottle'ı kapat, ZIP dosyasını İndirilenler klasörüne çıkar.
2. Terminal'de:

```bash
cd ~/Downloads/OpenBottle-v0.8.7
chmod +x scripts/build-macos.sh
./scripts/build-macos.sh
open dist/OpenBottle.app
```

3. **Şişeler → Steam → Oyunları Bul** bölümünde The Guild tek satır görünmelidir.
4. Kartı seçerek kütüphaneye ekleyebilirsin. Oyun başlatma GPTK üzerinden çalışmaya devam eder.

## Teknik notlar

- Oyun klasörleri `steamapps/common` altında aranır; her klasörden sıralama ile tek önerilen EXE seçilir.
- Başlatıcı seçiminde oyun klasörünün kökündeki `.exe` tercih edilir. Bu her oyun için mükemmel seçim garantisi değildir; bazı oyunlar özel launcher ister.
- Bir oyun zaten kütüphanedeyse ikinci EXE için tekrar önerilmez.
- Daha önce eklediğin iki kısayol varsa otomatik silinmez; kullanıcı kaldırabilir. Oyun dosyalarına dokunulmaz.
- 49 Swift çekirdek testi Linux üzerinde geçti. macOS SwiftUI uygulaması gerçek Mac üzerinde derlenip görsel olarak sınanmalıdır.
- Orijinal kaynak ve üçüncü taraf lisans açıklamaları proje içinde korunmuştur.

## v0.8.9 oyun kapakları

Steam oyunları yerel `steamapps/appmanifest_<appid>.acf` dosyalarından eşleştirilir. Uygulama açıldığında (internet varsa) eksik kapaklar Steam'in genel CDN'inden indirilir ve `~/Library/Application Support/OpenBottle/Artwork/` klasörüne kaydedilir. Mevcut kütüphane kayıtları güncellenir; oyunlar yeniden indirilmez. The Guild: Europa 1410 Demo için Steam manifestinin eksik olması durumunda doğrulanmış AppID (4693080) yedek olarak kullanılır. Oyun kartındaki **… → Kapak görselini yenile** komutu elle yeniden dener. Steam'in resim sunucularına erişilemiyorsa kumanda simgesi gösterilir. Steam logoları ve kapak görselleri hak sahiplerine aittir; OpenBottle kaynak paketine eklenmez.

Arkadaşlara dağıtmak için macOS üzerinde `./scripts/build-macos.sh` komutunu çalıştırın. `dist/OpenBottle-0.8.9.dmg` oluşur. Paket ad-hoc imzalıdır, Apple tarafından notarize edilmemiştir. Kullanıcıların ayrıca Wine Staging, GPTK ve uyumlu diğer araçları kurması gerekebilir. Geniş dağıtım için Developer ID ile imzalama ve Apple notarization önerilir.
