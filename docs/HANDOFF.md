# Handoff — Hari 2, 16 November 2026

**Author:** Jiddan Ibnu Ali — **NIM:** 24051214203  
**Peran sesi:** Codex Planner & Architect  
**Berikutnya:** Lanjutan Senin, 16 November 2026 — **Lock Planning** pada akhir hari (`ERD.sql`, `API_CONTRACT.md`, `UI_SPEC.md`).

## 1. Hasil sesi dan acuan

Dibaca terlebih dahulu: `AGENTS.md`, `README.md`, `docs/README.md`, `docs/IDEA.md`, dan handoff Hari 1.

| Artefak | Hasil |
|---|---|
| [PRD.md](PRD.md) | Tujuan terukur, persona/matriks akses, scope, lima layar plus Detail; UI-01..06, FR-01..07, AC-01..24, NFR-01..10; aturan radius/skor/CAP, moderasi, upload, alert, state UI dan fallback. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Tujuh diagram Mermaid: sistem, user flow, lifecycle alert, sequence sync/notifikasi, sequence upload/moderasi, state laporan, dan fallback. Layer, relasi SQL, transaksi, lease, storage adapter, keamanan dan runbook demo. |
| [HANDOFF.md](HANDOFF.md) | Keputusan Hari 2 dan instruksi siap-eksekusi Hari 3; mempertahankan keputusan terkunci Hari 1. |

Perubahan sesi terbatas pada ketiga file ini. Implementasi aplikasi, DDL, kontrak API dan wireframe belum dibuat. Tidak ada perintah Git yang dijalankan; Git/GitHub tetap dikelola Antigravity.

Narasi awal README tentang banjir/erupsi dari BMKG lebih luas dari scope final IDEA: otomatis hanya **TEWS + Nowcast**, banjir/erupsi melalui warga. README tidak diubah karena di luar scope sesi. Catatan verifikasi feed/wheel yang masih terbuka pada Hari 1 telah dijawab oleh fakta live yang diberikan user pada Hari 2.

## 2. Empat keputusan Hari 1 tetap TERKUNCI

1. **Cakupan:** BMKG Gempa & Potensi Tsunami dari tiga `DataMKG/TEWS` JSON serta Cuaca Ekstrem dari RSS `https://www.bmkg.go.id/alerts/nowcast/id` → CAP 1.2 XML. Toggle preferensi alert per user. Laporan warga tepat lima kategori: **Gempa, Banjir, Erupsi, Cuaca Ekstrem, Kabut Asap/Lainnya**. Maritim ditangguhkan ke pasca-UAS `v1.0.0`; tidak ada feed erupsi/PM2.5 otomatis.
2. **Dua pembeda:** Radar Radius dengan `S = 60P + 25M + 15T` khusus gempa dan alasan deterministik; Nowcast memakai wilayah/polygon, severity dan lifecycle CAP tanpa rumus gempa. Pembeda kedua laporan berjejak verifikasi. Skor adalah **prioritas informasi, bukan risiko ilmiah/peringatan resmi**; di luar radius bukan berarti aman.
3. **Zona:** satu titik GPS sekali/manual per akun, radius `25 / 50 / 100 km`, default `50 km`; tanpa multi-zona/background GPS.
4. **Moderasi:** role admin menggunakan **Tab Tinjau pada Lapor Warga**, state `pending → in_review → verified/rejected` dalam transaksi SQL dengan `report_verifications`; tanpa web admin terpisah.

Jangan membuka ulang keputusan tersebut. Batas UI: Akun & Set Radius, Beranda & Feed, Peta, Lapor Warga, Profil & Riwayat, serta satu Detail Bencana. Form/tab/panel berada pada layar yang ada.

## 3. Keputusan rinci Hari 2

