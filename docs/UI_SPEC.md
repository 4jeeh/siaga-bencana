# UI/UX dan Wireframe Low-Fidelity — Siaga Bencana

**LOCKED: Senin, 16 November 2026.** Implementasi Material 3 Flutter 3.47.7 / Dart 3.13.5, Provider/ChangeNotifier MVVM, go_router, http, geolocator, flutter_map + OSM, flutter_local_notifications. Acuan normatif: [PRD](PRD.md), [kontrak API dan kamus DTO](API_CONTRACT.md), [arsitektur](ARCHITECTURE.md), [skema](ERD.sql), [handoff](HANDOFF.md). Wireframe ASCII dan visual FigCraft ([siaga-bencana-v1.figcraft](wireframes/siaga-bencana-v1.figcraft) & [overview.png](wireframes/png/overview.png)) telah dibuat (`c924d39`); implementasi Flutter menyusul per slice.

## 1. Sistem layar, komponen dan state bersama

Tepat **UI-01..UI-05 lima layar utama + UI-06 Detail Bencana**. Bottom navigation setelah zona tersimpan mempunyai empat tujuan: Beranda, Peta, Lapor, Profil. Form, tab, pemilih foto, dialog keputusan dan panel detail laporan bukan layar/rute utama baru. `go_router` routes:

| ID | Route | Screen / ChangeNotifier |
|---|---|---|
| UI-01 | `/account` (`step=login\|register\|zone` di state internal) | `AccountScreen` / `AuthViewModel`, `ZoneViewModel` |
| UI-02 | `/home` | `HomeScreen` / `EventFeedViewModel` |
| UI-03 | `/map` (`mode=browse\|pick_zone\|pick_report` di state internal) | `MapScreen` / `MapViewModel` |
| UI-04 | `/reports` (tab `nearby\|mine\|review`, form/panel internal) | `ReportsScreen` / `ReportsViewModel`, `ModerationViewModel` |
| UI-05 | `/profile` | `ProfileScreen` / `ProfileViewModel`, `NotificationViewModel` |
| UI-06 | `/events/:eventId` | `EventDetailScreen` / `EventDetailViewModel` |

`SessionCoordinator` memegang token memori, guard, baseline cursor; `NotificationCoordinator` memegang lifecycle kanal. Bukan View yang membuka SSE setiap rebuild. Repository memetakan DTO manual fromJson/toJson; tidak ada bisnis langsung Supabase. Detail laporan menggunakan `ReportPanel` yang dapat dipasang pada UI-03/04/06. Profil memakai ulang langkah zona UI-01 lalu kembali Profil setelah simpan.

Guard: tanpa token→UI-01 login; token valid tanpa zona→UI-01 zone. Mode pick_zone UI-03 diizinkan saat setup tanpa zona, tetapi **tidak** memanggil marker API yang membutuhkan zona. Setelah login `GET /api/v1/me` + `GET /api/v1/me/zone`, baseline notifikasi dahulu, history kemudian; kanal aktif setelah guard selesai dan app resumed. Deep link Detail disimpan sebagai tujuan sementara, dilanjutkan setelah login+zona. UI-06 back kembali asal; empat nav utama tetap konsisten. Citizen tidak melihat Tinjau; backend tetap memeriksa403.

Komponen bersama: `Scaffold`, `SafeArea`, `AppBar`, `NavigationBar`, `ListView.builder`, `Card`, `ListTile`, `FilledButton`, `OutlinedButton`, `TextButton`, `TextFormField`, `SwitchListTile`, `SegmentedButton`, `FilterChip`, `TabBar`, `AlertDialog`, `ModalBottomSheet`, `LinearProgressIndicator`, `CircularProgressIndicator`, `SnackBar`. Tanpa kit/animasi/3D berat. Banner data `SIMULASI — data demo`, ikon lab + teks, menetap; badge per kartu/detail/foto serta prefix notifikasi. Status kesegaran sumber adalah dimensi terpisah: SIMULASI bisa juga STALE. LIVE berarti mode data aktual, bukan jaminan data baru.

Semua request punya state `initialLoading`, `refreshing`, `loadingMore`, `empty`, `error` yang terpisah dari freshness/mode. Data lama tidak dihapus ketika refresh/load-more gagal. Cache hanya memori sesi beserta timestamp; offline bukan sukses tersimpan. Filter/zona berubah membatalkan atau mengabaikan respons lama berdasarkan request generation + meta.zone_version. List20, max50; dedup UUID, load-more sesuai page.next_offset. Signed image lazily loaded, tidak ada base64/full polygon di feed.

Teks konsisten:

- “Prioritas informasi aplikasi, bukan penilaian risiko ilmiah. Di luar radius bukan berarti aman.”
- “Warga — ditinjau admin aplikasi” untuk verified, bukan verifikasi BMKG.
- Empty sekitar: “Belum ada informasi yang cocok dengan radius ini.” Tombol Semua/Ubah Zona; tidak menulis “aman”.
- Sumber gagal: “Data BMKG [Gempa/Cuaca] belum berhasil diperbarui. Terakhir berhasil …”. Tampilkan sumber terpisah, bukan satu lampu global.
- Tile gagal: “Peta dasar tidak tersedia. Daftar dan koordinat tetap dapat digunakan.” Tanpa janji peta offline penuh.
- Kanal: “Pembaruan otomatis saat aplikasi aktif. Tidak dijamin saat aplikasi ditutup.”

