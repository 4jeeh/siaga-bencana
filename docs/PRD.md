# PRD — Siaga Bencana

**Author:** Jiddan Ibnu Ali — **NIM:** 24051214203  
**Mata kuliah:** Pemrograman Aplikasi Bergerak, Semester 5  
**Tanggal:** Senin, 16 November 2026 — Hari 2  
**Status:** LOCKED 16 November 2026; [DDL](ERD.sql), [kontrak API](API_CONTRACT.md), [wireframe ASCII/UI](UI_SPEC.md), dan wireframe FigCraft ([siaga-bencana-v1.figcraft](wireframes/siaga-bencana-v1.figcraft)) selesai.

Acuan: [aturan proyek](../AGENTS.md), [README](../README.md), [indeks dokumentasi](README.md), [keputusan Hari 1](IDEA.md), dan handoff Hari 1. Arsitektur pelaksanaan ada di [ARCHITECTURE.md](ARCHITECTURE.md); tugas Hari 3 ada di [HANDOFF.md](HANDOFF.md). Empat keputusan Hari 1 tetap terkunci. Angka yang dahulu berupa usulan dan dirinci di sini menjadi baseline implementasi Hari 2.

Fakta payload TEWS, RSS/CAP Nowcast, dan kompatibilitas binary wheel Python mengikuti hasil verifikasi live **yang diberikan user pada 16 November 2026**. Sesi dokumentasi ini tidak mengklaim melakukan ulang pemeriksaan jaringan atau instalasi paket tersebut. Narasi awal README tentang banjir/erupsi dari BMKG ditafsirkan sesuai IDEA: otomatis hanya TEWS dan Nowcast; banjir/erupsi masuk melalui laporan warga.

## 1. Produk, tujuan, dan ukuran keberhasilan

Siaga Bencana membantu warga membaca informasi resmi BMKG yang relevan dengan satu titik pantau serta melihat laporan kondisi warga yang telah ditinjau admin aplikasi. Dua pembeda MVP adalah **Radar Radius dengan alasan prioritas transparan** dan **laporan warga dengan jejak verifikasi transaksional**.

Skor adalah **prioritas informasi**, bukan model risiko ilmiah, prediksi, estimasi dampak, atau peringatan resmi. Jarak ke episentrum bukan intensitas guncangan; di luar radius tidak berarti aman. Keterangan potensi tsunami ditampilkan sebagaimana sumber, tidak disimpulkan dari skor. Label laporan terverifikasi berarti **ditinjau admin aplikasi**, bukan pengesahan BMKG atau otoritas kebencanaan.

| Tujuan | Ukuran selesai dan bukti UAS |
|---|---|
| Aplikasi lengkap milik sendiri | Alur Flutter → REST FastAPI → PostgreSQL dan Storage berjalan di deployment serta lokal; tidak ada akses tabel Supabase dari Flutter. |
| Kedalaman backend dan SQL | PK/FK/UNIQUE/CHECK/index, upsert sumber, perhitungan radius, transaksi moderasi dan audit dibuktikan dengan pengujian integrasi PostgreSQL. |
| Radar dapat dijelaskan | Fixture skor dan batas radius menghasilkan nilai/alasan konsisten; Nowcast memiliki aturan terpisah; dua kali sync fixture identik tidak menambah event/notifikasi duplikat. |
| Laporan dapat ditelusuri | Pending tidak bocor, admin tidak meninjau laporan sendiri, konflik dua admin menghasilkan satu pemenang dan audit utuh. |
| Demo tetap berjalan | Akun, zona, feed, laporan/foto, moderasi, dan replay notifikasi berfungsi tanpa Railway/Supabase/internet menggunakan PostgreSQL lokal serta seed SIMULASI. |
| Selesai sesuai batas waktu | Planning lock 16 Nov; feature freeze 26 Nov (jeda 23–25 Nov); QA, keamanan, deploy dan rilis 27–29 Nov; mulai 30 Nov video minimal 10 menit dan artikel maksimal 11–12 halaman. |

Keberhasilan tidak diukur dari akurasi prediksi bencana atau pengiriman alert saat aplikasi mati. Semua target performa di bagian 10 merupakan target uji, bukan hasil benchmark yang sudah dicapai.

## 2. Persona dan hak akses

- **Guest/unauthenticated:** calon pengguna yang perlu masuk/daftar; izin GPS mungkin ditolak. Guest adalah keadaan sesi, bukan nilai role database.
- **Citizen:** warga dengan HP Android kelas menengah dan jaringan tidak selalu stabil; ingin memantau rumah atau titik yang dipilih serta mengirim satu foto kondisi.
- **Admin:** moderator proyek yang menggunakan aplikasi Flutter yang sama; perlu mengambil antrean, membaca bukti, dan mencatat alasan keputusan.

| Kemampuan | Guest | Citizen | Admin |
|---|---|---|---|
| Masuk/daftar | Ya; daftar selalu citizen | Sesi aktif | Sesi aktif |
| Feed resmi, detail, peta dan laporan verified | Tidak sebelum login | Ya | Ya |
| Zona dan preferensi | Tidak | Milik sendiri | Milik sendiri |
| Membuat laporan | Tidak | Ya | Ya, tidak boleh memoderasi laporan sendiri |
| Pending/in_review/rejected dan catatan | Tidak | Hanya milik sendiri | Semua untuk moderasi |
| Identitas pelapor | Tidak | Identitas sendiri | ID internal untuk tugas moderasi; email tidak diperlukan dalam antrean |
| Tab Tinjau dan transisi status | Tidak | Tidak | Ya, kecuali laporan sendiri |
| Riwayat, SSE, tanda dibaca | Tidak | Hanya milik sendiri | Hanya milik sendiri |
| Memberi role admin | Tidak | Tidak | Tidak melalui API aplikasi; provisioning operator |
| Mengubah audit atau laporan final | Tidak | Tidak | Tidak |
| Memicu sync/seed | Tidak | Tidak | Bukan aksi UI; pekerjaan operator/worker |

Istilah **feed publik** berarti terlihat oleh seluruh pengguna terautentikasi, bukan endpoint anonim. Backend memeriksa hak akses per objek; menyembunyikan tombol saja tidak cukup. Tanpa token: `401`; role terlarang: `403`; objek privat milik orang lain: `404` agar keberadaannya tidak dibocorkan.

## 3. Scope MVP dan batas tetap