| Area | Baseline Hari 3 |
|---|---|
| Auth | Guest hanya masuk/daftar; feed publik berarti semua akun terautentikasi. Pendaftaran selalu citizen; admin diprovisi operator. Argon2 + JWT bearer 60 menit, token di memori sesi, tanpa refresh MVP. Restart meminta login. |
| Preferensi | Dua boolean default aktif: Gempa & Potensi Tsunami, Cuaca Ekstrem. Toggle memengaruhi notifikasi baru, bukan visibilitas feed. Perubahan zona/toggle menaikkan version dan memperbarui alert_eligible_since; tanpa backlog historis. |
| Radius | Haversine R=6371.0088 km, bbox konservatif, antimeridian/kutub ditangani, batas inklusif dengan toleransi 0.000001 km. Pembulatan tampilan tidak menentukan eligibility. |
| Skor | eq-priority-v1; P=clamp(1-d/r), M=clamp(m/10), T=clamp(1-umur_jam/24). Label <35 biasa, 35–<65 perhatian, >=65 tinggi. Contoh 10/50 km, M5, umur 2 jam →74.25, tampil 74.3 dengan pembulatan half-up. Data wajib null → prioritas belum tersedia. |
| Nowcast | cap-priority-v1; point-in-polygon seluruh polygon, boundary termasuk; di luar memakai minimum jarak centroid/vertex dengan label perkiraan. Bukan irisan radius-poligon eksak. Invalid geometri → Semua/Detail saja tanpa alert lokasi. Extreme/Severe tinggi, Moderate perhatian, Minor informasi, Unknown belum tersedia. |
| Lifecycle CAP | Actual dan effective <= now < expires, belum cancelled/superseded. Effective kosong memakai sent, expires hilang tidak layak alert. Update/Cancel memakai references bila tersedia; lifecycle tidak lengkap tidak menerbitkan alert baru. Jangan mengasumsikan references selalu tersedia. |
| Sync | Interval 300 detik, timeout 15 detik/request, retry 2/4 detik, deadline 240 detik; lease SQL per sumber300 detik dengan token/fencing. Bootstrap pertama tanpa alert historis. Degraded saat gagal/partial; stale setelah 15 menit tanpa sukses. |
| Identity TEWS | SHA256 namespace TEWS + DateTime UTC kanonik + lat/lon enam desimal, tanpa nama endpoint. Optional field digabung; konflik satu siklus auto → terkini → dirasakan. Koreksi waktu/koordinat dapat membentuk key baru, tanpa fuzzy merge. |
| Notifikasi | official_new unik user/event/kind, hanya event resmi baru cocok lokasi/preferensi/cutoff; gempa umur<=24 jam dan CAP aktif. Skor bukan syarat. Event+log+checkpoint batch commit bersama. Sequence per-user dialokasikan melalui counter row lock sampai commit, bukan global serial ID. |
| SSE/polling | Satu SSE saat resumed; heartbeat 20 detik, timeout 45 detik. Dua kegagalan → polling 60/120/240/300 detik ±10%; probe SSE tiap 5 menit. Paused menghentikan kanal/timer; resume catch-up. Login baru baseline tanpa popup histori. Tidak menjanjikan alert saat app mati. |
| Paging/peta | List default 20 maksimum 50 dengan offset; marker endpoint terpisah maksimal 100 total dan truncated. Urutan stabil dengan ID; client dedup saat list berubah. Tidak menyatukan skor gempa dan severity sebagai satu angka. |
| Upload | Satu foto opsional JPEG<=2 MiB; request<=3 MiB. Client1024 px/~75%; server input max 4096 px/16 MP, decode/re-encode max 1024 px tanpa EXIF. Deskripsi 20–1000 karakter. Bucket privat dan URL baca 5 menit melalui backend. |
| Retry upload | client_request_id UUID + payload_hash, unique reporter/key. Payload sama mengembalikan laporan sama, beda 409. Compensating delete hanya objek tak direferensikan; cek commit ambigu dahulu. Cleanup SQL/reconciliation objek>24 jam hanya ketika DB sehat. |
| Moderasi | expected_version, bukan pelapor sendiri, keputusan final hanya pemegang klaim dengan alasan 10–500 karakter. Konflik409, role/self-review 403. Status+audit atomik; tidak ada edit final/reassignment otomatis MVP. |
| Privasi | Pending/in_review/rejected dan foto hanya pemilik/admin. Publik verified tanpa email, EXIF atau audit privat; koordinat yang tampil adalah titik kejadian, bukan titik pantau pengguna. |
| Fallback | Production live, local live dan local SIMULASI dipilih eksplisit. PostgreSQL lokal + adapter file privat; database/folder demo terpisah. Label SIMULASI di banner/kartu/detail/notifikasi; tile gagal memakai daftar/input koordinat pada panel Peta. |

