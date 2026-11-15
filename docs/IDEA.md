# Siaga Bencana — Brainstorming Hari 1

**Penyusun proyek:** Jiddan Ibnu Ali (`24051214203`)  
**Mata kuliah:** Pemrograman Aplikasi Bergerak, Semester 5  
**Tanggal:** 15 November 2026  
**Status:** Usulan untuk konfirmasi sebelum PRD Hari 2; belum merupakan kontrak implementasi.

Dasar: `AGENTS.md`, `README.md`, dan `docs/README.md`. Sesi ini tidak melakukan riset web. Versi stack mengikuti ketentuan proyek; ketersediaan paket, kompatibilitas wheel Python, dan cakupan feed sumber masih perlu diverifikasi pada tahap persiapan implementasi, tanpa mengganti stack sepihak.

## 1. Analisis Pembeda vs Aplikasi Bencana Biasa

Feed BMKG dan marker peta saja terutama menunjukkan konsumsi API serta rendering Flutter. Nilai akademiknya terbatas apabila tidak ada persistensi relasional, keputusan server yang bisa dijelaskan, perubahan status, maupun pengujian integritas data. Memanggil BMKG langsung dari Flutter juga melanggar arsitektur proyek dan menggandakan permintaan sumber untuk setiap pengguna.

Celah paling realistis adalah menjawab dua pertanyaan: **“Informasi mana yang relevan dengan titik pantau saya, dan mengapa?”** serta **“Bagaimana membedakan laporan warga yang baru masuk dengan yang sudah ditinjau?”** Keduanya dapat dibangun dengan SQL, aturan deterministik, dan alur moderasi sederhana, tanpa AI, sensor, atau layanan berbayar tambahan.

Posisi produk: **aplikasi informasi kejadian dan kondisi warga di sekitar satu titik pantau, dengan prioritas yang transparan dan status verifikasi yang dapat ditelusuri.** Keunikan karya terletak pada rancangan serta integrasi kedua alur tersebut, bukan klaim sebagai aplikasi pertama di pasar.

Usulan cakupan MVP: sinkronisasi **gempa BMKG**, menampilkan keterangan potensi tsunami **hanya jika tersedia pada data resmi**, serta laporan warga berkategori dampak gempa, banjir, atau erupsi. README menyebut cakupan bencana lebih luas; tanpa verifikasi sumber, jangan menganggap BMKG menyediakan feed banjir/erupsi yang setara. Integrasi otomatis sumber tambahan ditunda; penajaman cakupan ini perlu dikonfirmasi sebelum PRD.

## 2. Konsep & 2 Fitur Pembeda Unik Terpilih

### Fitur 1 — Radar Radius dengan Alasan Prioritas

**Mekanisme end-to-end:**

1. Flutter memperoleh lokasi sekali melalui `geolocator`, atau pengguna memilih titik di peta ketika izin ditolak. Pengguna memilih radius usulan `25`, `50`, atau `100 km`; hanya satu titik pantau aktif per akun.
2. Flutter mengirim pengaturan melalui REST API FastAPI. Backend memvalidasi koordinat/radius dan menyimpan `alert_zones` yang berelasi ke `users`.
3. Scheduler FastAPI mengambil data BMKG melalui `httpx`, menormalisasi waktu dan koordinat, lalu melakukan upsert `disaster_events` di PostgreSQL. Permintaan feed pengguna membaca cache database, bukan memicu fetch BMKG.
4. FastAPI menghitung jarak Haversine, kecocokan radius, dan skor prioritas berbasis aturan. Respons ringkas memuat jarak, label prioritas, alasan, sumber, waktu kejadian, serta waktu pembaruan data.
5. Saat ada kejadian baru yang memenuhi radius, backend menyimpan `notification_logs`. Flutter yang aktif menerima SSE dari `StreamingResponse`, lalu menampilkan pembaruan dan notifikasi lokal. Riwayat tetap tersedia melalui REST.

**Pembeda:** kartu informasi menjelaskan alasan seperti “18 km dari titik pantau; dalam radius 50 km; kejadian 20 menit lalu”, bukan hanya label warna. Peta menampilkan lingkaran radius yang sama agar hasil perhitungan mudah diperiksa saat demo.

**Nilai akademik:** cache sumber eksternal, normalisasi data, fungsi geospasial tanpa library GIS berat, pemeringkatan deterministik, deduplikasi notifikasi, dan relasi pengguna–zona–kejadian–notifikasi.