### Standar aksesibilitas yang diuji pada setiap layar

Target sentuh minimal **48dp/logical px**, teks sistem **200%**, lebar **360 logical px** tanpa overflow horizontal. Gunakan Wrap/kolom/scroll, bukan tinggi Card tetap. Label teks+ikon untuk sumber/status/prioritas, bukan warna saja. Fokus keyboard/TalkBack berurutan, `Semantics` untuk kontrol/icon-only dan pengumuman error/status singkat; dekorasi tidak dibaca berulang. Kontras teks minimal4.5:1 normal,3:1 besar; focus terlihat. Tombol disabled diberi alasan teks. Format waktu Indonesia dengan zona lokal eksplisit (misalnya WIB), tooltip tanggal lengkap; server UTC tetap sumber hitungan. Tidak menghitung ulang skor/eligibility di mobile.

## 2. UI-01 — Akun & Setup Zona Pantau

**Screen/VM:** `AccountScreen`, `AuthViewModel`, `ZoneViewModel`. Tiga langkah internal, tanpa layar tambahan. Setelah login token hanya memori60menit; restart login lagi. `/account` dari Profil membuka zone dengan tombol kembali.

```text
SafeArea > Scaffold > AppBar: Siaga Bencana
  [Banner SIMULASI jika meta.mode=simulation]
  SingleChildScrollView > Form
    Step login/register:
      SegmentedButton [Masuk] [Daftar]
      TextFormField: Nama tampilan (register saja)
      TextFormField: Email
      TextFormField: Password [Tampilkan/Sembunyikan]
      Inline field error / session-expired message
      FilledButton [Masuk / Daftar] + progress saat submit
    Step zone:
      Text: Satu titik pantau, tidak mengikuti GPS terus-menerus
      OutlinedButton [Gunakan lokasi saya sekali]
      OutlinedButton [Pilih titik di peta / manual]
      Card: Lintang, bujur terpilih + ikon lokasi
      SegmentedButton/Wrap [25 km] [50 km default] [100 km]
      SwitchListTile: Gempa & Potensi Tsunami [aktif]
      SwitchListTile: Cuaca Ekstrem [aktif]
      Text: Toggle hanya memengaruhi notifikasi baru
      FilledButton [Simpan Zona Pantau]
```

| Aksi | Endpoint exact / DTO dan perilaku |
|---|---|
| Banner mode awal | `GET /api/v1/health` → meta.mode/is_simulated; jika tidak tersedia tampilkan API tidak terjangkau, jangan mengarang mode live. |
| Daftar | `POST /api/v1/auth/register` → email/password/display_name; Auth DTO access_token/expires_in/expires_at/user. Role input tidak ada. |
| Masuk / guard | `POST /api/v1/auth/login`, `GET /api/v1/me` → User.has_zone/role; `GET /api/v1/me/zone` → Zone/null. |
| GPS sekali | geolocator setelah tap, timeout10s; hasil lokal belum disimpan. Denied→pilih manual, permanentlyDenied→pengaturan OS opsional. Tidak ada endpoint GPS. |
| Pilih manual | UI-03 pick_zone, hasil latitude/longitude kembali draft ZoneViewModel; tidak PUT sampai user Simpan. |
| Simpan | `PUT /api/v1/me/zone` → latitude/longitude/radius_km/notify_earthquake/notify_weather. Return zone_version/alert_eligible_since/updated_at. Sukses→Beranda (atau kembali Profil); refresh semua response personal. |

Validasi: email format, password10..128 tidak trim, nama1..80; no role; finite lat[-90,90]/lon[-180,180], +180 dikanonisasi server; radius preset. Simpan terkunci sebelum titik valid/saat request. Ulang PUT identik no-op versi; hasil response menentukan zona, bukan optimisme client. Draft register/password tidak dicatat/log/persist.

| State | Tampilan/pemulihan UI-01 |
|---|---|
| loading / load-more | Spinner tombol saat auth/save; skeleton lokasi saat GET; tidak ada pagination. |
| empty | Zone null→langkah setup; koordinat belum dipilih→petunjuk, Simpan disabled. |
| error / offline | Error field422; login401 generik;429 hitung Retry-After;503/jaringan pertahankan input nonsensitif dan Coba Lagi. Cold start offline tidak menyediakan login offline. |
| degraded/stale | Tidak menghalangi akun/zona; health tidak membawa freshness BMKG, banner sumber baru di layar data. |
| SIMULASI | Banner mode pada login/zone; tidak menyebut akun demo sebagai akun produksi. |
| 409 | EMAIL_ALREADY_REGISTERED→arah Masuk tanpa menghapus email; ZONE_REQUIRED dari tujuan→tetap setup. Tidak ada version conflict zona. |
| tile-offline | Ditangani UI-03 picker; hasil input koordinat kembali dapat disimpan. |
| permission-denied | GPS ditolak→manual; izin notifikasi tidak diminta paksa saat login, Profil dapat meminta nanti. |
| token habis | Tutup kanal, bersihkan data privat, tampil “Sesi berakhir, masuk kembali”; hasil draft tidak lintas akun. |