Detail angka, keamanan dan NFR mengikuti PRD, bukan dibuat ulang berbeda di kontrak. Stack tetap Flutter 3.47.7/Dart 3.13.5 dengan Provider MVVM tanpa build_runner, go_router, http, geolocator, flutter_map+OSM, flutter_local_notifications; Python 3.15.0/FastAPI 0.163.0/Uvicorn 0.54.0, SQLModel/SQLAlchemy, Pydantic v2, psycopg[binary], httpx, python-multipart, pytest; PostgreSQL+Supabase Storage/Railway dan localhost. Tanpa NoSQL/Firebase SDK/akses tabel Supabase langsung/chat/komentar/voting.

## 4. Fakta diterima dan validasi tersisa

**Hasil live yang diberikan user pada 16 Nov, tidak diulang pada sesi dokumentasi:**

- TEWS tidak memiliki ID numerik tunggal. DateTime ISO UTC dan Coordinates lat/lon; Potensi pada auto/terkini, Dirasakan pada auto/dirasakan, Shakemap pada auto. Field lainnya sesuai PRD. Jangan merancang upsert memakai ID BMKG yang tidak ada.
- Nowcast RSS 2.0 memiliki link `*_alert.xml`, guid OID dan pubDate. CAP namespace `urn:oasis:names:tc:emergency:cap:1.2`, header/info, areaDesc provinsi dan beberapa polygon lat/lon. Pencocokan otomatis memakai koordinat, tanpa meminta kode kecamatan baru.
- `fastapi==0.163.0`, `uvicorn==0.54.0`, `sqlmodel`, `pydantic-settings`, `psycopg[binary]`, `httpx`, `python-multipart`, `pytest`, `pillow`, `pwdlib[argon2]`, `pyjwt` lolos pemeriksaan wheel Python 3.15 dengan `--only-binary=:all:` exit 0. Paket tanpa versi angka dipin saat build berdasarkan resolusi kompatibel.

**Masih perlu dibuktikan saat implementasi:** runtime paket; proxy/timeout/buffering SSE Railway; TLS/pooler Supabase; storage cloud/lokal; concurrency SQL; performa dan lifecycle Android. Ini bukan alasan mengganti stack atau mengklaim deployment sudah berjalan.

## 5. Instruksi Hari 3 — docs/ERD.sql

Tujuan: DDL PostgreSQL lengkap untuk Supabase dan lokal dengan skema sama, berdasarkan PRD FR-01..07 dan arsitektur bagian 8.

1. Tetapkan schema, strategi ID, timestamptz UTC, tipe angka, nullability/defaults, PK/FK/CHECK/UNIQUE/index. Guest bukan role SQL. Zona unik per user, koordinat finite valid, radius preset, dua preferensi, version dan cutoff.
2. Buat inti users, alert_zones, disaster_events, citizen_reports, report_verifications, notification_logs, sync_runs; pendukung event_areas, area_polygons, polygon_vertices, event_references, media_cleanup_jobs. CAP multi-area/polygon tidak direduksi menjadi satu centroid.
3. Wajib unique source/key, reporter/client_request_id, report/resulting_version, user/event/kind, user/sequence; reviewer bukan reporter, konsistensi reviewer/status, kategori/status/transisi valid. Aturan lintas tabel/peran memakai service transaksi/trigger yang tepat, bukan CHECK dengan subquery ilegal.
4. Counter per-user dan lock zona harus mendukung cursor sesuai commit. Log menyimpan snapshot alasan, evaluated_at, zone_version; read_at terpisah. Jangan memakai urutan bigserial global sebagai jaminan urutan commit.
5. Index FK/filter/order/radius kandidat, partial unique running sync per sumber, lease token/expiry dan cleanup. FK inti RESTRICT untuk audit/riwayat, bukan cascade tak sengaja. Runtime audit append-only.
6. Komentar SQL menjelaskan transaksi upsert+notification+checkpoint, klaim/keputusan dan idempotensi upload. Seed SIMULASI dipisahkan dari DDL produksi; tidak ada password/kredensial nyata. JSONB hanya metadata pendukung, bukan pengganti relasi.

**Gate ERD:** FK/tipe/enum/null konsisten; semua unique/index untuk AC konkuren tersedia; tanpa ekstensi GIS. Jika PostgreSQL disposable lokal tersedia dan diotorisasi pada sesi berikutnya, apply/test di sana; jika tidak, catat batas validasi, jangan mengklaim DDL sudah dieksekusi.

## 6. Instruksi Hari 3 — docs/API_CONTRACT.md

Tujuan: kontrak REST JSON/multipart dan SSE siap implementasi. Baseline prefix `/api/v1`; nama endpoint final dikunci Hari 3.