**Tetap ringan dan terbatas:** server menghitung semuanya; Flutter merender hasil. Tidak ada pelacakan GPS terus-menerus, multi-lokasi, prediksi gempa, atau perhitungan wilayah terdampak. Jarak ke episentrum bukan ukuran guncangan di lokasi pengguna. Skor aplikasi adalah prioritas informasi, bukan estimasi ilmiah bahaya atau peringatan resmi; berada di luar radius tidak berarti aman.

### Fitur 2 — Laporan Warga dengan Jejak Verifikasi

**Mekanisme end-to-end:**

1. Dari layar Lapor Warga, pengguna mengisi kategori, deskripsi singkat, titik kejadian, dan maksimal satu foto. Referensi ke kejadian BMKG bersifat opsional agar laporan banjir tidak dipaksa terkait gempa.
2. Flutter mengecilkan foto hingga sisi terpanjang sekitar `1024 px`, kualitas JPEG sekitar `75%`, kemudian mengirim multipart ke FastAPI. Backend tetap memvalidasi ukuran, jenis/isi berkas, koordinat, panjang teks, serta kepemilikan akun; kompresi client bukan kontrol keamanan.
3. FastAPI menyimpan foto ke Supabase Storage dan metadata ke `citizen_reports` di PostgreSQL dengan status `pending`. Laporan belum terverifikasi hanya terlihat oleh pemilik dan admin; feed publik menampilkan laporan `verified`.
4. Admin dalam tab pada layar Lapor Warga yang sama mengambil laporan menjadi `in_review`, lalu memutuskan `verified` atau `rejected` dengan alasan. Setiap transisi ditulis ke `report_verifications`, berisi aktor, status asal/tujuan, catatan, dan waktu.
5. Flutter membaca status dan catatan melalui REST. Laporan terverifikasi muncul di feed/peta radius, dengan label sumber **Warga — ditinjau admin aplikasi**, terpisah dari data BMKG. Verifikasi ini bukan pengesahan oleh otoritas kebencanaan.

**Nilai akademik:** state machine, otorisasi berbasis peran, foreign key opsional, transaksi perubahan status beserta audit, penanganan konflik dua moderator, dan konsistensi metadata–berkas.

**Tetap ringan dan terbatas:** form pendek, satu foto, daftar berpaginasi, dan moderasi manual. Tidak ada voting, reputasi, deteksi hoaks otomatis, komentar, video, atau chat. Laporan final tidak diedit; koreksi dikirim sebagai laporan baru agar jejak keputusan tidak berubah. Notifikasi proaktif MVP hanya untuk kejadian resmi; laporan warga memakai feed/status biasa untuk membatasi kompleksitas.

## 3. Arsitektur 5 Layar Utama (+ Detail)

Tepat **lima layar utama**. Login/setup merupakan satu layar dengan langkah internal; empat layar setelah login menjadi navigasi utama. Tab, form inline, dialog, dan bottom sheet tidak menjadi rute layar utama baru.

| No. | Layar utama | Isi dan pemetaan fitur |
|---|---|---|
| 1 | **Akun & Set Radius** | Form masuk/daftar sederhana dalam satu layar; lokasi sekali atau titik manual; radius 25/50/100 km. Membentuk zona Fitur 1. Pengaturan dapat dibuka kembali dari Profil. |
| 2 | **Beranda & Feed Bencana** | Ringkasan zona, waktu sync, feed gempa, alasan prioritas Fitur 1, filter sekitar/semua, tautan detail. Status kosong tidak diberi label “aman”. |
| 3 | **Peta Interaktif** | `flutter_map` + OpenStreetMap; titik pantau, lingkaran radius, marker kejadian resmi dan laporan terverifikasi dengan legenda berbeda. Tap marker membuka ringkasan/detail. Pemilihan titik dilakukan lewat mode pada layar ini. |
| 4 | **Lapor Warga** | Tab Sekitar/Saya; tombol buat membuka form inline atau bottom sheet. Status dan catatan Fitur 2 dibuka inline. Role admin mendapat tab Tinjau beserta aksi moderasi pada layar yang sama. |
| 5 | **Profil & Riwayat Notifikasi** | Identitas, keluar, pengaturan zona melalui layar 1, daftar notifikasi dan status dibaca. Tap notifikasi menuju detail kejadian. |

**Satu halaman tambahan: Detail Bencana.** Memuat atribut kejadian BMKG, sumber, waktu, jarak, alasan prioritas, keterangan tsunami dari sumber jika tersedia, serta daftar berpaginasi laporan terverifikasi yang ditautkan ke kejadian tersebut. Tidak membuat detail laporan terpisah; gunakan panel pada layar 4 atau ringkasan marker.