**Checklist a11y UI-01:** [ ] kontrol/password eye48dp; [ ] form scroll pada font200%; [ ] radius Wrap360px; [ ] switch punya nama+nilai TalkBack; [ ] error dibaca dekat field, fokus ke error pertama; [ ] pilihan manual selalu terjangkau tanpa GPS.

## 3. UI-02 — Beranda & Feed Bencana

**Screen/VM:** `HomeScreen` / `EventFeedViewModel`. Default Sekitar, semua kategori, recent. Toggle notifikasi tidak menjadi filter feed.

```text
Scaffold > AppBar: Beranda   [ikon+Ubah Zona]
  Banner: SIMULASI (jika mode demo)
  FreshnessBanner: BMKG Gempa ... | BMKG Cuaca ... (boleh Wrap)
  Card: Titik pantau | Radius 50 km
  SegmentedButton [Sekitar] [Semua]
  Wrap FilterChip [Semua jenis] [Gempa] [Cuaca Ekstrem]
  Jika Gempa: Dropdown [Terbaru / Prioritas]
  Jika Semua: Chip cuaca [Aktif / Semua status]
  Expanded > RefreshIndicator > ListView.builder
    Card Gempa:
      [ikon gempa] BMKG — Gempa [SIMULASI]
      Judul | waktu | jarak
      Prioritas 74.3 — Tinggi / Prioritas belum tersedia
      ExpansionTile [Mengapa?] → reasons terurut
      [Lihat Detail]
    Card CAP:
      [ikon cuaca] BMKG — Cuaca [SIMULASI]
      Area | severity | masa berlaku | lifecycle label
      Metode lokasi / “perkiraan centroid/vertex”
      [Lihat Detail]
    Load-more indicator / [Coba muat lagi]
  NavigationBar [Beranda] [Peta] [Lapor] [Profil + unread badge]
```

| Aksi/komponen | Wiring exact |
|---|---|
| Zona header | `GET /api/v1/me/zone` → radius_km/latitude/longitude/zone_version; edit membuka UI-01. Titik pribadi tidak dibagikan. |
| Feed/refresh/filter/load-more | `GET /api/v1/events?radius_only=true&limit=20&offset=0`; category opsional earthquake/extreme_weather, sort recent/priority hanya gempa, weather_status active/all (all hanya radius_only=false). |
| Card/reasons | EventSummary.source/title/occurred_at/is_simulated/lifecycle_status/cap; priority.priority_display/priority_label/priority_algo/priority_reasons/match_distance_km/within_radius/match_method/evaluated_at. eq-priority-v1 angka; cap-priority-v1 severity tanpa angka. |
| Freshness | meta.sources[].source/state/last_success_at; meta.is_simulated; cached error tidak menyembunyikan freshness. |
| Tap Detail | UI-06 eventId; `GET /api/v1/events/{event_id}` dilakukan DetailViewModel. |
| Badge unread | NotificationViewModel dari `GET /api/v1/me/notifications` unread_count, bukan jumlah SSE terkini. |

Label angka74.3 memakai priority_display server, tidak round ulang. Priority null bukan0. Bahasa alasan memakai Reason.text + label domain; S/P/M/T opsional ExpansionTile. Semua data sumber adalah teks biasa, tidak HTML. CAP inactive menampilkan Kedaluwarsa/Dibatalkan/Digantikan/Data belum lengkap dan tidak dipromosikan sebagai aktif.

| State | Tampilan/pemulihan UI-02 |
|---|---|
| loading / load-more | Skeleton kartu awal; refresh mempertahankan list; next_offset menambah dengan dedup ID. |
| empty | “Belum ada informasi yang cocok …”; [Semua] [Ubah Zona]. Sumber unavailable menjelaskan data belum tersedia, bukan tidak ada kejadian. |
| error / offline | ErrorPanel retry; cache sesi tetap timestamp “Data terakhir dimuat …”; jangan menampilkan cache sebagai LIVE baru. |
| degraded/stale | Banner per sumber tetap terlihat dengan last_success_at; API200 cache tidak jadi full error. |
| SIMULASI | Banner + badge setiap kartu, termasuk hasil Semua; title sumber tidak menghapus badge. |
| 409 | ZONE_REQUIRED→setup UI-01; tidak ada aksi moderasi di layar ini. |
| tile-offline | Tidak ada tile di feed; navigasi Peta tetap tersedia dengan fallbacknya. |
| permission-denied | Feed tidak tergantung izin GPS/OS notification; tampil hanya status izin dari Profil bila relevan. |
| token habis | Guard login dan hentikan kanal; jangan terus retry feed401. |

**Checklist a11y UI-02:** [ ] card action/chip48dp; [ ] teks judul/reasons200% membungkus; [ ] dropdown/filter360px Wrap; [ ] label sumber/tingkat disertai ikon+teks; [ ] status refresh diumumkan tanpa membaca seluruh feed; [ ] urutan fokus sesuai urutan visual.

## 4. UI-03 — Peta Interaktif dan Pilih Titik

