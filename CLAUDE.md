# CLAUDE.md — Rak-tracker (GPSTracker)

## Ne bu
iOS 18+ / Swift 6 / SwiftUI, **tamamen çevrimdışı** GPS kayıt uygulaması. Ayrıntılı mimari `README.md`'de.

| Yol | İş |
|---|---|
| `GPSTracker.xcodeproj` | iOS app projesi (iPhone, Swift 6 dil kipi) |
| `GPSTracker/` | App: `Services`, `Persistence`, `UI`, `App`, `Resources` |
| `TrackerKit/` | Yerel Swift paketi — saf mantık: sabit-nokta codec'leri, Douglas-Peucker, GPX/GeoJSON/CSV dışa aktarım, SQL şeması, enerji politikası durum makinesi |

Bağımlılık: GRDB.swift (SPM) + yerel `TrackerKit`. Başka hiçbir şey.

Akış: `RecordingCoordinator` (@MainActor, @Observable) → `LocationService` / `CMMotionActivity` / `EnergyPolicy` → `PersistenceStore` (actor, GRDB, WAL, toplu yazma) → `ExportEngine`.

## Komutlar
```bash
cd TrackerKit && swift test      # saf mantık — Xcode gerektirmez, CLT ile çalışır
```

App hedefi Xcode ister; bu makinede Xcode bozuk. Mantık değişikliğini `TrackerKit` testleriyle doğrula, `xcodebuild`'e uzanma.

## Dikkat
- **Sıfır ağ isteği, analitik yok, hesap yok, senkronizasyon yok.** Bu ürün kararı. Ağ çağrısı, SDK, telemetri, crash reporter ekleme — sorulmadan asla.
- Konum verisi kişiseldir: örnek koordinat/iz çıktısını rapora veya artifact'e koyma.
- Yeni saf mantık `TrackerKit`'e gider (Apple'a özgü API kullanmaz, Linux'ta da test edilebilir); yalnız iOS API'si gereken kod `GPSTracker/`'a.
- Uzak `ResulKarahasanMD/Rak-tracker`, aktif dal `RAK-MD`. İzinsiz commit/push yok.