Target awal client: `limit=20`, batas server `50` per halaman; urutan stabil dengan ID sebagai pembeda; maksimal `100` marker aktif dengan indikator jika hasil dibatasi. Thumbnail dimuat seperlunya, foto penuh hanya ketika dibuka, dan data feed tidak menyertakan seluruh riwayat verifikasi atau foto berbentuk base64.

## 4. Pilar Kompleksitas Backend & PostgreSQL (Nilai UAS Tinggi, Beban Client Rendah)

### Stack dan batas tanggung jawab

- **`mobile/`:** Flutter `3.47.7` / Dart `3.13.5`, MVVM `Provider`/`ChangeNotifier`, `go_router`, `http`, `geolocator`, `flutter_map`, Material 3, dan `flutter_local_notifications`. Serialisasi JSON manual; tanpa `build_runner`, Firebase SDK, atau UI/animasi berat.
- **`backend/`:** Python `3.15.0`, FastAPI `0.163.0`, Uvicorn `0.54.0`, SQLModel/SQLAlchemy, Pydantic v2, `pydantic-settings`, `psycopg[binary]`, `httpx`, `python-multipart`, `StreamingResponse`, dan `pytest`. Hindari `geopandas`/`shapely`; gunakan Haversine Python/SQL. Pastikan dependency native memiliki wheel yang sesuai sebelum implementasi.
- **Data:** PostgreSQL relasional di Supabase dan Supabase Storage. Seluruh autentikasi/alur bisnis, query, moderasi, serta upload melewati FastAPI. Flutter hanya boleh memuat gambar melalui URL baca yang diberikan backend; tidak menerima kredensial database atau kunci layanan Storage.

### Entitas relasional inti

| Entitas | Relasi, constraint, dan indeks yang direncanakan |
|---|---|
| `users` | PK `id`; email unik; hash password; role terbatas `citizen/admin`. Role ditentukan server, bukan input pendaftaran. |
| `alert_zones` | PK `id`; FK `user_id` unik untuk satu zona per pengguna; koordinat dan radius dengan `CHECK` batas nilai. |
| `disaster_events` | PK `id`; sumber dan kunci sumber unik; waktu UTC, koordinat, magnitudo/kedalaman yang tersedia, keterangan sumber, waktu sync; indeks waktu kejadian dan koordinat kandidat. |
| `citizen_reports` | PK `id`; FK pelapor; FK `event_id` nullable; kategori/status terbatas; koordinat, deskripsi, storage object key/metadata; indeks `(status, created_at)` dan `(user_id, created_at)`. |
| `report_verifications` | PK `id`; FK laporan dan moderator; status asal/tujuan, alasan, waktu; indeks `(report_id, created_at)`; catatan audit tidak bisa diubah melalui API biasa. |
| `notification_logs` | PK `id`; FK pengguna dan kejadian; jenis, waktu dibuat/dibaca; unik `(user_id, event_id, kind)` untuk mencegah notifikasi ganda; indeks `(user_id, created_at, id)` untuk riwayat/replay. |
| `sync_runs` | PK `id`; sumber, waktu mulai/selesai, hasil/jumlah perubahan, ringkasan kegagalan tanpa rahasia; membuktikan kesegaran dan kegagalan sinkronisasi. |

DDL lengkap, kebijakan penghapusan FK, dan kontrak REST dikunci pada Hari 2–3. Hapus akun dan penghapusan audit tidak termasuk MVP.

### Alur server yang dapat diuji dan didemokan