**Screen/VM:** `MapScreen` / `MapViewModel`; flutter_map+OpenStreetMap. browse/pick_zone/pick_report pada layar sama. Lingkaran radius hanya zona, bukan poligon bahaya ilmiah. Awal viewport Indonesia, bukan pembatas input bumi.

```text
Scaffold > AppBar: Peta / Pilih titik [Kembali]
  Banner SIMULASI + freshness ringkas saat browse
  Wrap filters: kategori | Sekitar/Semua | Warga verified
  Expanded > Stack
    FlutterMap:
      TileLayer OSM + atribusi “© OpenStreetMap contributors”
      CircleLayer: zona radius25/50/100 km
      MarkerLayer <=100 total [Gempa] [Cuaca] [Warga]
      titik pantau terpisah dari marker kejadian
    bila tile gagal: banner + [Tampilkan daftar hasil]
    bila truncated: “Hasil dibatasi 100. Persempit area/filter.”
    picker: crosshair + [Gunakan titik ini]
  Browse: Draggable/ModalBottomSheet ringkasan marker terpilih
    BMKG → [Detail Bencana]; Warga → ReportPanel inline
  Picker: panel lat/lon input manual, [Konfirmasi titik] [Batal]
  NavigationBar (browse); kembali ke form pemanggil (picker)
```

| Aksi | Wiring exact |
|---|---|
| Browse/update viewport | Debounce300ms; `GET /api/v1/map/markers?bbox=west,south,east,north&radius_only=true&include_reports=true`, category opsional lima nilai. Tidak limit100 di list API, tidak paging marker. Abaikan response viewport lama. |
| Marker/legenda | Marker.id/kind/source/category/title/latitude/longitude/match_method/match_distance_km/priority_label/is_simulated; response truncated/cap=100, meta.zone_version/sources. Jangan download semua polygon. |
| Radius | `GET /api/v1/me/zone` → latitude/longitude/radius_km. Client hanya menggambar circle; backend menentukan match. |
| BMKG tap | Ringkasan lokal Marker kemudian UI-06 menggunakan event id. CAP centroid label “Titik representatif area”, bukan pusat bahaya. |
| Warga tap | `GET /api/v1/reports/{report_id}` → ReportPublic/Private sesuai akses; foto hanya bila dibuka lewat photo-url. Tidak rute baru. |
| Picker | Klik peta/input lat/lon mengubah draft lokal. Hasil kembali ZoneViewModel/ReportsViewModel; tidak PUT/POST otomatis. pick_zone tanpa zona tidak GET markers. |

Viewport antimeridian west>east diteruskan ke backend, bukan dibalik. Marker CAP dipilih radius dari seluruh polygon tetapi bbox dari centroid representatif; panel menjelaskan bila area luas tidak semua tampak. Marker jumlah100 **gabungan** warga/resmi; user memfilter atau kembali feed, tidak mengakumulasi pagination di peta. Jangan membawa JWT API ke host tile OSM.

| State | Tampilan/pemulihan UI-03 |
|---|---|
| loading / load-more | Progress ringkas saat marker fetch; marker lama tetap hanya hingga response baru, replace/dedup set, tidak load-more. |
| empty | “Belum ada marker sesuai area/filter”; circle tetap; [Perluas area] [Feed Semua]. Picker tetap bisa dipakai. |
| error / offline | Marker cache timestamp + retry; submit picker hanya memilih draft, penyimpanan di form menunggu API. |
| degraded/stale | Banner sumber + source labels pada panel; tile sehat tidak berarti BMKG fresh. |
| SIMULASI | Banner peta + badge ringkasan/ReportPanel; tidak menutupi atribusi OSM. |
| 409 | ZONE_REQUIRED saat browse→setup; picker setup tidak memanggil API tersebut. |
| tile-offline | Fallback daftar Marker sama dan input lat/lon. Tanpa mengharuskan internet untuk memilih titik; tidak menyebut offline map penuh. |
| permission-denied | Tombol lokasi saya→manual/input; map browse tidak memerlukan GPS. Izin notifikasi tidak terkait. |
| token habis | Tutup request/kanal lalu login; hapus marker privat/panel akun lama. |

**Checklist a11y UI-03:** [ ] kontrol peta/marker hit area48dp; [ ] alternatif daftar setara untuk TalkBack; [ ] panel200% scroll360px; [ ] legenda ikon+teks; [ ] input lintang/bujur berlabel jelas dan error finite/range; [ ] atribusi tetap terbaca dan bisa diakses.

## 5. UI-04 — Lapor Warga dan Tab Tinjau

**Screen/VM:** `ReportsScreen`, `ReportsViewModel`, `ModerationViewModel`. Tab Sekitar/Saya untuk citizen, tambah Tinjau untuk admin. Form/panel inline atau bottom sheet scroll; bukan halaman detail laporan baru.