| Termasuk MVP | Batas |
|---|---|
| Akun email/password dan zona | Satu zona per akun; GPS sekali atau pilih manual; radius `25 / 50 / 100 km`, default `50 km`. |
| BMKG Gempa dan Potensi Tsunami | `DataMKG/TEWS`: `autogempa.json`, `gempaterkini.json`, `gempadirasakan.json`; satu event gempa dapat membawa teks potensi tsunami. Tidak membuat prediksi tsunami sendiri. |
| BMKG Cuaca Ekstrem | RSS `https://www.bmkg.go.id/alerts/nowcast/id` → CAP 1.2 XML; waktu berlaku, severity, wilayah/poligon dan keterangan sumber. |
| Preferensi alert | Dua toggle independen: **Gempa & Potensi Tsunami** dan **Cuaca Ekstrem**, keduanya default aktif. Bukan toggle tsunami terpisah. Toggle memengaruhi notifikasi baru, bukan menghapus data feed/riwayat. |
| Radar, feed, peta, detail | Skor hanya gempa; batas 100 marker total; daftar `limit=20`, maksimum 50. |
| Laporan warga | Kategori tepat lima: Gempa, Banjir, Erupsi, Cuaca Ekstrem, Kabut Asap/Lainnya; satu foto opsional; referensi event opsional. |
| Moderasi | Tab Tinjau pada Lapor Warga; `pending → in_review → verified/rejected`; audit SQL. |
| Notifikasi | Hanya kejadian resmi; satu SSE saat aplikasi aktif, polling fallback, riwayat persisten dan notifikasi lokal bila izin tersedia. |
| Fallback demo | API, PostgreSQL dan adapter file lokal; seed/snapshot terpisah dengan label SIMULASI. |

Di luar scope: NoSQL; Firebase SDK; akses bisnis langsung Supabase; `dio`; `build_runner`; web admin; chat/komentar/voting; AI/hoaks/reputasi; OTP/login sosial/reset password otomatis; hapus akun; multi-zona; GPS latar belakang; push saat app mati; video/multi-foto; dispatch/rute evakuasi; peta offline penuh; feed erupsi/PM2.5 otomatis; Redis/broker/microservices/PostGIS sebagai syarat. **Maritim ditangguhkan ke pasca-UAS v1.0.0**, bukan acceptance gate MVP dan tidak boleh menunda freeze.

## 4. Navigasi dan spesifikasi lima layar

Tepat lima layar utama dan satu halaman Detail Bencana. Tab, langkah internal, form inline, dialog dan bottom sheet bukan layar utama tambahan. Empat tujuan navigasi setelah setup adalah Beranda, Peta, Lapor Warga, Profil. Pemilihan titik memanfaatkan mode pilih pada Peta dan kembali ke pemanggil.

| ID | Layar, user story, dan isi wajib | Acceptance criteria |
|---|---|---|
| UI-01 | **Akun & Set Radius.** Sebagai warga, saya dapat daftar/masuk lalu menetapkan titik pantau tanpa wajib memberi izin GPS. Langkah akun → GPS/manual → radius/toggle → simpan; Profil membuka kembali langkah zona yang sama. | Pendaftaran tidak menerima role. GPS ditolak/tidak tersedia/timeout memberi tombol pilih manual. Simpan zona berhasil sebelum navigasi awal ke Beranda; kegagalan mempertahankan input. Akun tanpa zona diarahkan ke setup. |
| UI-02 | **Beranda & Feed Bencana.** Saya melihat sumber, waktu, jarak, alasan prioritas dan kesegaran data. Filter Sekitar/Semua dan Gempa/Cuaca; default Sekitar dan semua jenis. | Sekitar mengikuti zona server. Semua menampilkan data nasional tersimpan tanpa batas radius, tetap berpaginasi. Toggle alert tidak menyembunyikan jenis feed. Daftar gempa default terbaru dahulu; pilihan urut prioritas hanya pada filter Gempa. Nowcast aktif didahulukan. Tidak mencampur skor gempa dengan severity sebagai satu angka. |
| UI-03 | **Peta Interaktif.** Saya melihat titik pantau, lingkaran radius, marker BMKG dan warga verified dengan ikon/legenda berbeda. | Maksimum 100 marker gabungan dari hasil filter server; ada indikator hasil dibatasi dan arahkan ke feed/filter. Marker warga membuka panel, BMKG menuju Detail. Tidak mengambil seluruh polygon/foto penuh dalam payload marker. Tile gagal tidak membuat aplikasi crash dan masih menyediakan daftar hasil. |
| UI-04 | **Lapor Warga.** Saya melihat tab Sekitar/Saya, membuat laporan inline, lalu membaca status/catatan. Admin memperoleh tab Tinjau. | Sekitar hanya verified dalam radius; Saya memuat semua status milik sendiri. Lima kategori tersedia. Form mempunyai deskripsi, titik kejadian, satu foto opsional, event opsional. Tombol kirim terkunci saat in-flight. Admin mengambil dan memutuskan dari panel yang sama. |
| UI-05 | **Profil & Riwayat Notifikasi.** Saya mengubah zona/preferensi, melihat kanal aktif, izin notifikasi dan riwayat serta keluar. | Notifikasi milik sendiri; tap menuju Detail dan menandai dibaca secara idempoten. Tersedia status SSE/polling/offline. Keluar menutup SSE/timer dan menghapus data privat/token/cache sesi. |
| UI-06 | **Detail Bencana**, satu halaman tambahan. Saya memeriksa atribut sumber dan kaitan laporan warga. | Gempa menampilkan waktu, koordinat, magnitudo/kedalaman bila ada, Potensi/Dirasakan/Shakemap bila ada. Cuaca menampilkan event, areaDesc, severity/urgency/certainty, effective/expires, headline/description serta tautan sumber. Ada waktu sync, alasan kecocokan, label kedaluwarsa dan laporan verified terkait berpaginasi. Tidak ada halaman detail laporan tersendiri. |

Teks tetap pada penjelasan Radar/Detail: **“Prioritas informasi aplikasi, bukan penilaian risiko ilmiah. Di luar radius bukan berarti aman.”** Laporan verified berlabel **“Warga — ditinjau admin aplikasi”**. Tidak ada klaim “aman” pada empty state.

## 5. Kebutuhan fungsional dan aturan bisnis

### FR-01 — Akun, sesi dan zona

User story: sebagai citizen, saya ingin pengaturan rumah tersimpan per akun, meskipun lokasi perangkat berubah.