1. **Cache sync BMKG:** interval awal usulan lima menit, dapat diatur lewat `.env`; timeout dan retry terbatas dengan backoff. Upsert memakai identitas sumber yang stabil; bila tidak ada ID, definisikan kunci normalisasi saat kontrak sumber diperiksa. Satu scheduler aktif/lock database mencegah pekerjaan ganda. Kegagalan sumber mempertahankan cache terakhir dan menampilkan waktu sync; tidak menghasilkan kejadian palsu. Pemrosesan ulang kejadian menggunakan constraint notifikasi agar aman dari duplikasi.
2. **Haversine dan radius:** server memvalidasi lintang/bujur, menyaring kandidat memakai bounding box, lalu menghitung jarak lingkaran besar secara tepat dengan konstanta radius bumi yang konsisten. Tangani lintasan bujur ±180°; uji titik sama, batas radius, dan di luar radius. Radius adalah jarak dari titik kejadian, bukan poligon wilayah terdampak. Feed “semua” tetap tersedia saat tidak ada kejadian dalam radius.
3. **Skor prioritas:** usulan awal khusus gempa: `S = 60P + 25M + 15T`, dengan `P = clamp(1 - jarak_km/radius_km, 0, 1)`, `M = clamp(magnitudo/10, 0, 1)`, dan `T = clamp(1 - umur_jam/24, 0, 1)`. Usulan label `<35 biasa`, `35–<65 perhatian`, `≥65 prioritas tinggi`. Ini heuristik demonstrasi yang belum dikalibrasi, bukan model risiko. Eligibility notifikasi ditentukan oleh radius dan kejadian baru, bukan skor. Skor tidak digunakan untuk menafsirkan potensi tsunami, banjir, atau erupsi; keterangan resmi tetap ditampilkan apa adanya. Data wajib skor yang hilang menghasilkan “prioritas belum tersedia”, bukan nol yang menyesatkan. Simpan versi aturan dalam kode dan kembalikan komponen alasan agar pengujian deterministik.
4. **SSE/smart alert:** simpan notifikasi terlebih dahulu; stream hanya baris milik pengguna terautentikasi. Gunakan ID untuk deduplikasi client dan pengambilan ulang riwayat; cursor/replay dirinci dalam kontrak API. Satu koneksi SSE saat aplikasi aktif; bila gagal, polling sekitar 60 detik dengan backoff hingga lima menit dan jeda ketika aplikasi tidak aktif. Saat resume, ambil notifikasi yang terlewat dari database. Perubahan radius tidak membanjiri pengguna dengan notifikasi historis. **MVP tidak menjanjikan pengiriman real-time ketika aplikasi ditutup atau dihentikan Android.** SSE dan notifikasi lokal bukan pengganti layanan push latar belakang.
5. **Verifikasi laporan:** transisi `pending → in_review → verified/rejected`; hanya admin boleh memoderasi, dan admin tidak memverifikasi laporannya sendiri. Perubahan status dan audit dalam satu transaksi; conditional update terhadap status/versi awal mencegah keputusan yang saling menimpa. Server mengembalikan konflik jika laporan sudah diubah moderator lain. Payload pembuatan tidak boleh menentukan pelapor atau status sendiri.
6. **Upload dan konsistensi:** usulan maksimal JPEG `2 MB` sesudah kompresi, nama objek acak, bucket privat, URL baca sementara dari backend. Jangan mempercayai ekstensi/MIME client saja; batasi dimensi dan periksa isi gambar dengan dependency kompatibel. Upload Storage dan transaksi SQL tidak atomik: hapus objek bila pencatatan gagal, serta sediakan pembersihan objek yatim terbatas. Jangan menyajikan metadata sensitif foto atau identitas pelapor dalam feed publik.

### Deploy dan fallback demo

Railway menjalankan FastAPI serta scheduler; Supabase menjalankan PostgreSQL dan Storage. Kredensial hanya di `.env`/secret hosting, dengan `.env.example` tanpa nilai rahasia. Gunakan pooler Supabase jika konektivitas deployment memerlukannya.

Fallback wajib tidak bergantung pada trial Railway: URL API dapat diganti melalui konfigurasi Flutter; backend berjalan lokal dengan konfigurasi yang sama. Untuk menjalankan seluruh komponen aplikasi di localhost, rencanakan PostgreSQL lokal dengan skema identik serta adapter penyimpanan berkas lokal di belakang API yang sama. Mode produksi tetap memakai Supabase Storage. Siapkan seed sintetis bertanda **SIMULASI** dan snapshot sumber untuk demo saat sumber eksternal tidak terjangkau; jangan mencampurnya dengan data live.

Localhost tidak otomatis berarti semua layanan eksternal tersedia offline: tile OpenStreetMap dan fetch BMKG tetap memerlukan jaringan dalam mode live. Saat offline, feed/detail memakai data demo lokal dan layar peta menunjukkan status tile tidak tersedia; peta offline penuh ditolak. Emulator memakai alamat host yang sesuai; HP fisik memakai IP LAN komputer, bukan `localhost` HP. Langkah menjalankan mode lokal dan reset seed menjadi bagian handoff implementasi.

Bukti UAS yang ditargetkan: sync dua kali tanpa duplikasi, perhitungan radius pada titik batas, alasan skor yang konsisten, role warga ditolak saat memoderasi, dua moderator menghasilkan konflik yang benar, riwayat audit utuh, serta notifikasi dapat diambil ulang setelah koneksi putus.

