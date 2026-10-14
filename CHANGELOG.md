# OpenBottle v0.8.9 — Steam Oyun Kapakları

- Daha önce kütüphaneye eklenmiş oyunların da Steam AppID kimliğini `.acf` manifestlerinden bulur.
- Steam'in yerel kapak önbelleğini kullanır; bulunmazsa Steam'in genel erişime açık görsel adreslerinden indirmeyi dener.
- İndirilen kapakları `~/Library/Application Support/OpenBottle/Artwork/` altında saklar.
- Kütüphane oyun kartları ve ana sayfanın öne çıkan oyununda kapak resimlerini gösterir.
- Oyun kartındaki `… → Kapak görselini yenile` seçeneğiyle tekrar deneme sunar.
- Steam/Wine/GPTK motoru, şişeler ve oyun EXE başlatma akışı değişmedi.
- Gerçek macOS derlemesi için Xcode gereklidir; `.app` ve `.dmg` Mac'teki `scripts/build-macos.sh` ile oluşturulur.

# OpenBottle v0.8.7 — Steam oyun tarama düzeltmesi

- **Oyunları Bul** her kurulu Steam oyun klasörü için yalnızca **bir oyun kartı** gösterir.
- Örneğin `The Guild - Europa 1410 Demo` içindeki `Europa1410.exe` ile `Binaries/Win64/Europa1410-Win64-Shipping.exe` artık iki ayrı oyun olarak görünmez.
- Birden çok çalıştırılabilir dosya bulunduğunda oyun klasörünün kökündeki başlatıcıya öncelik verilir; hiç yoksa mevcut alt klasör EXE dosyalarından en uygun aday seçilir.
- Kütüphanede aynı oyunun başka bir EXE'si zaten kayıtlıysa taramada ikinci defa önerilmez.
- Teknik EXE yolları sade oyun seçme ekranından kaldırıldı; **Oyun ara** ve **oyun sayısı** metinleri güncellendi.
- Steamworks Shared klasörü oyun olarak gösterilmez.
- Dosya silme, Wine motoru değiştirme, oyunları yerinden taşıma veya Steam onarım mekanizmasında değişiklik yok.
- macOS'ta derleme henüz doğrulanmadı. Linux Swift çekirdek testleri: **49 başarılı**.

**Not:** Eski sürümde zaten elle eklenmiş yinelenen oyun kısayolları otomatik silinmez; bu düzeltme yeni tarama listesine yöneliktir.