- Email dinormalisasi trim dan huruf kecil, unik; password 10–128 karakter, tidak dipotong/di-trim dan tidak dicatat ke log. Pesan login gagal generik. Admin diprovisi operator, bukan field request pendaftaran.
- Autentikasi FastAPI memakai Argon2 melalui `pwdlib[argon2]` dan bearer JWT bertanda tangan melalui `pyjwt`. Masa berlaku access token dapat dikonfigurasi **`3600–604800` detik** (default `604800` detik / 7 hari), tanpa refresh flow MVP; expiry mengharuskan masuk kembali. Di mobile Flutter, token akses terenkripsi (tanpa menyimpan kata sandi) disimpan melalui `flutter_secure_storage` saat opsi **Tetap masuk** aktif (default aktif), dan dihapus saat logout atau `401`. Zona, pencarian wilayah Indonesia (`/locations/search`), cuaca ringan zona (`/me/weather`), dan riwayat tetap melewati backend FastAPI.
- Validasi lintang `[-90,90]`, bujur `[-180,180]`, angka finite; kanonisasi `180` menjadi `-180`. Radius selain preset ditolak `422`. Satu baris zona unik per `user_id`.
- Panggilan GPS hanya setelah aksi pengguna atau konfirmasi dialog onboarding izin opsional; timeout 10 detik. Titik pantau juga dapat dipilih via pencarian wilayah Indonesia (provinsi/kota/kecamatan) atau tap peta; titik tidak otomatis mengikuti pergerakan. Titik laporan adalah input terpisah, tidak otomatis mengganti titik pantau.
- Setiap perubahan nyata zona/toggle menaikkan `zone_version` (PUT dengan nilai kanonik identik adalah no-op) dan menyetel `alert_eligible_since` dengan waktu UTC server. Tidak membangkitkan notifikasi dari event yang sudah ada. Feed dan jarak direfresh; respons perhitungan memuat versi zona agar respons lama tidak menimpa zona baru.

### FR-02 — Ingest dan kesegaran BMKG

User story: sebagai warga, saya tetap membaca cache terakhir ketika sumber BMKG gagal, dengan informasi umur data yang jujur.

1. Scheduler mencoba TEWS dan Nowcast setiap **300 detik**, konfigurabel. HTTP timeout total 15 detik per request, maksimum dua retry dengan backoff 2 dan 4 detik; deadline satu pekerjaan sumber 240 detik. Satu worker aktif dengan lock PostgreSQL; pekerjaan tidak overlap. Feed user tidak pernah memicu fetch BMKG.
2. TEWS memakai `DateTime` ISO UTC sebagai waktu utama dan `Coordinates` dalam urutan `lat,lon`. `Lintang`/`Bujur` disimpan untuk tampilan/validasi; `Magnitude` dan `Kedalaman` diparse dari teks. `Potensi` tersedia pada auto/terkini, `Dirasakan` pada auto/dirasakan, `Shakemap` pada auto; field opsional yang tidak ada tetap null.
3. Karena tidak ada ID numerik sumber, `source_key = SHA256("TEWS|" + waktu_UTC_kanonik + "|" + lat_6_desimal + "|" + lon_6_desimal)`. Waktu ekuivalen zona waktu dibuat sama, nol negatif dikanonisasi dan pembulatan desimal ditetapkan sama di semua parser. **Nama file endpoint tidak masuk key.** Unique `(source, source_key)` membuat tiga endpoint bergabung.
4. Nilai tidak kosong memperkaya record; field kosong tidak menghapus field valid. Konflik dalam satu siklus: auto didahulukan, kemudian terkini, lalu dirasakan; provenance/waktu pengamatan disimpan. Payload identik hanya memperbarui waktu dilihat, bukan versi isi. Jika BMKG mengoreksi waktu/koordinat sehingga key berubah, MVP bisa menghasilkan event baru; jangan memakai fuzzy merge berisiko. Keterbatasan ini dicatat untuk demo dan audit sumber.
5. RSS berisi item `title`, `link`, `description`, `guid` OID unik dan `pubDate`. Ambil CAP dari link valid `*_alert.xml`; baca namespace `urn:oasis:names:tc:emergency:cap:1.2`, `identifier`, `sent`, `status`, `msgType`, dan info (`event`, `urgency`, `severity`, `certainty`, `eventCode`, `effective`, `expires`, `headline`, `description`, `web`, areaDesc dan beberapa polygon). Identity CAP adalah identifier; guid RSS disimpan sebagai provenance/deduplikasi unduhan, bukan pengganti waktu berlaku.
6. CAP info Bahasa Indonesia dipilih bila ada; fallback blok pertama dengan bahasa dicatat. Semua area/polygon dari blok pilihan dipertahankan. Parser menerima pola tertutup valid dengan minimal tiga vertex unik; batas di bagian keamanan. CAP invalid disisihkan dengan alasan dalam sync_runs, tidak menghapus cache valid.
7. Hanya `status=Actual` dan pesan aktif tervalidasi yang layak alert live. `Alert`/`Update` dapat menjadi informasi aktif; `Cancel` menonaktifkan pesan rujukan bila references tersedia. Rujukan `Update` juga menandai versi lama superseded. Jangan menebak relasi berdasarkan judul; references hilang/tidak dikenali menghasilkan flag lifecycle tidak lengkap dan tidak menerbitkan alert baru untuk Update/Cancel tersebut. Status Test/Exercise tidak masuk feed live. Pesan tanpa effective memakai sent; tanpa expires atau waktu interval invalid tidak boleh mengirim alert otomatis.
8. Keaktifan memakai UTC server: `effective <= now < expires`, belum dibatalkan/superseded. Tepat expires sudah kedaluwarsa meskipun sync berikut belum berjalan. Detail/histori boleh membaca data lama; marker sekitar cuaca default hanya yang aktif. Payload CAP identifier sama dengan isi berubah memperbarui versi isi, tidak membuat identity baru.
9. `sync_runs` per sumber mencatat status success/partial/failed, waktu sukses terakhir, jumlah valid/invalid/perubahan dan error tersanitasi. Partial/gagal menampilkan degraded segera; sukses terakhir lebih dari **15 menit** menampilkan stale. TEWS sehat dan Nowcast gagal ditampilkan terpisah. Tanpa cache, tampilkan tidak tersedia; tidak membuat data pengganti otomatis.

### FR-03 — Radius, skor gempa dan prioritas Nowcast

User story: sebagai warga, saya dapat memahami mengapa sebuah informasi cocok dengan titik pantau saya.

**Jarak gempa dan warga.** Semua hitungan di backend, dengan Haversine double precision, radius bumi `R=6371.0088 km`, sudut radian, selisih bujur terpendek pada `[-π,π]`, dan intermediate `a` di-clamp `[0,1]` sebelum akar/asin. Bounding box hanya filter kandidat: pecah interval jika melintasi antimeridian; dekat kutub gunakan semua bujur. Keputusan akhir `distance_km <= radius_km + 0.000001` (toleransi numerik 1 mm). Pembulatan tampilan satu desimal tidak menentukan eligibility.

**Rumus terkunci `eq-priority-v1`:**

```text
clamp(x, a, b) = min(max(x, a), b)
age_hours = max(0, (evaluated_at_utc - occurred_at_utc) / 3600 detik)
P = clamp(1 - distance_km / radius_km, 0, 1)
M = clamp(magnitude / 10, 0, 1)
T = clamp(1 - age_hours / 24, 0, 1)
S = 60P + 25M + 15T
S < 35        : biasa
35 <= S < 65  : perhatian
S >= 65       : prioritas tinggi
```