## 5. Batasan Scope Anti-Bablas & Daftar Fitur yang Sengaja Ditolak

**Batas tetap:** satu pengembang, dua role, satu zona aktif per pengguna, dua pembeda, lima layar utama dan satu detail, satu foto per laporan, satu sumber otomatis awal. REST tetap menjadi jalur data utama. Backend mengerjakan logika; Flutter hanya input, state tampilan, dan rendering.

**Ditolak untuk rilis UAS:**

- NoSQL, akses tabel Supabase langsung dari Flutter, Firebase SDK, `dio`, dan codegen `build_runner`.
- Prediksi bencana, AI klasifikasi foto/hoaks, simulasi tsunami, atau klaim estimasi dampak ilmiah.
- Feed otomatis multi-instansi, radar cuaca, sensor/IoT, scraping berita, dan multi-zona keluarga.
- Live chat, komentar, voting, gamifikasi, reputasi pelapor, donasi, serta integrasi dispatch petugas.
- Web admin terpisah, dashboard analitik baru, login sosial, OTP, dan pemulihan akun otomatis pada MVP.
- Video, galeri banyak foto, background GPS, foreground service permanen, jaminan alert saat aplikasi mati, peta offline penuh, serta navigasi/rute evakuasi.
- Redis, broker antrean, microservices, dan PostGIS sebagai syarat MVP; PostgreSQL dan satu layanan FastAPI cukup untuk skala demo.

**Urutan pelaksanaan untuk Antigravity:**

| Periode | Hasil terukur |
|---|---|
| 15–17 Nov | Konfirmasi ide → PRD → arsitektur/ERD/kontrak API; planning dikunci akhir 17 Nov. |
| 18–20 Nov | Slice akun/zona + sync BMKG + feed: database → API → Flutter → test. |
| 21–23 Nov | Slice jarak/skor + peta/detail, termasuk pengujian radius dan payload. |
| 24–26 Nov | Slice laporan/foto + moderasi/audit pada aplikasi yang sama. |
| 27–28 Nov | Slice notifikasi/SSE/fallback polling, integrasi lokal dan smoke test Railway; **feature freeze 28 Nov**. |
| 29 Nov–02 Des | QA, keamanan, perbaikan bug, validasi deploy dan demo localhost; Antigravity menyiapkan rilis `v1.0.0`. |

Jika waktu menipis, sederhanakan visual dan filter tambahan; jangan menghapus REST API, PostgreSQL, audit, atau kedua alur inti. Git/GitHub dan commit bertahap sepenuhnya ditangani Antigravity. Tidak ada penambahan fitur setelah freeze. Mulai 03 Des, fokus video minimal 10 menit dan artikel maksimal 11–12 halaman.

## 6. Empat Keputusan untuk Dikonfirmasi Sebelum `docs/PRD.md`

Pilihan berikut belum dikunci; rekomendasi menjadi bahan keputusan user pada Hari 2.

| No. | Keputusan | Pilihan yang jelas | Rekomendasi |
|---|---|---|---|
| 1 | Cakupan kejadian MVP | **A:** Gempa BMKG + keterangan tsunami resmi bila tersedia; laporan warga dampak gempa/banjir/erupsi. **B:** Gempa dan laporan dampak gempa saja. | **A**, dengan feed otomatis banjir/erupsi tetap di luar MVP. |
| 2 | Dua pembeda dan skor | **A:** Radar Radius dengan skor prioritas transparan + laporan berjejak verifikasi. **B:** Radar Radius memakai label aturan sederhana tanpa angka, dengan alur verifikasi yang sama. | **A**; bobot usulan dikunci saat PRD, tidak disebut skor risiko ilmiah. |
| 3 | Pengaturan zona | **A:** Satu titik GPS/manual, radius preset 25/50/100 km, default 50 km. **B:** Satu titik GPS/manual, radius tetap 50 km. | **A**; multi-zona dan pelacakan kontinu tetap ditolak. |
| 4 | Kanal moderasi MVP | **A:** Tab admin dalam layar Lapor Warga. **B:** Moderasi melalui Swagger FastAPI yang tetap memerlukan autentikasi admin. | **A**, lebih mudah didemokan dalam alur mobile; keduanya tetap memakai transaksi dan audit yang sama. |

Sesudah empat keputusan dijawab, PRD menetapkan acceptance criteria, batas akses role, state UI, dan perilaku gagal/offline. Batas pengiriman alert saat aplikasi tidak aktif serta pemisahan sumber resmi/warga wajib ikut ditulis sebagai perilaku produk.