```text
Scaffold > AppBar: Lapor Warga   [Tulis Laporan]
  Banner SIMULASI
  TabBar [Sekitar] [Saya] [Tinjau hanya admin]
  Tab Sekitar/Saya > RefreshIndicator > ListView
    ReportCard: ikon warga | kategori | status + teks
      deskripsi | waktu | jarak | badge SIMULASI
      [Lihat] → ReportPanel (foto lazy / catatan bila berhak)
  Form sheet:
    Dropdown lima kategori
    TextFormField deskripsi20..1000 + counter
    [GPS sekali] [Pilih titik manual] + koordinat kejadian
    Optional event: “Terkait event ...” [Lepas]
    [Ambil/pilih satu foto] → preview | ukuran | [Hapus foto]
    Text: Hindari wajah/identitas dan titik rumah yang tak relevan
    [Kirim] / progress upload / [Coba kirim lagi]
  Tab Tinjau:
    Filter [Menunggu] [Sedang ditinjau] [Keduanya]
    Queue oldest first → pilih ReportPanel
    Status | reviewer_id ringkas | version
    [Ambil untuk ditinjau] jika pending dan bukan laporan sendiri
    [Setujui] [Tolak] jika reviewer_id == user.id dan in_review
    Dialog keputusan:
      outcome + TextFormField alasan10..500 + counter
      [Batal] [Simpan keputusan] + progress
    ExpansionTile Jejak peninjauan (owner/admin)
  NavigationBar [Beranda] [Peta] [Lapor] [Profil]
```

Lima kategori wire persis `earthquake,flood,eruption,extreme_weather,haze_other`, label Gempa/Banjir/Erupsi/Cuaca Ekstrem/Kabut Asap-Lainnya. Foto **opsional satu**, kompres sisi<=1024px JPEG~75% sebelum preview upload, cek <=2MiB. Server tetap sanitasi tanpa EXIF; jangan menyebut kompresi client sebagai bukti aman. Total request<=3MiB. Tidak mengirim bila foto yang dipilih gagal diproses; beri Perbaiki/Pilih Ulang, jangan otomatis kirim tanpa foto. Pilihan sumber kamera/galeri memakai fasilitas/plugin Flutter ringan yang dipin Antigravity; tidak menambah layar utama.

| Aksi/tab | Endpoint exact dan field |
|---|---|
| Sekitar | `GET /api/v1/reports?scope=nearby&limit=20&offset=0`, category opsional; hanya verified, DTO ReportPublic kecuali pemilik/admin. |
| Saya | `GET /api/v1/reports?scope=mine&limit=20&offset=0`, status opsional empat nilai; ReportPrivate.version/status/latest_reason/claimed_at/decided_at. |
| Tinjau | `GET /api/v1/reports?scope=review&limit=20&offset=0`, status pending/in_review opsional; admin mendapat reporter_id/reviewer_id/version, tanpa email. |
| Buka laporan | `GET /api/v1/reports/{report_id}` → Public/Private. `GET /api/v1/reports/{report_id}/verifications?limit=20&offset=0` hanya pemilik/admin → Verification.from_status/to_status/reason/resulting_version/created_at. |
| Foto | Jika has_photo dan panel dibuka: `GET /api/v1/reports/{report_id}/photo-url` → url/expires_at/is_simulated. `Image.network(url)` tanpa JWT ke storage; failure refresh URL sekali lalu placeholder. |
| Lokasi | geolocator one-shot10s / UI-03 pick_report; tidak mengganti alert_zones. |
| Event opsional | Form dibuka dari UI-06 membawa event_id; pemilih inline memakai `GET /api/v1/events?radius_only=false&limit=20&offset=0`. Tidak wajib kategori laporan sama event. |
| Submit | `POST /api/v1/reports` multipart category/description/latitude/longitude/client_request_id, event_id/photo opsional. 201 created/200 replay → Private dan tab Saya. payload_hash/payload_hash_algo adalah hasil server, tidak dibuat/dikirim client. |
| Klaim | `POST /api/v1/reports/{report_id}/claim` body expected_version dari Private. 200 ModerationResult→refetch detail/audit/list. Reason claim dibuat server. |
| Putuskan | `POST /api/v1/reports/{report_id}/decision` expected_version/outcome verified atau rejected/reason10..500. 200→refetch ketiga state. Tidak ada optimisme status final. |

Idempotensi: setelah kompresi selesai dan user submit, kunci satu snapshot field+byte foto serta client_request_id UUID selama request/retry. Disable Kirim saat in-flight. Error503/network/response hilang → tombol retry memakai snapshot+key sama; 200 replay boleh menunjukkan status terkini. Mengubah isi menghasilkan UUID baru dengan pemberitahuan “Isi berubah, akan menjadi laporan baru”; jangan auto-submit ulang sebagai laporan baru setelah hasil commit ambigu. Tampilkan saran cek tab Saya dahulu. Draft hanya memori sesi, tanpa offline queue. Jangan mempertahankan draft privat lintas logout/akun.

Moderasi: pending→in_review→verified/rejected, versi1→2→3. Self-review disabled dengan teks “Tidak dapat meninjau laporan sendiri” (server403). In_review milik admin lain menampilkan pemegang klaim, tanpa aksi keputusan. Versi/status final tidak dapat diedit. Modal alasan wajib pada approve **dan** reject; tombol aktif hanya10..500 setelah trim. Catatan pemilik/admin saja, publik hanya verified_at dan label warga. Timeout keputusan→refetch; jangan auto retry. Tidak ada reassignment tersembunyi.