Label memakai nilai sebelum pembulatan; `priority_display` tampilan satu desimal dengan pembulatan desimal **half-up**, bukan default bankers rounding. Contoh terkunci: `d=10 km`, `r=50 km`, `m=5`, umur `2 jam` → `P=0.8`, `M=0.5`, `T=22/24`, **S=74.25**, tampilan **74.3**, label **prioritas tinggi**. Alasan urut tetap: jarak dan radius → magnitudo → umur → label aplikasi; bila input hilang, alasan missing_data disisipkan sebelum label aplikasi. Sertakan `priority_algo`, `evaluated_at`, komponen mentah dan `zone_version` sehingga test memakai jam beku. Semua hitungan satu respons memakai evaluated_at yang sama.

Jika koordinat/waktu/magnitudo wajib hilang/invalid, skor null dan label **“Prioritas belum tersedia”**, bukan nol. Waktu di masa depan lebih dari 5 menit ditandai invalid untuk skor/alert; toleransi sampai 5 menit memakai umur nol. Kedalaman/Dirasakan/Potensi tidak mengubah skor. Di luar radius, skor masih dapat dijelaskan pada Detail tetapi tidak mengubah eligibility. Feed campuran diurutkan waktu terbaru lalu ID; urut skor hanya gempa dengan null terakhir, lalu waktu dan ID.

**Aturan Nowcast `cap-priority-v1`, tanpa angka gempa:**

1. Parse semua polygon area pilihan, simpan bbox dan centroid sebagai koordinat representatif event. Untuk area majemuk, marker memakai centroid polygon pertama yang valid; **bukan** pusat bahaya. Pencocokan selalu terhadap semua polygon, bukan marker saja.
2. Unwrap bujur setiap ring melewati antimeridian sebelum menghitung centroid/bbox atau ray casting; sesuaikan bujur titik pantau ke cabang yang sama. Titik pada tepi/vertex dihitung di dalam dengan toleransi numerik `1e-9` derajat. Satu polygon yang memuat titik cukup untuk `match_method=inside_polygon`, jarak kecocokan nol.
3. Jika tidak di dalam, gunakan minimum Haversine ke seluruh centroid dan vertex valid. Jika minimum <= radius dengan toleransi di atas, `match_method=near_polygon_sample`, label **“Dekat area peringatan — perkiraan centroid/vertex”**. Ini pendekatan ringan, **bukan** jarak minimum eksak ke tepi atau uji irisan lingkaran-poligon. Bisa melewatkan irisan pada tengah sisi panjang; dokumen/UI tidak mengklaim cakupan radius poligon sempurna. Bounding box kandidat harus konservatif agar tidak membuang titik di dalam poligon.
4. Tanpa geometri valid, tampilkan areaDesc di feed Semua/Detail dengan **“Kecocokan lokasi belum tersedia”**; jangan mengklaim masuk radius, memasang marker fiktif, atau mengirim alert lokasi. Nama provinsi saja bukan bukti titik pengguna berada di area peringatan.
5. Untuk pesan aktif dan cocok, severity `Extreme/Severe` → **prioritas tinggi**, `Moderate` → **perhatian**, `Minor` → **informasi**, `Unknown`/nilai lain → **prioritas belum tersedia**. Urgency/certainty tetap ditampilkan apa adanya; jangan menyimpulkan probabilitas numerik. Severity tidak menjadi syarat alert: pesan aktif Actual yang cocok tetap eligible walau severity Unknown, dengan keterangan tersebut. Expired/cancelled/superseded selalu diberi label status, bukan prioritas aktif.
6. Alasan deterministik berisi areaDesc, metode kecocokan, jarak sampel bila relevan, severity, urgency/certainty, dan rentang berlaku. Potensi tsunami tetap teks TEWS dan tidak dipetakan ke aturan CAP ini.

### FR-04 — Feed, peta dan detail

- List memakai `limit=20`, `1..50`, `offset>=0`, urutan sekunder ID yang stabil; invalid ditolak `422`. Offset pagination tidak menjamin snapshot saat data berubah: refresh kembali halaman pertama dan deduplikasi ID client. Feed default gempa 7 hari terakhir, cuaca aktif; Semua dapat melihat cuaca kedaluwarsa lewat filter status, tetap berpaginasi. Event lama tetap tersedia dari Detail/riwayat.
- Endpoint marker terpisah dari list, batas **100 total** BMKG+warga, berisi data ringkas dan `truncated`; tidak memakai `limit=100` pada endpoint list. Filter radius dan status diterapkan sebelum batas. Pilihan 100 terdekat memakai jarak kecocokan, kemudian waktu terbaru dan ID; respons menyertakan legenda jenis. Tidak ada pengambilan halaman berikut otomatis yang menambah marker di atas 100.
- Laporan verified disaring radius titik laporan. Info warga tidak diberi skor gempa. Detail resmi hanya menampilkan laporan verified yang memiliki event_id terkait, bukan semua laporan sekitar.
- Thumbnail lazily loaded; foto penuh hanya saat dibuka. List tidak mengandung base64, seluruh polygon, audit penuh, email pelapor atau signed URL yang dicatat ke log.

### FR-05 — Pembuatan dan upload laporan

User story: sebagai citizen, saya ingin mengirim bukti kondisi tanpa membocorkan metadata foto dan tetap dapat mencoba ulang jika koneksi terputus.

- Field wajib: kategori enum, deskripsi setelah trim **20–1000 karakter**, lat/lon valid. Waktu laporan dibuat server. event_id opsional harus menunjuk event yang ada; kategori tidak dipaksa sama dengan event. Satu foto **opsional**, JPEG saja, maksimum **2 MiB = 2,097,152 byte** setelah kompresi; seluruh request maksimal 3 MiB. Jika pengguna memilih foto lalu upload gagal, jangan diam-diam mengirim laporan tanpa foto.
- Client mengecilkan sisi terpanjang maksimum 1024 px, kualitas JPEG sekitar 75%, serta menghapus metadata. Server tetap memeriksa byte aktual, signature/decode, MIME, dimensi sisi maksimum 4096 px dan maksimum 16 megapixel sebelum re-encode dengan Pillow. Hasil simpan maksimum 1024 px, JPEG sekitar 75%, metadata EXIF/GPS dihapus; decompression bomb/invalid ditolak.
- Server menentukan reporter_id/status pending; field role, status, reviewer atau reporter kiriman client ditolak. Bucket privat, nama objek acak, tidak memakai nama berkas asli sebagai path. Feed tidak memuat EXIF, identitas kontak atau koordinat GPS tersembunyi foto. Koordinat kejadian yang dipilih memang tampil untuk laporan verified; form memberi keterangan jangan memilih rumah pribadi jika tidak relevan.
- Backend memvalidasi sebelum upload, upload berkas tersanitasi, lalu commit laporan. Storage/SQL tidak atomik: bila SQL gagal, lakukan compensating delete; jika delete gagal, catat cleanup untuk objek yatim. Jangan mengembalikan sukses sebelum SQL commit. Timeout yang status commit-nya belum jelas harus diperiksa lewat kunci idempoten sebelum menghapus objek.
- Setiap submit mempunyai `client_request_id` UUID unik per pengguna, dipertahankan pada retry payload yang sama. Unique `(reporter_id, client_request_id)` dan hash payload/foto tersanitasi mengembalikan laporan yang sama setelah respons hilang; reuse key untuk payload berbeda → `409`. Perubahan isi form menghasilkan key baru. Duplikat upload bersamaan dibersihkan tanpa menghapus objek pemenang.
- Draft hanya di memori selama layar/sesi hidup; retry eksplisit, tidak ada background offline queue. Foto gagal/batas terlampaui tidak meninggalkan laporan pending separuh jadi. Setelah sukses, tampilkan status pending dan masuk tab Saya. Laporan yang telah dikirim tidak diedit; koreksi berupa laporan baru.