| Kelompok | Endpoint calon dan cakupan |
|---|---|
| Auth | POST /auth/register, POST /auth/login, GET /me; tidak ada role input/refresh/forgot-password. Logout client menghapus sesi; jelaskan token tetap valid sampai expiry bila tidak ada revocation. |
| Zona | GET dan PUT /me/zone; lat/lon, radius, dua toggle, version dan eligible_since server. |
| Resmi | GET /events dan /events/{id}; filter/urutan, source/freshness, score nullable, CAP lifecycle, reasons/match_method, is_simulation. |
| Peta | GET /map/markers; resmi+warga verified, cap 100/truncated, payload ringkas; berbeda dari limit list 50. |
| Warga | POST /reports multipart idempoten, GET /reports dan /reports/{id}; scope sekitar/saya/tinjau sesuai role. Detail laporan ditampilkan inline, bukan layar baru. |
| Foto | GET /reports/{id}/photo-url; URL5 menit setelah otorisasi; route local dengan signature/expiry. |
| Moderasi | POST /reports/{id}/claim, POST /reports/{id}/decision, GET /reports/{id}/verifications; expected_version, outcome/reason dan konflik. |
| Alert | GET /me/notifications, /me/notifications/sync, /me/notifications/stream; aksi mark-read idempoten. Offset history berbeda dari after_sequence catch-up. |
| Operasional | Health/readiness minimal, metadata mode/freshness; sync/seed bukan endpoint pengguna. |

Untuk setiap endpoint, tulis metode/path, role/ownership, schema request/response dengan tipe/null/unit, validasi, contoh sukses, status HTTP, error, efek SQL, idempotensi dan paging. ISO8601 UTC, enum stabil, DTO publik terpisah dari internal; jangan membocorkan email/hash/audit.

Detail wajib:

- Envelope error konsisten seperti code/message/details/request_id; 401/403/404/409/413/415/422/429/503. Cache stale tetap 200 bila API+DB sehat. Retry-After untuk throttle; tidak loop retry 401.
- Contoh skor 74.25, data null, label 35/65, radius antimeridian, CAP inside/near-sample/no-geometry/expired dan SIMULASI. Tetapkan field sumber resmi/warga dan label perkiraan.
- Multipart satu file 2 MiB/request 3 MiB, client_request_id, hash mismatch409, status pertama/replay (misalnya 201/200), storage failure dan retry dengan hasil sama.
- expected_version, pemegang klaim, larangan self-review/skip state, konflik dua admin dan rollback audit. Akses catatan/foto/pending tidak boleh bocor.
- SSE framing id/event/data dan komentar heartbeat; text/event-stream; bearer header, cursor precedence, replay/baseline high-water mark, batch20/max 50/has_more. Cursor scoped per-user dan monoton sesuai commit; invalid/out-of-range mengarahkan baseline eksplisit. Tidak ada pemangkasan log otomatis MVP.
- last_received vs read_at; dedup, resume/login baru, token expiry stream, SSE/polling saling eksklusif, tanpa push saat mati. Replay event yang sudah expired/cancelled tidak boleh dipresentasikan sebagai peringatan aktif; riwayat tetap tersedia dengan status aktual.

**Gate API:** tiap FR/AC memiliki endpoint/aturan/bukti, field selaras ERD, contoh JSON valid, tidak ada endpoint Supabase bisnis langsung atau fitur di luar MVP.

## 7. Instruksi Hari 3 — docs/UI_SPEC.md

Tujuan: wireframe rendah fidelitas yang siap dibangun dengan Material 3 ringan. Markdown/ASCII/diagram cukup; referensi Figma hanya bila benar-benar tersedia, jangan mengarang tautan.