| State | Tampilan/pemulihan UI-04 |
|---|---|
| loading / load-more | Skeleton sesuai tab; submit/klaim/keputusan progress dan disabled; load-more mempertahankan list. |
| empty | Sekitar “Belum ada laporan ditinjau dalam radius”; Saya “Belum ada laporan Anda”; Tinjau “Antrean sesuai filter kosong”. Form tetap tersedia. |
| error / offline |422 dekat field;413 ukuran;415 format;429 tunggu;503 retry aman hanya laporan idempoten. Offline submit/moderasi disabled, draft memori belum tersimpan. Foto gagal placeholder. |
| degraded/stale | Laporan tidak diwariskan sebagai data BMKG stale. Jika picker event resmi terbuka, tampilkan meta.sources dari events; tidak memblokir laporan warga. |
| SIMULASI | Banner, kartu/panel dan overlay preview foto demo; label server is_simulated tetap otoritatif. |
| 409 | IDEMPOTENCY_CONFLICT→jangan retry key itu dengan payload beda; cek Saya. VERSION_CONFLICT/INVALID_TRANSITION→tutup submit dialog, refetch detail/audit, tampil status/version/reviewer terbaru; alasan draft boleh tetap di memori tetapi tidak dikirim ulang otomatis. ZONE_REQUIRED→setup. |
| tile-offline | UI-03 picker memakai daftar/input koordinat; form menerima hasil tanpa tile. |
| permission-denied | Lokasi→manual. Kamera/galeri ditolak→pilih sumber lain atau secara eksplisit Hapus foto opsional; tidak menghapus pilihan diam-diam. OS notification bukan syarat laporan. |
| token habis | Tutup kanal/login; jangan mengunggah otomatis setelah login ulang. Key hanya dapat dipakai pada akun pelapor yang sama. |

**Checklist a11y UI-04:** [ ] tab/action48dp; [ ] deskripsi/modal200% scroll dan keyboard tidak menutup tombol; [ ] form360px tanpa overflow; [ ] status dan self-review memakai teks+ikon; [ ] counter alasan dibaca saat perlu, bukan setiap ketikan; [ ] preview punya label; [ ] konflik diumumkan dan fokus pindah ke status terbaru.

## 6. UI-05 — Profil, Zona & Riwayat Notifikasi

**Screen/VM:** `ProfileScreen`, `ProfileViewModel`, `NotificationViewModel`. Status kanal adalah state lifecycle client, bukan field role/DB. Read_at persisten; last_received hanya cursor sesi.

```text
Scaffold > AppBar: Profil
  Banner SIMULASI
  ListView
    Card akun: display_name | email sendiri | role
    Card zona: titik | radius | dua toggle (read summary)
      [Ubah Zona & Preferensi] → langkah zone UI-01
    Card notifikasi:
      Kanal [SSE aktif / Polling / Menghubungkan / Offline / Dijeda]
      Izin OS [Diizinkan / Belum diminta / Ditolak]
      [Aktifkan notifikasi / Buka pengaturan OS]
      Text: Pembaruan saat aplikasi aktif, tanpa jaminan saat mati
    Riwayat [unread badge + jumlah teks] [Hanya belum dibaca]
      ListTile: ikon+jenis | judul | waktu | Belum dibaca/Dibaca
      [SIMULASI] [Kedaluwarsa/Dibatalkan bila relevan]
      Tap → mark read + UI-06
      Load more / retry
    OutlinedButton [Keluar]
  NavigationBar [Beranda] [Peta] [Lapor] [Profil]
```

| Aksi | Wiring exact |
|---|---|
| Akun/zona | `GET /api/v1/me`, `GET /api/v1/me/zone` → User/Zone; edit UI-01 `PUT /api/v1/me/zone`, return refresh tanpa backlog baru. |
| History/filter/load-more | `GET /api/v1/me/notifications?limit=20&offset=0&unread_only=false` → Notification[]/unread_count/page; sequence DESC, snapshot priority_reasons dan current_lifecycle_status. |
| Tap notif | `POST /api/v1/me/notifications/{notification_id}/read` body `{}` → id/read_at; navigasi UI-06 event_id. Jika mark-read gagal tetap buka Detail, badge belum dihapus permanen; retry idempoten eksplisit/refresh saat berikut. |
| Login baru baseline | `GET /api/v1/me/notifications/sync?baseline=true` → cursor_user_id/high_water_mark/next_sequence; history berikutnya tanpa popup histori. |
| Catch-up | `GET /api/v1/me/notifications/sync?since_sequence=N&cursor_user_id=UUID&limit=20` → items/next_sequence/has_more; advance hanya setelah diproses. |
| Streaming | `GET /api/v1/me/notifications/stream?since_sequence=N&cursor_user_id=UUID` + bearer header; parser connected/heartbeat/alert, id user_uuid:sequence. Reconnect Last-Event-ID menang atas query. |
| Izin OS | flutter_local_notifications request permission hanya setelah tap yang jelas; tidak mengubah notify_earthquake/notify_weather otomatis. |
| Keluar | Lokal: close stream/http subscriptions, stop timers, clear token/private caches/cursor/draft, tutup foto/panel, UI-01. Tidak memanggil endpoint logout yang tidak ada. |