### FR-06 — Moderasi dan jejak verifikasi

User story: sebagai admin, saya ingin mengambil laporan dan memberi keputusan yang tidak tertimpa moderator lain.

| Status asal | Aksi dan syarat | Status tujuan | Audit |
|---|---|---|---|
| Belum ada | Citizen/admin mengirim laporan valid | pending | Reporter dan created_at pada laporan; belum ada keputusan moderator. |
| pending | Admin bukan pelapor, expected_version cocok; klaim | in_review | Aktor, pending → in_review, catatan klaim, waktu UTC, versi baru. |
| in_review | Admin pemegang klaim, bukan pelapor, expected_version cocok; alasan 10–500 karakter | verified atau rejected | Aktor, asal/tujuan, alasan, waktu UTC, versi baru. |
| verified/rejected | Tidak ada aksi perubahan status MVP | Tetap final | Audit tidak dapat diubah/dihapus melalui API. |

Update status, reviewer_id, version dan insert `report_verifications` harus satu transaksi SQL. Dua klaim dari versi sama: tepat satu berhasil, lainnya `409 CONFLICT`; tidak ada audit untuk aksi gagal. Langsung pending → verified, memakai versi lama, keputusan berulang, atau transisi final → lainnya ditolak `409`. Citizen/self-review/non-owner klaim ditolak `403`. UI refetch setelah konflik dan menampilkan keputusan aktual, tidak melakukan retry keputusan secara diam-diam.

Klaim tidak mempunyai auto-timeout/reassignment pada MVP; admin yang sama dapat melanjutkan setelah login ulang. Untuk demo siapkan minimal dua admin selain akun pelapor; hindari klaim memakai akun yang akan dihapus. Pemulihan klaim macet di luar MVP, tidak boleh dilakukan lewat edit audit/UI tersembunyi. Catatan keputusan boleh dibaca pemilik dan admin; publik hanya menerima status verified, waktu verifikasi dan label sumber.

### FR-07 — Eligibility notifikasi, SSE dan polling

User story: sebagai warga, saya menerima informasi baru untuk zona saya saat aplikasi aktif dan dapat membuka riwayat setelah koneksi kembali.

**Penerbitan server:**

- Notifikasi hanya sumber resmi, `kind=official_new`; unik `(user_id, event_id, kind)`. Laporan warga, kenaikan skor akibat refresh, perubahan radius atau pengayaan field event tidak menerbitkan alert baru. Satu event TEWS dengan Potensi tetap satu notifikasi.
- Syarat: akun memiliki zona; jenis diaktifkan; event baru pertama kali teramati sesudah `alert_eligible_since`; event cocok lokasi; waktu sumber tidak sebelum `alert_eligible_since`. Gempa harus berumur <=24 jam dan tidak invalid masa depan. CAP harus Actual, lifecycle valid dan aktif pada waktu evaluasi; gunakan sent sebagai waktu sumber. **Skor/ambang severity bukan syarat eligibility.**
- Bootstrap sumber pertama pada database memasukkan cache tanpa alert historis. Setelah bootstrap, event baru diproses menurut syarat di atas; akun/zona baru tidak menerima backlog lama. Identifier CAP Update yang baru dan valid dapat mendapat satu alert baru jika seluruh syarat terpenuhi; identifier sama tidak mengulang. Cancel mengubah status sumber/detail tanpa notifikasi proaktif tambahan MVP.
- Worker menyimpan event, evaluasi eligibility dengan zona terbaru, notification_logs dan checkpoint batch dalam transaksi database sebelum data tersedia di stream. Jika zona berubah bersamaan, lock/version check membuat keputusan memakai zona yang berlaku saat commit. Job retry mengandalkan unique constraint. Kegagalan batch tidak boleh menyimpan event baru sambil kehilangan notifikasi yang seharusnya dibuat; sumber lain tetap dapat maju independen.

**Pengiriman mobile:**

- Satu SSE terautentikasi melalui header bearer saat lifecycle `resumed`, dengan heartbeat **20 detik**. Client tidak melihat heartbeat/data selama **45 detik** → koneksi dianggap putus. Server menutup stream saat JWT kedaluwarsa; client masuk ulang, bukan retry tanpa batas pada `401`.
- Dua kegagalan SSE berturut-turut mengaktifkan polling REST: awal **60 detik**, lalu **120/240/300 detik** saat gagal, jitter ±10%; kembali 60 detik setelah sukses. Percobaan naik kembali ke SSE setiap 5 menit saat aktif/online. Poll dan SSE tidak berjalan bersamaan sebagai kanal aktif; koneksi berhasil menghentikan timer polling.
- Cursor memakai **sequence per pengguna yang dialokasikan secara serial dalam transaksi**, bukan hanya timestamp/ID global yang dapat commit tidak berurutan. SSE `id` adalah cursor pengguna; REST catch-up memakai `since_sequence` bersama `cursor_user_id`, ascending, limit default 20 maksimum 50 sampai `has_more=false`. List riwayat biasa tetap `limit/offset` terbaru dahulu. Bentuk envelope terkunci di API_CONTRACT.md; SSE id berformat user_uuid:sequence dan memverifikasi pemilik cursor.
- Cursor maju hanya setelah record diterima/diproses; disconnect dapat mengirim ulang record (at-least-once). Client deduplikasi berdasarkan notification ID dan ID notifikasi lokal yang stabil, memisahkan last_received dari read_at. Deduplikasi/cursor di memori sesi; pada login/restart muat high-water mark dan riwayat sebagai baseline tanpa memunculkan ulang seluruh notifikasi lama. Reconnect/resume sesi yang sama catch-up dari cursor; jumlah notifikasi lokal saat backlog dibatasi satu ringkasan per catch-up, detail tetap di riwayat.
- Saat aplikasi paused/inactive, tutup SSE dan hentikan polling/reconnect timer. Saat resumed, lakukan catch-up lalu buka SSE mulai cursor terakhir agar tidak ada celah. Stream sendiri juga harus mendukung replay. Tidak ada jaminan notifikasi ketika app ditutup/di-kill; OS izin ditolak tetap memungkinkan banner/riwayat dalam aplikasi.
- MVP tidak memangkas log otomatis selama periode UAS. Cursor di luar rentang atau salah pengguna ditolak dengan error yang mengarahkan sinkronisasi baseline; tidak diam-diam melewatkan record. Logout menghentikan kanal dan membersihkan data akun lama.
- Replay membawa status lifecycle terkini selain snapshot alasan saat penerbitan. CAP yang sudah expired/cancelled/superseded tetap ada dalam riwayat, tetapi tidak memunculkan notifikasi lokal sebagai peringatan aktif. Client tidak menyimpulkan keaktifan dari snapshot lama saja.