1. Buat tepat UI-01..06 sesuai PRD: lima layar utama plus satu Detail Bencana, empat bottom-nav setelah setup. Masuk/daftar/zona satu layar bertahap; form laporan inline/bottom sheet, warga panel, admin Tab Tinjau.
2. Setiap layar memuat hierarki komponen, tombol, endpoint/DTO, ViewModel, navigasi dan guard. Mode pilih titik zona/laporan menggunakan Peta yang sama, termasuk input lat/lon ketika tile offline.
3. Gambarkan loading, load-more, empty, error field/jaringan, offline, degraded/stale per sumber, konflik 409, izin GPS/notifikasi ditolak, token habis, tile/foto gagal dan SIMULASI.
4. Kartu BMKG/warga memakai ikon+teks berbeda. Gempa memiliki skor/jarak/alasan; CAP area/severity/match_method/masa berlaku; verified bukan pengesahan BMKG. Jangan menulis empty/outside sebagai aman.
5. Radius25/50/100 default 50, dua toggle, satu titik; marker maksimal 100/truncated, list 20/max 50, lazy image. Tab Tinjau memuat klaim/versi/alasan/hasil/refetch konflik. Profil status kanal dan riwayat baca.
6. Responsif 360 logical px, sentuh minimal 48, skala teks 200%, label aksesibilitas dan status bukan warna saja. Jangan menambah UI/animasi berat atau layar baru.

**Gate UI:** setiap UI/FR tercakup dan aksi menunjuk API, semua state gagal/SIMULASI terlihat, tidak menjanjikan push saat mati, cakupan poligon eksak atau peta offline penuh.

## 8. Planning lock dan kelanjutan Antigravity

Urutan Lock Planning (16 Nov): **ERD → kontrak API → wireframe → cross-check tiga arah → update HANDOFF → planning lock akhir 16 Nov**. Iterasi field antar dokumen boleh, tanpa membuka ulang empat keputusan Hari 1.

Checklist lock: field/enum/status/null/unit ERD–API–UI sama; akses foto/audit jelas; key sumber, lease, radius/CAP, versi skor, cursor, idempotensi dan version moderasi eksplisit; localhost/SIMULASI memakai kontrak sama; AC-01..24 punya rencana test; Mermaid valid; keterbatasan belum diuji tercatat.

| Tanggal | Vertical slice Antigravity (Revisi Rilis 27 Nov) |
|---|---|
| 17–18 Nov | Foundation Backend+DB+Mobile skeleton + akun/zona. Skema log/eligibility disiapkan sejak awal. |
| 19–21 Nov | Kedua sumber BMKG + radius/skor/CAP match + peta/detail dan pengujian antimeridian. |
| 22–23 Nov | Laporan/foto/privasi + moderasi transaksional/audit termasuk dua admin. |
| 24 Nov | SSE/polling/catch-up + uji perangkat & mode SIMULASI; **feature freeze 24 Nov**. |
| 25–27 Nov | QA (`25 Nov`), security audit & deploy/fallback (`26 Nov`), smoke test final & **rilis v1.0.0 (`27 Nov`)**. |
| Mulai 28 Nov | Video minimal 10 menit dan artikel maksimal 11–12 halaman. |

Setiap slice **Database → FastAPI → Flutter → Test → Commit** oleh Antigravity. Baca skill relevan yang tersedia sebelum slice sesuai AGENTS.md; daftar skill Antigravity bukan klaim bahwa semua tersedia di sesi Codex. Codex tidak menjalankan git init/add/commit/push atau mengubah remote/branch.

## 9. Pemeriksaan kualitas Hari 2

Hasil pemeriksaan dokumen:

- Ketiga file terbaca UTF-8 tanpa karakter pengganti; Markdown fence berpasangan, tabel konsisten dan seluruh tautan lokal menuju file yang ada.
- Definisi UI-01..06, FR-01..07, AC-01..24 dan NFR-01..10 lengkap, masing-masing muncul sekali sebagai definisi.
- Tujuh blok Mermaid menggunakan struktur standar: empat flowchart, dua sequenceDiagram, satu stateDiagram-v2. Pemeriksaan statis memeriksa kutipan label flowchart, node/participant, pasangan subgraph dan alt/opt/loop/end, serta ketiadaan HTML. Renderer/parser Mermaid resmi tidak tersedia di lingkungan sesi; preview visual GitHub belum diuji.
- Contoh aritmetika diperiksa: skor 74.25 → 74.3 dengan half-up; jarak antimeridian dari 179.9 ke -179.9 derajat pada ekuator sekitar 22.239016 km, termasuk radius 25 km.
- Hash berkas acuan AGENTS.md, README.md, .gitignore, docs/README.md dan docs/IDEA.md tidak berubah selama penulisan; perubahan hanya tiga dokumen yang diminta. Tidak ada perintah Git dijalankan.

Ini verifikasi dokumentasi, bukan hasil uji aplikasi. SQL, API, Flutter, deployment, keamanan runtime dan benchmark belum dijalankan; menjadi gate implementasi Antigravity.