Heartbeat20s timeout45s; satu SSE saat resumed. Dua gagal→poll60/120/240/300s ±10%, sukses reset60, probe SSE5menit, jangan poll dan stream bersamaan. Paused/inactive→tutup kanal/timer, status Dijeda saat relevan; resume catch-up lalu stream replay. Notification UUID dedup; stable local-ID collision handling. Replayed inactive record tampil hanya histori; backlog maksimal satu ringkasan, bukan popup setiap record. SIMULASI prefix pada notifikasi OS. Token expired→login tanpa loop401. Izin ditolak tetap banner/riwayat.

| State | Tampilan/pemulihan UI-05 |
|---|---|
| loading / load-more | Skeleton profile/history terpisah; fetch riwayat gagal tidak menghapus profil yang sudah ada. |
| empty | “Belum ada notifikasi untuk akun ini”; unread_only kosong “Semua notifikasi sudah dibaca”; bukan tanda aman. |
| error / offline | Status Offline + last received time; history cache tetap, mark-read yang gagal tidak ditandai tersimpan.429 Retry-After,503 backoff. |
| degraded/stale | Snapshot log menunjukkan waktu evaluasi; keaktifan current_lifecycle_status/present_as_active_alert, tidak menganggap snapshot lama alert aktif. Detail menunjukkan freshness per sumber. |
| SIMULASI | Banner profil/history, badge setiap log dan prefix popup OS. |
| 409 | Cursor mismatch/out-of-range→tutup kanal, baseline eksplisit+reload history dengan pesan sinkronisasi ulang tanpa popup histori; gap delivery retry sync dari cursor sah dahulu. |
| tile-offline | Tidak ada tile; edit zona menggunakan fallback UI-03. |
| permission-denied | Izin OS Ditolak + Buka Pengaturan, kanal/riwayat tetap aktif. GPS tidak diminta hanya untuk membuka Profil. |
| token habis | Semua timer/kanal berhenti, data akun lama dibersihkan; login ulang baseline baru. |

**Checklist a11y UI-05:** [ ] history/settings/logout48dp; [ ] email/panel200% wrap360px; [ ] unread bukan titik warna saja; [ ] status kanal dan izin dibaca sebagai label+nilai; [ ] perubahan kanal tidak spam TalkBack setiap heartbeat; [ ] text batas layanan terlihat.

## 7. UI-06 — Detail Bencana

**Screen/VM:** `EventDetailScreen` / `EventDetailViewModel`. Satu-satunya detail route tambahan, khusus event resmi; laporan terkait selalu panel inline.

```text
Scaffold > AppBar: [Kembali] Detail Bencana
  Banner SIMULASI / LIVE + freshness STALE/degraded terpisah
  ListView
    Header: ikon sumber | judul | waktu sumber | last_seen_at
    Card prioritas:
      Gempa: angka server / Belum tersedia, label
      Cuaca: severity + lifecycle (tanpa angka gempa)
      ExpansionTile: alasan deterministik terurut
      Text: Prioritas informasi, bukan risiko ilmiah ...
    Gempa fields:
      magnitudo | kedalaman km | wilayah | koordinat
      Potensi (teks sumber) | Dirasakan | Shakemap opsional
    Cuaca fields:
      event | severity | urgency | certainty
      effective - expires | msg_type/status | areaDesc
      headline/description | rujukan update/cancel
    MiniMap jika geometri/lokasi tersedia + attribution OSM
      CAP polygon semua area valid + marker representatif
      fallback teks daftar area/koordinat bila tile gagal
    [Buka sumber resmi] (source_url / web_url tervalidasi)
    [Laporkan kondisi terkait] → form UI-04 event_id
    Laporan warga terkait — verified saja, paginated
      ReportCard [Lihat] → ReportPanel inline
```

| Komponen/aksi | Wiring exact |
|---|---|
| Fetch/refresh | `GET /api/v1/events/{event_id}` → EventDetail + meta.sources/zone_version; abaikan response zona lama. |
| Prioritas | priority.priority_algo/priority_score/priority_display/priority_label/priority_reasons/components/evaluated_at/zone_version. Semua alasan memakai hasil server; notifikasi snapshot berbeda dari detail terkini diberi waktu, bukan ditimpa. |
| Gempa | earthquake.magnitude/depth_km/region/latitude_text/longitude_text/potential/felt/shakemap_url. Null→“Tidak tersedia dari sumber”, bukan0; potensi tsunami tampil persis sumber, tidak disimpulkan dari skor. |
| CAP | cap.severity/urgency/certainty/effective/expires/area_descriptions, weather.cap_event/status/msg_type/headline/description/lifecycle_complete, lifecycle_status, areas[].polygons[].vertices, references[].referenced_event_id. Link reference hanya jika ID tersedia dan dapat dibaca. |
| Peta mini | EventDetail.latitude/longitude atau seluruh polygon geometry_valid=true; no_geometry→areaDesc/“Kecocokan lokasi belum tersedia”, tidak marker palsu. inside_polygon label “Titik pantau berada dalam area”; near_polygon_sample “Dekat area peringatan — perkiraan centroid/vertex” hanya jika within_radius=true; false “Di luar radius menurut sampel centroid/vertex”. |
| Terkait | `GET /api/v1/reports?scope=verified&event_id={event_id}&limit=20&offset=0`; tidak menggunakan nearby (keterkaitan bukan jarak). |
| Panel/foto | `GET /api/v1/reports/{report_id}` + jika has_photo `GET /api/v1/reports/{report_id}/photo-url`. Audit hanya pemilik/admin bila panel memintanya. |
| Lapor terkait | UI-04 form dengan event_id terisi, tetap kategori bebas kelima enum. Tidak submit sebelum user mengisi. |