## 6. State UI bersama dan perilaku kegagalan

| State | Perilaku wajib dan jalur pemulihan |
|---|---|
| Loading awal | Indikator ringan, cegah aksi ganda; tidak menampilkan “kosong” sebelum hasil diterima. |
| Refresh/loading halaman berikut | Data sebelumnya tetap terlihat dengan status memperbarui; kegagalan halaman tidak menghapus halaman yang sudah ada. |
| Empty | “Belum ada informasi yang cocok dengan radius ini”; beri filter Semua/ubah zona. Tab Saya/Tinjau menyebut tidak ada laporan, tanpa klaim aman. |
| Error validasi | Kesalahan dekat field, input/foto tetap tersedia; kode error API dipetakan ke Bahasa Indonesia. |
| Error jaringan/server | Tombol coba lagi eksplisit; tidak retry POST/moderasi tanpa idempotensi/version. Riwayat yang sudah termuat tidak hilang. |
| Offline API | Tampilkan data terakhir di memori sesi beserta waktu, nonaktifkan submit/moderasi yang perlu server; tidak mengklaim tersimpan. Cold start tanpa API tidak menyediakan login offline. |
| Degraded/stale sumber | API masih berjalan dari cache PostgreSQL; status per TEWS/Nowcast dan waktu sukses terakhir terlihat, tidak menganggap feed kosong sebagai tidak ada kejadian. |
| Tile/gambar gagal | Placeholder dan retry; feed/detail teks tetap berfungsi. Signed URL expired boleh diminta ulang satu kali, tidak retry permanen. |
| Konflik moderasi | Jelaskan laporan telah berubah, refetch, tampilkan reviewer/status terbaru; tidak menimpa otomatis. |
| Token habis | Hentikan kanal, kembali langkah login layar Akun; setelah login fetch ulang state server. Draft hanya dipertahankan di sesi bila aman. |
| SIMULASI | Banner menetap pada semua layar data, badge kartu/detail, prefix notifikasi dan foto demo; tidak hanya ditulis di README. |

## 7. Acceptance criteria lintas modul dan kasus tepi

Setiap AC di bawah harus menjadi fixture/test otomatis atau langkah demo yang dicatat hasilnya saat build. Hari 2 mendefinisikan target, belum menjalankan pengujian aplikasi.

| ID | Given / When | Then yang dapat diuji |
|---|---|---|
| AC-01 | Daftar memasukkan role admin; citizen memanggil moderasi; guest membaca feed | Role input ditolak, citizen `403`, guest `401`; tidak ada perubahan DB. |
| AC-02 | Izin GPS ditolak, user memilih titik manual dan radius default | Zona 50 km tersimpan; login berikut mendapat zona sama; tidak ada background GPS. |
| AC-03 | Radius 30, lat 91, lon 181, NaN/Infinity, zona kedua | `422` untuk input invalid; update zona tidak membuat baris kedua; unique user_id berlaku. |
| AC-04 | Titik sama; titik konstruksi pada 25/50/100 km; titik 1 meter di luar | Jarak nol; batas termasuk; di luar ditolak. Keputusan memakai presisi penuh, bukan angka satu desimal. |
| AC-05 | Titik pantau `(0,179.9)` dan gempa `(0,-179.9)`, radius 25 km; kandidat dekat kutub | Jarak sekitar 22.239 km dan termasuk; bbox antimeridian/kutub tidak membuang kandidat yang lolos Haversine. |
| AC-06 | Fixture skor `10/50 km, M5, umur 2 jam`; nilai tepat 35 dan 65; magnitudo null | 74.25/74.3 dan prioritas tinggi; 35 perhatian, 65 tinggi; null memberi “belum tersedia”. Waktu beku menghasilkan alasan yang sama. |
| AC-07 | Tiga TEWS memuat waktu/koordinat sama dengan optional field berbeda; sync dua kali | Satu event, Potensi/Dirasakan/Shakemap tergabung; tidak ada notifikasi ganda; key tidak memuat nama file. |
| AC-08 | Nowcast beberapa polygon; titik di polygon kedua, di tepi, di luar dekat vertex, atau tanpa polygon | Dua pertama inside_polygon; dekat vertex memakai label perkiraan; invalid geometri hanya Semua/Detail tanpa alert/marker fiktif. |
| AC-09 | Polygon CAP melintasi ±180; titik dekat garis itu; disk hanya menyentuh tengah sisi jauh dari vertex/centroid | Inside test antimeridian benar. Kasus sisi mendemonstrasikan keterbatasan near_polygon_sample, bukan mengklaim irisan eksak; alasan/label perkiraan ada. |
| AC-10 | CAP tepat expires, Cancel dengan references valid, Update superseding, status Test, expires hilang | Tidak eligible sebagai alert aktif; versi superseded tidak tampil aktif; data Test tidak masuk live; missing expiry berlabel tidak lengkap. |
| AC-11 | TEWS timeout, Nowcast sukses; XML berbahaya/JSON rusak | Cache TEWS utuh dan degraded; Nowcast maju; invalid tidak menghasilkan event/alert; last_success tidak dipalsukan. |
| AC-12 | Toggle cuaca mati lalu hidup atau radius diganti setelah event tersimpan | Feed tetap dapat melihat cuaca; tidak ada notifikasi historis baru; event baru berikut memakai zona/preferensi terakhir. |
| AC-13 | 120 kandidat marker dan 75 item feed; request limit 51 | Hanya 100 marker total, truncated=true; list 20 default dan maksimum 50; 51 ditolak. ID item tidak berulang saat load-more client. |
| AC-14 | Upload JPEG >2 MiB, file non-gambar mengaku JPEG, dimensi >4096, atau entity/DTD XML | Upload ditolak `413/415/422` sesuai sebab; XML ditolak sebelum parse; tidak ada record/objek aktif yang tidak sah. |
| AC-15 | Storage gagal sebelum SQL; SQL gagal setelah upload; respons sukses hilang lalu retry key sama | Tidak ada laporan separuh jadi; objek dibersihkan atau tercatat cleanup; retry mengembalikan satu laporan sama. Hash payload berbeda dengan key sama → `409`. |
| AC-16 | Laporan pending milik A diminta B termasuk URL foto; kemudian verified | Sebelum verified `404` dan tanpa URL; sesudah verified publik menerima data tersanitasi tanpa email/EXIF/audit privat. |
| AC-17 | Dua admin mengklaim expected_version sama secara bersamaan | Satu sukses dan satu `409`; tepat satu audit pending → in_review; hanya pemegang klaim dapat memutuskan. |
| AC-18 | Self-review, skip pending → verified, final diubah, insert audit gagal | Ditolak sesuai aturan; kegagalan audit rollback status; tidak ada keputusan tanpa jejak. |
| AC-19 | SSE putus setelah menerima item tetapi sebelum cursor diakui client; ada dua commit notifikasi konkuren | Replay tidak melewatkan item karena sequence per-user; deduplikasi tidak menambah popup ganda; stream hanya milik user. |
| AC-20 | SSE gagal dua kali, polling gagal berulang, app paused/resumed, token expired | Interval 60→120→240→300 dengan jitter; tidak ada timer berjalan saat paused; catch-up saat resume; 401 meminta login, tidak loop retry. |
| AC-21 | DB gagal saat transaksi sync/notification; proses mati sebelum commit | Tidak ada setengah batch; retry membuat event/log tepat sekali secara logis; kegagalan satu sumber tidak menghapus data sumber lain. |
| AC-22 | Internet/Railway/Supabase dinonaktifkan; backend+PostgreSQL+storage lokal berjalan | Alur akun sampai moderasi dan notifikasi fixture tetap berhasil; semua data demo bertanda SIMULASI; tile gagal memiliki fallback daftar. |
| AC-23 | Izin notifikasi OS ditolak; app di-kill lalu dibuka | Banner/riwayat tersedia ketika aktif; tidak menjanjikan push saat mati; login baru memuat baseline tanpa popup seluruh histori. |
| AC-24 | Keluar akun A lalu masuk B; akses URL foto kedaluwarsa; auth brute force melewati batas | Tidak ada data/stream akun A; URL gagal lalu refresh lewat API berotorisasi; throttle `429` dengan Retry-After. |

## 8. Keamanan, privasi dan integritas

- TLS untuk produksi, rahasia hanya env server/hosting; tidak ada service-role Storage, password database, JWT signing key atau `.env` dalam repo/APK/log. Akses database hanya backend dengan hak terbatas; tabel bisnis tidak dibuka untuk anon Supabase. JWT memeriksa algoritma allowlist, signature, issuer, audience, subject dan expiry; role/akun aktif dibaca server, bukan dipercaya dari request.
- Baseline rate limit satu instans demo: login 5 percobaan/menit/IP, register 3/menit/IP, submit laporan 5/menit/user, API baca 120/menit/user, maksimum satu SSE aktif/user. Implementasi in-memory memadai untuk satu instans, reset saat restart dicatat; bukan proteksi multi-instance. Middleware proxy tidak mempercayai X-Forwarded-For dari sembarang pengirim.
- XML diperlakukan input tak tepercaya: hanya HTTPS host/path BMKG yang diizinkan; setiap redirect divalidasi ulang; tidak boleh menuju localhost/private IP/file URL. Tolak DTD/entity sebelum stdlib XML parse, encoding didukung dibatasi UTF-8, nonaktifkan XInclude, batasi hasil dekompresi **2 MiB per dokumen**, kedalaman **32**, **50.000 node**, **10.000 vertex per CAP**. Payload melewati batas disisihkan, bukan dipotong diam-diam menjadi geometri palsu. Maksimum 50 dokumen CAP per siklus; backlog valid diproses siklus berikut, status partial sampai habis. Jangan mengambil arbitrary URL dari user.
- Field teks dari laporan/BMKG ditampilkan sebagai teks biasa, bukan HTML executable. Query terparameterisasi melalui ORM. Validasi server dan CHECK SQL saling melengkapi.
- Foto disanitasi sebelum penyimpanan. URL baca privat berlaku **5 menit**, diterbitkan backend hanya sesudah otorisasi; pemegang URL dapat membacanya selama masa berlaku sehingga UI tidak membagikan URL. Local adapter menerapkan token URL, expiry, dan validasi akses setara, bukan direktori statis publik.
- Publik memperoleh titik kejadian yang memang disubmit, bukan titik pantau pengguna/email pelapor. Admin melihat data seperlunya; koordinat zona tidak masuk analytics/log umum. Jangan mengunggah foto wajah/identitas yang tidak diperlukan; tampilkan arahan singkat pada form.
- Audit append-only pada API; akun DB runtime tidak diberi UPDATE/DELETE untuk audit. Perubahan status harus melalui service transaksi. Audit dan status privat tidak dikirim di list publik. Tidak ada hard delete akun/event/laporan selama MVP; FK RESTRICT untuk entitas yang dirujuk, dirinci di ERD.sql.
- Log operasional berisi request ID, sumber, durasi dan kode error; redaksi token, password, signed URL, email lengkap, koordinat zona dan isi foto. Endpoint health publik hanya status minimal; diagnosis internal tidak mengeluarkan DSN/stack trace.

## 9. Fallback dan mode demo

| Mode | Infrastruktur/data | Perilaku |
|---|---|---|
| Production live | Railway + PostgreSQL Supabase + Supabase Storage + BMKG | HTTPS, data aktual, kesegaran per sumber. |
| Local live | FastAPI localhost + PostgreSQL lokal + file adapter lokal + BMKG jika internet tersedia | Kontrak sama; tidak memerlukan Railway/Supabase. Tidak otomatis berarti offline. |
| Local SIMULASI | FastAPI dan PostgreSQL lokal + file lokal + fixture/seed terpisah | Seluruh alur bisnis berjalan tanpa internet, worker live dimatikan; event/foto/notifikasi bertanda SIMULASI. |
| Sumber gagal | API/database masih hidup, cache terakhir | Degraded/stale; tidak beralih diam-diam ke seed. |
| API tidak terjangkau | Cache memori Flutter bila sudah ada | Baca terakhir saja, tidak bisa login baru/submit/moderasi; berbeda dari local SIMULASI yang backend-nya tetap hidup. |

Pemilihan mode eksplisit lewat `.env` backend dan konfigurasi API base URL Flutter; database/bucket/folder simulasi terpisah dari live. Snapshot BMKG yang diputar ulang tetap berlabel **SIMULASI — snapshot historis**, mempertahankan waktu asli dan menambahkan waktu simulasi terpisah bila diperlukan untuk test expiry. Seed menghasilkan citizen, dua admin, zona, event dalam/luar/batas radius, Nowcast aktif/expired, laporan semua status dan notifikasi. Tidak ada fallback SQLite/NoSQL.

Alamat localhost milik host tidak sama dengan perangkat: emulator Android mengarah ke `10.0.2.2`, HP fisik ke IP LAN host. HTTP cleartext hanya konfigurasi development lokal. Peta offline penuh tidak disediakan; tile OSM dapat tidak tersedia, tetapi data/daftar dan pemilihan koordinat manual pada panel Peta tetap dapat dipakai tanpa tile.