Detail expired/cancelled/superseded selalu status nonaktif jelas, bukan kartu prioritas aktif. Nowcast valid boundary termasuk; minimum centroid/vertex tidak dijual sebagai irisan radius-poligon sempurna. Shakemap link/gambar hanya URL sumber yang telah divalidasi backend, tanpa bearer dikirim ke BMKG. Bila gambar gagal teks detail tetap tersedia. Buka sumber memakai external handler platform; tampilkan sumber dan tidak memuat HTML feed dalam WebView executable.

| State | Tampilan/pemulihan UI-06 |
|---|---|
| loading / load-more | Skeleton detail; laporan terkait loading sendiri/next_offset; refresh tidak mengosongkan detail. |
| empty | Terkait kosong→“Belum ada laporan warga ditinjau yang terkait”; field sumber null diberi teks, bukan event kosong palsu. |
| error / offline |404 “Informasi tidak tersedia” + Kembali;503/network retry atau cache timestamp; foto/shakemap gagal placeholder. |
| degraded/stale | Banner sumber terkait+last_success_at; last_seen_at bukan disamakan last_success_at. STALE dapat bersama LIVE/SIMULASI; expired status tetap diprioritaskan untuk mencegah alert aktif palsu. |
| SIMULASI | Banner header, badge pada event/laporan/foto, tidak hanya pada judul. |
| 409 | ZONE_REQUIRED→setup; saat kembali refetch detail; tidak ada moderasi di detail event. |
| tile-offline | Area/koordinat dan reasons tetap, miniMap placeholder; tidak menonaktifkan tombol laporan. |
| permission-denied | Detail/miniMap tidak butuh GPS; lokasi laporan diminta nanti di UI-04. Izin OS ditolak tidak menyembunyikan detail. |
| token habis | Hentikan request/kanal, login guard dengan tujuan Detail aman disimpan, privat lama dibuang. |

**Checklist a11y UI-06:** [ ] back/link/expansion48dp; [ ] teks sumber/reasons200%360px tanpa truncation kritis; [ ] polygon punya alternatif daftar area/metode; [ ] lifecycle dan prioritas ikon+teks; [ ] heading Semantics berurutan; [ ] null terucap “tidak tersedia”, bukan kosong tak bermakna.

## 8. Referensi FigCraft dan gate implementasi

Visual wireframe low-fidelity telah dibuat berdasarkan dokumen ini pada `c924d39` di [siaga-bencana-v1.figcraft](wireframes/siaga-bencana-v1.figcraft) beserta ekspor 13 PNG di `docs/wireframes/png/` ([overview.png](wireframes/png/overview.png), `UI-01..06`, dan 6 varian `STATE-*`). Visual ini melengkapi spesifikasi tanpa membuka kembali planning lock atau menambah layar baru; seluruh perilaku/kontrak tetap mengikuti UI-01..06 di atas.

Brief visual: satu page “v1 Lock Planning”, enam frame utama nama UI-01..UI-06, baseline360 logical px, varian tambahan state (bukan layar baru): font200%, error, empty, stale/degraded, SIMULASI, konflik409 UI-04, tile-offline UI-03/06, permission-denied UI-01/05. Wireframe grayscale dengan label ikon sederhana; warna Material3 ditetapkan saat implementasi dengan pemeriksaan kontras. Tandai area scroll/Wrap dan bottom-sheet; anotasi setiap action dengan endpoint di tabel layar. Jangan membuat 6 tujuan bottom-nav, web admin, live chat atau peta offline penuh.

| Gate | Bukti implementasi Antigravity |
|---|---|
| Cakupan | Tepat enam Screen di tabel; form laporan/panel/akun steps tidak menambah layar utama. |
| Data | DTO/API exact, field privat tidak bocor, `is_simulated` konsisten semua mode, alasan skor hanya server. |
| State | Matriks tiap layar di atas menjadi kasus widget/VM; mock success/empty/error/freshness/409/permission/tile. |
| Lifecycle | App paused nol timer/GPS/stream, resume replay dan dedup, token habis login; no push promise. |
| A11y | Checklist setiap layar dijalankan pada360px/font200%/TalkBack,48dp; visual ASCII bukan bukti tes perangkat lulus. |
| AC/NFR | [API §12](API_CONTRACT.md#12-pemetaan-implementasi-dan-gate-uji) memetakan AC-01..24; PRD NFR-01..10 diukur saat build/QA. |

Tidak ada uji widget, screenshot Flutter, benchmark APK atau validasi desain visual FigCraft yang diklaim selesai pada sesi perencanaan.