## 10. Non-functional requirements terukur

Baseline pengukuran: Android fisik RAM 4 GB, build profile/release; backend satu instans 1 vCPU/512 MiB, PostgreSQL dengan 10.000 event, 2.000 laporan, 100 akun/zona, 20 client aktif. Catat spesifikasi nyata bila berbeda. Seed uji performa adalah fixture pengujian, bukan perluasan scope produk.

| ID | Target dan cara ukur |
|---|---|
| NFR-01 | Feed 20 item dan marker 100 p95 waktu server <=500 ms pada data baseline, 20 request konkuren; jaringan/BMKG/upload tidak dimasukkan. Query count dan EXPLAIN dicatat bila gagal. |
| NFR-02 | Payload JSON 20 item <=100 KiB tanpa gambar; marker <=150 KiB; list tidak memuat polygon/audit/base64. Ukur serialisasi response fixture terpadat. |
| NFR-03 | Feed awal terlihat <=2 detik pada RTT <=100 ms dan koneksi >=5 Mbps; saat scroll 20 item/100 marker, minimal 95% frame memenuhi 16.7 ms pada layar 60 Hz di perangkat baseline. Profile selama 60 detik, thumbnail lazily loaded. |
| NFR-04 | Target APK Android arm64 release <=40 MiB dan peak RSS client <=200 MiB pada skenario demo; ukur hasil nyata, optimasi aset/dependency bila lewat, tanpa menghapus fitur wajib. |
| NFR-05 | Setelah commit notification_logs, event tampil via SSE p95 <=5 detik saat aktif; polling normal <=70 detik. Latensi dari sumber mencakup interval sync hingga 300 detik dan tidak diklaim real-time absolut. |
| NFR-06 | Satu koneksi SSE aktif, nol timer jaringan notifikasi/GPS ketika app paused; ukur lifecycle dan jumlah request, bukan klaim baterai tanpa pengukuran. |
| NFR-07 | Pengulangan job/request idempoten dan dua moderator bersamaan lulus AC-07/15/17/19/21 pada PostgreSQL asli, bukan SQLite. |
| NFR-08 | Password/token/EXIF tidak muncul pada snapshot respons publik/log/foto hasil; uji IDOR pada report/photo/history, SQL injection, ukuran upload dan XML berbahaya sebelum rilis. |
| NFR-09 | Teks Indonesia, ukuran teks sistem 200% tanpa overflow kritis, target sentuh minimal 48 logical px, ikon/teks selain warna untuk status; uji layar sempit 360 logical px. |
| NFR-10 | Dengan dependency sudah terpasang, operator dapat menjalankan local SIMULASI dari runbook dalam <=10 menit dan mendemokan alur inti tanpa internet. Uji setelah Railway/Supabase dimatikan, bukan sekadar mengganti URL API. |

## 11. Rencana validasi, ketergantungan dan selesai MVP

Unit test: normalisasi TEWS/CAP, waktu UTC, Haversine/antimeridian, skor, polygon dan eligibility dengan jam beku. Integrasi PostgreSQL: constraint, upsert, dua admin konkuren, idempotensi upload dan urutan replay. Integrasi HTTP: auth, timeout/partial feed, Storage gagal, SSE putus/resume/expiry. Flutter: ViewModel loading/error/degraded, router guard, form, lifecycle serta smoke test end-to-end. Pemeriksaan keamanan dan performa dilakukan saat build/QA, bukan dianggap lulus karena dokumen selesai.

Risiko dan keputusan: toleransi key TEWS tidak mengatasi revisi koordinat; pencocokan luar polygon Nowcast bersifat perkiraan; CAP lifecycle tak lengkap tidak memicu alert; OSM/BMKG memerlukan jaringan live; SSE/timeout proxy dan koneksi pooler Railway harus dibuktikan pada deployment; pemegang klaim moderasi harus tersedia. Mitigasi berada dalam batas MVP: label jujur, fixture deterministik, fallback cache/lokal, PostgreSQL transaction, dan runbook.

Urutan implementasi Antigravity (jadwal rilis 1 Des, disesuaikan 27 Nov pasca-jeda 23–25 Nov & 27 Nov): **17–18 Nov foundation + akun/zona**, **19–21 Nov kedua sumber BMKG + radius/skor + peta/detail**, **22 Nov laporan/foto + moderasi/audit + UI-04 + Full Slice 5 (`5-1`..`5-3`)**, **26 Nov uji perangkat Android + Batch 1 `C1–C6` & feature freeze 26 Nov**, **28 Nov poles UI/UX menyeluruh**, **29 Nov – 1 Des QA, security audit, deploy Railway/fallback & rilis `v1.0.0`**. Setiap slice database → API → Flutter → test → commit oleh Antigravity. Tidak menunda rancangan notification_logs/eligibility sampai slice terakhir; skema dan transaksi sync disiapkan sejak slice sumber.

Definition of Done MVP: UI-01..06 dan FR-01..07 tersedia, AC-01..24 mempunyai hasil lulus/bukti, NFR diukur dan masalah material diperbaiki, tidak ada kebocoran kredensial/data privat, demo lokal serta live diuji, dan dokumentasi menjalankan aplikasi selesai. Lock Planning (16 Nov) mengunci DDL, request/response/error/cursor, dan wireframe tanpa menambah layar/fitur. Tidak ada fitur baru setelah 26 November 2026.

## 12. Penamaan final saat Lock Planning

Kontrak wire/SQL memakai `is_simulated` untuk flag SIMULASI, `priority_algo` untuk versi algoritma, `priority_score` mentah dan `priority_display` satu desimal. Source resmi `BMKG_TEWS|BMKG_NOWCAST`; source warga `CITIZEN` hanya DTO. Kategori wire `earthquake|flood|eruption|extreme_weather|haze_other`, resmi hanya earthquake/extreme_weather. Status CAP pada `disaster_events.status` berbeda dari `citizen_reports.status`; `lifecycle_status` dihitung server. Schema SQL `siaga`, UUID seluruh PK, koordinat bumi finite (bukan pembatas Indonesia), longitude kanonik [-180,180).

`GET /api/v1/me/notifications/sync` memakai `since_sequence` dan `cursor_user_id`, baseline eksplisit saat login; SSE id `user_uuid:sequence` mendeteksi perpindahan akun. Mark-read `POST /api/v1/me/notifications/{notification_id}/read` idempoten. `payload_hash` laporan dihitung server dengan `report-payload-v1`; client hanya mengirim `client_request_id` bersama snapshot multipart yang sama. Zone baru/berubah tidak memberi backlog, PUT identik tidak mereset cutoff. Jam simulasi hanya domain, JWT/URL/lease memakai jam dinding. Detail request/DTO/error, canonical hash, freshness, urutan dan guard zona mengikuti [API_CONTRACT.md](API_CONTRACT.md); tidak ada alias nama lama.
