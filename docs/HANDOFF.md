# Handoff — Lock Planning selesai, 16 November 2026

**Author:** Jiddan Ibnu Ali — **NIM:** 24051214203  
**Peran:** Codex Planner & Architect  
**Status:** **Slice 3A SELESAI (19 Nov 2026) — siap Slice 3B: Peta & Feed (`UI-02` Beranda & `UI-03` Peta Browse), Jumat 20 November 2026.**  
**Target:** feature freeze24Nov; rilis `v1.0.0`27Nov2026. Rilis belum dilaksanakan.

## 1. Hasil sesi dan acuan

Dibaca menyeluruh: [AGENTS.md](../AGENTS.md), [indeks](README.md), [jadwal](SCHEDULE.md), [PRD](PRD.md), [arsitektur](ARCHITECTURE.md), handoff sebelumnya terutama bagian5–8. Hanya file dalam `docs/` diubah. Tidak ada perintah Git, tool FigCraft, file `.figcraft`/PNG, atau implementasi backend/mobile dalam sesi ini.

| Artefak | Status akhir |
|---|---|
| [ERD.sql](ERD.sql) | **SELESAI:** 12 tabel schema siaga, UUID/FK RESTRICT/CHECK/UNIQUE/index, counter sequence, lease, geometri relasional, trigger transisi/audit. DDL murni tanpa seed. |
| [API_CONTRACT.md](API_CONTRACT.md) | **SELESAI:** 22 kombinasi metode/path, DTO publik/privat, auth/error/paging, multipart/hash, signed media, mark-read, SSE/baseline/replay. |
| [UI_SPEC.md](UI_SPEC.md) | **SELESAI:** UI-01..06 Material3/ASCII, Screen/ViewModel, wiring exact, state per layar dan checklist a11y; brief visual FigCraft sesi berikutnya. |
| [PRD.md](PRD.md), [ARCHITECTURE.md](ARCHITECTURE.md) | Nama field/cursor, urutan lock dan status dokumen diselaraskan; empat keputusan Hari1 tetap. |
| [README.md](README.md), [SCHEDULE.md](SCHEDULE.md) | Link/index dan status lock diperbarui; Slice1 mencakup fondasi auth, finalisasi akun/zona18Nov. |
| [HANDOFF.md](HANDOFF.md) | Kontrak final, bukti validasi dan instruksi build berikut. |

README root tidak diubah. Narasi awal banjir/erupsi BMKG tetap ditafsirkan sesuai scope: otomatis hanya TEWS+Nowcast, banjir/erupsi melalui warga. Antigravity menangani Git/GitHub dan README implementasi nanti.

## 2. Empat keputusan Hari 1 tetap TERKUNCI

1. **Cakupan:** Gempa & Potensi Tsunami dari tiga DataMKG/TEWS JSON; Cuaca Ekstrem dari RSS `https://www.bmkg.go.id/alerts/nowcast/id` → CAP1.2. Lima kategori warga: Gempa, Banjir, Erupsi, Cuaca Ekstrem, Kabut Asap/Lainnya. Maritim pasca-UAS; tanpa feed erupsi/PM2.5 otomatis.
2. **Dua pembeda:** Radar Radius `S=60P+25M+15T` khusus gempa dan laporan warga berjejak verifikasi. Nowcast memakai polygon/severity/lifecycle. Skor **prioritas informasi**, bukan risiko ilmiah/prediksi/peringatan resmi; di luar radius bukan berarti aman.
3. **Zona:** satu titik GPS sekali/manual per akun, radius25/50/100km default50, dua toggle default aktif; tanpa multi-zona/background GPS.
4. **Moderasi:** admin di Tab Tinjau UI-04; pending→in_review→verified/rejected dalam transaksi+audit. Tanpa web admin/chat/reassignment otomatis.

Lima layar utama Akun, Beranda, Peta, Lapor, Profil + Detail Bencana. Empat bottom-nav setelah setup; panel laporan/form/picker tidak menambah layar utama.

## 3. Kontrak final lintas dokumen

| Area | Keputusan terkunci |
|---|---|
| Schema/ID | `siaga`, tidak diekspos PostgREST; UUID seluruh PK, timestamptz,13 FK RESTRICT. JSONB hanya metadata/snapshot. |
| Auth | JWT HS256 allowlist, iss/aud/sub/expiry, role/active dari DB; TTL3600s, token memori, tanpa refresh. Logout client, token tetap valid hingga expiry. Register selalu citizen. |
| Koordinat/zona | Earth finite lat[-90,90], input lon[-180,180]→[-180,180); tanpa pembatas Indonesia agar fixture antimeridian/kutub valid. `zone_version`>0; perubahan nyata reset `alert_eligible_since`; PUT identik no-op. |
| Nama final | `is_simulated`; `priority_algo`; `priority_score` mentah; `priority_display` half-up string; `priority_reasons`; `since_sequence`+`cursor_user_id`. Tidak ada alias nama rancangan lama. |
| Source/category | BMKG_TEWS/earthquake, BMKG_NOWCAST/extreme_weather; CITIZEN hanya source DTO derived. Warga `earthquake\|flood\|eruption\|extreme_weather\|haze_other`. |
| Status/versi | disaster_events.status enum CAP, msg_type terpisah, lifecycle_status derived. Report pending1→in_review2→verified/rejected3; zona zone_version, event content_version. |
| TEWS | SHA256 literal TEWS + UTC fixed6 mikrodetik + lat/lon fixed6 half-up kanonik, tanpa nama file. Auto→terkini→dirasakan; null tidak menimpa valid; revisi key tanpa fuzzy merge. |
| Radius/skor | Haversine R6371.0088km, cutoff r+0.000001km, bbox konservatif. eq-priority-v1 <35 biasa/35..<65 perhatian/>=65 tinggi;74.25→74.3; missing→null. |
| Nowcast | cap-priority-v1 tanpa angka; semua polygon, boundary1e-9deg, outside minimum centroid/vertex berlabel perkiraan, bukan irisan eksak. Invalid geometri hanya Semua/Detail tanpa marker/alert lokasi. |
| CAP aktif | Actual, Alert/Update, effective<=now<expires, belum cancelled/superseded, interval/references lengkap. Effective absen pakai sent. Severity Unknown tetap eligible jika cocok/aktif; skor bukan syarat alert. |
| Sync | Interval300s, timeout15s/request, retry2/4s, deadline240s, lease300s per sumber. Partial/failed degraded; >15menit sejak sukses stale. Copy committed checkpoint/bootstrap/last_success; bootstrap awal traversal penuh tanpa alert histori. |
| Notifikasi SQL | Unique user/event/official_new dan user/sequence; first_seen>cutoff, source_time>=cutoff, preferensi/lokasi/waktu valid. Event+log+checkpoint atomik. Lock users lalu alert_zones, urut UUID user sampai commit. |
| Paging/peta | List20/max50 offset, ID tie-breaker; cap100 marker total+truncated, filter dahulu. Centroid CAP representatif, bukan pusat bahaya; polygon penuh hanya Detail. |
| Foto/retry | JPEG<=2MiB/body<=3MiB; client1024px/~75%; server input4096px/16MP, output1024/JPEG75 tanpa EXIF. client_request_id UUID+payload_hash server report-payload-v1;201 baru/200 replay/409 mismatch. Encoder dipin. |
| Media/cleanup | Privat, URL300s setelah otorisasi, local signature terikat objek/path/expiry/mode; bukan JWT query. Commit ambigu lookup key dahulu; reconciliation>24jam hanya DB sehat, bukan in-flight. |
| Moderasi | expected_version; admin non-self, keputusan hanya holder, reason10..500.409 versi/state,403 role/self/non-holder. Update+audit atomik, deferred trigger menolak audit hilang, audit immutable. |
| Cursor/SSE | Bearer header, id user_uuid:sequence; Last-Event-ID menang. Baseline eksplisit login: high-water dahulu, history, stream. Sync since_sequence batch20/max50; read_at bukan cursor; gap recovery tanpa silent skip. |
| Client lifecycle | Heartbeat20s/timeout45s; dua gagal→poll60/120/240/300s ±10%, probe5menit. Satu kanal, nol timer paused; resume catch-up. Login baru tanpa popup histori, replay inactive tidak alert aktif, tanpa janji push app mati. |
| SIMULASI | APP_MODE production_live/local_live/simulation explicit; DB/folder terpisah, tanpa auto-switch seed. Timestamp bisnis clock domain konsisten; JWT/URL/lease/rate-limit jam dinding. Badge/banner/popup SIMULASI. |

Stack tetap Flutter3.47.7/Dart3.13.5 Provider MVVM, go_router/http/geolocator/flutter_map+OSM/flutter_local_notifications; Python3.15.0/FastAPI0.163.0/Uvicorn0.54.0, SQLModel/SQLAlchemy/Pydanticv2/pydantic-settings/psycopg[binary]/httpx/python-multipart/pytest, Pillow/pwdlib[argon2]/PyJWT. PostgreSQL Supabase/Storage/Railway + localhost. Tanpa NoSQL/Firebase/dio/build_runner/GIS extension wajib.

## 4. Fakta diterima dan batas pembuktian

Hasil live feed/wheel **diberikan user pada16Nov**, tidak diuji ulang sesi ini: TEWS tidak punya ID numerik universal; DateTime UTC+Coordinates untuk identity, Potensi/Dirasakan/Shakemap opsional. RSS Nowcast mempunyai guid/link CAP namespace1.2, info Indonesia/areaDesc/multi-polygon; references tidak diasumsikan selalu ada. Pemeriksaan wheel Python3.15 `--only-binary=:all:` paket resmi termasuk Pillow/Argon2/PyJWT telah exit0 menurut user; paket belum bernomor dipin saat build dan diuji runtime.

Sesi ini mengeksekusi DDL pada **PostgreSQL18.6 lokal disposable**, bukan Supabase/PostgreSQL15 aktual. Fitur dipilih dari dokumentasi PostgreSQL15: [UUID core](https://www.postgresql.org/docs/15/functions-uuid.html), [constraints](https://www.postgresql.org/docs/15/ddl-constraints.html), [constraint triggers](https://www.postgresql.org/docs/15/sql-createtrigger.html). Tanpa ekstensi; SQL tests bukan bukti endpoint/Flutter sudah berjalan.

Gate implementasi tersisa: migrations/grants lingkungan target, fixture geometri/source/eligibility lengkap, runtime paket Python, upload/storage failure/EXIF via HTTP, SSE proxy/pooler Railway-Supabase, lifecycle Android, security/performance dan fallback end-to-end. Tidak perlu mengganti stack hanya karena belum diuji runtime.

## 5. ERD.sql — Lock Planning SELESAI

- [x] 12 tabel: users, alert_zones, disaster_events, event_areas, area_polygons, polygon_vertices, event_references, citizen_reports, report_verifications, notification_logs, sync_runs, media_cleanup_jobs.
- [x] PK/FK/UNIQUE/CHECK, coordinate/preset/enum/versi/sequence, counter user, partial unique active sync; index feed/map/moderasi/history/cleanup.
- [x] FK RESTRICT, trigger transisi+append-only+deferred audit; cross-table source/geometry/eligibility eksplisit service, tanpa CHECK subquery ilegal.
- [x] Notes transaksi/idempotensi/lease/fallback; seed terpisah, tidak ada kredensial/event produksi buatan.
- [x] Apply bersih dan uji SQL lokal, hasil bagian9.

Antigravity membuat migration dari DDL; ORM jangan menyimpang. Owner migrasi terpisah dari runtime non-owner tanpa CREATE/DELETE/TRUNCATE. Audit SELECT/INSERT saja; log UPDATE(read_at) saja. Ingestion role boleh mengganti anak geometri/reference dalam transaksi, tanpa menghapus core. Schema siaga tidak terbuka untuk anon/authenticated Supabase; periksa trigger/grants setelah restore.

## 6. API_CONTRACT.md — Lock Planning SELESAI

Seluruh path final berprefix `/api/v1`. DTO/contoh/error ada di [kontrak](API_CONTRACT.md). Mark-read dan media lokal mewujudkan kebutuhan lama, bukan perluasan scope.

| Kelompok | Metode/path final |
|---|---|
| Auth | POST /api/v1/auth/register; POST /api/v1/auth/login; GET /api/v1/me |
| Zona | GET /api/v1/me/zone; PUT /api/v1/me/zone |
| Resmi | GET /api/v1/events; GET /api/v1/events/{event_id} |
| Peta | GET /api/v1/map/markers |
| Warga | POST /api/v1/reports; GET /api/v1/reports; GET /api/v1/reports/{report_id} |
| Media | GET /api/v1/reports/{report_id}/photo-url; GET /api/v1/media/reports/{report_id}/photo (local signed route) |
| Moderasi | POST /api/v1/reports/{report_id}/claim; POST /api/v1/reports/{report_id}/decision; GET /api/v1/reports/{report_id}/verifications |
| Notifikasi | GET /api/v1/me/notifications; POST /api/v1/me/notifications/{notification_id}/read; GET /api/v1/me/notifications/sync; GET /api/v1/me/notifications/stream |
| Operasional | GET /api/v1/health; GET /api/v1/ready |

- [x] Header/TTL/auth401vs403vs404, signed photo capability, tanpa JWT query SSE.
- [x] Tipe/null/unit/enum/ownership/SQL effects/idempotensi/paging dan envelope400/401/403/404/409/413/415/422/429/503 (+500 tak terduga).
- [x] priority_score/algo/reasons, lifecycle CAP, is_simulated dan DTO publik/privat.
- [x] Multipart/sanitizer/hash deterministik201/200/409, commit ambigu, expected_version dan rollback audit.
- [x] Baseline/high-water/cursor user binding, framing/replay/dedup/gap recovery/read_at/expiry.
- [x] AC-01..24 dipetakan ke endpoint/worker/gate API bagian12; JSON/SSE data tervalidasi.

## 7. UI_SPEC.md — Lock Planning SELESAI

- [x] Tepat UI-01..06: AccountScreen/HomeScreen/MapScreen/ReportsScreen/ProfileScreen/EventDetailScreen; route/ViewModel final.
- [x] ASCII Material3, bottom-nav empat, steps auth/zone, mode picker pada peta sama, panel laporan inline, Tinjau admin.
- [x] Matriks per layar: loading/empty/error/offline/degraded/stale/SIMULASI/409/tile-offline/permission-denied/token-expired; relevansi dijelaskan.
- [x] Wiring action ke endpoint/DTO, batas paging/marker/foto, retry idempoten/refetch409/privasi.
- [x] Checklist48dp/360px/font200%/fokus/semantics, indikator ikon+teks dan batas Radar/notifikasi.
- [x] Visual FigCraft lengkap [siaga-bencana-v1.figcraft](wireframes/siaga-bencana-v1.figcraft) (Page 1 Low-Fi `20` frame + Page 2 Palet `19` style, Hi-Fi `23` frame, `2` flow / `205` interaksi prototype) + `45` PNG ([overview.png](wireframes/png/overview.png), [overview-hifi.png](wireframes/png/overview-hifi.png), `UI-01..06`, `STATE-*`, `hifi/*`) selesai tanpa menambah layar/fitur baru.

## 8. Kelanjutan Antigravity — mulai Slice 1

**Selasa17Nov: Foundation, Auth, & DB Migration.** Baca skill relevan yang tersedia menurut AGENTS.md. Daftar skill Antigravity bukan klaim seluruhnya tersedia bagi Codex. Antigravity mengelola seluruh Git/GitHub.

1. Fondasi backend/mobile sesuai stack; pin dependency kompatibel, env.example tanpa rahasia, mode eksplisit. Jangan commit .env/token/password.
2. Migration ERD pada PostgreSQL lokal terisolasi lalu target; SQLModel schema siaga, role/grants owner terpisah, DTO Pydantic terpisah ORM.
3. Foundation auth Argon2/JWT register/login/me, role guard, envelope/request_id/throttle; health/ready. Register tidak menerima role.
4. Skeleton Flutter Provider/http/Bearer/DTO manual/go_router, lima layar+Detail dan guard; smoke health/auth. Finalisasi integrasi akun/zona18Nov.
5. Uji migration/grants/auth nyata. Temuan yang mengubah kontrak wajib menyelaraskan dokumen terkait dan handoff; layar skeleton bukan klaim fitur selesai.

| Tanggal | Slice dan gate |
|---|---|
| 17 Nov | **SELESAI:** Foundation, Auth, & DB Migration + mobile skeleton; 87 pytest + 12 widget + 1 live HTTP smoke lulus ([SLICE1_VERIFICATION.md](SLICE1_VERIFICATION.md)). |
| 18 Nov | **SELESAI:** Akun/zona UI+API (`GET/PUT /api/v1/me/zone`, `UI-01c`, `UI-03` `pick_zone`, `UI-05` edit zona); 159 pytest + 23 widget + 1 live HTTP smoke lulus. |
| 19–21 Nov | **19 Nov (Slice 3A SELESAI):** TEWS+Nowcast/radar/lease/notification-log worker + `/events`, `/events/{id}`, `/map/markers` (`406 pytest` + `EXPLAIN` + `1 live smoke` lulus); lanjut **20–21 Nov** UI feed/peta/detail. |
| 22–23 Nov | Laporan/foto/idempotensi/privasi, moderasi/audit/concurrency, UI Tinjau. |
| 24 Nov | SSE/poll/catch-up/OS notification/uji perangkat/SIMULASI; **feature freeze malam24Nov**. |
| 25–27 Nov | QA25, security+deploy/fallback26, smoke final+target tag v1.0.0 pada27Nov. |
| Mulai28Nov | Video>=10menit; artikel<=11–12halaman. |

Tiap slice berjalan secara **micro-batch terpisah** (`Backend` dan `Mobile` tidak digabung): **Codex** (`medium` default, `high` hanya di titik kritis `3A-1`/`4A`/`5`) menulis modul kode tanpa menjalankan `flutter.bat`/`.tooling/`/`git`; **Antigravity (`Orchestrator (Neon)`)** menangani `context7`/`pub add`, seluruh pengujian berat (`pytest`, `flutter analyze/test`, `smoke_live`, HP Android), perbaikan minor, serta commit/push; **`Opus 5.5 (Medium)`** opsional untuk poles UI/mentok >30m. Maritim tetap pasca-UAS.

## 9. Pemeriksaan kualitas sesi Lock Planning

- **DDL:** apply stop-on-error berhasil sampai COMMIT pada PostgreSQL18.6 kosong;12 tabel,13 FK seluruhnya RESTRICT; tanpa ekstensi GIS atau seed produksi.
- **SQL:** 60 pemeriksaan lulus, termasuk enum/range/NaN/Infinity/UNIQUE/RESTRICT, audit append-only, larangan skip/final/self-review, rollback transisi tanpa audit, partial unique lease, enum CAP/expiry, bbox/vertex dan metadata foto all-or-none. Dua koneksi admin menghasilkan tepat satu klaim/audit. Dua writer counter membuktikan writer kedua menunggu commit pertama dan reader tidak melihat increment belum commit.
- **API:** 33 blok JSON di-parse strict, termasuk duplicate key/NaN;3 JSON data SSE valid; tidak ada trailing comma/syntax invalid.22 metode/path unik dan wiring UI mengacu kontrak.
- **Konsistensi:** nama final/enum/status/versi/mode/cursor diselaraskan PRD–arsitektur–DDL–API–UI–handoff; scope lima layar+Detail, lima kategori, radius25/50/100, list20/max50, marker100, hash/cutoff/visibility/clocks ditinjau silang. AC tetap24; belum seluruh AC aplikasi dijalankan.
- **Aritmetika:**74.25→74.3 half-up, jarak antimeridian≈22.239016km termasuk radius25.
- **Dokumen:** UTF-8, fence berpasangan dan tautan file lokal valid. Tujuh Mermaid dipertahankan (empat flowchart, dua sequenceDiagram, satu stateDiagram-v2); tidak mengklaim render visual baru. ASCII/state/a11y adalah spesifikasi, bukan hasil tes perangkat.

Direktori validasi sementara Codex (`docs/.planning-validation`) telah dibersihkan oleh Antigravity sebelum commit dokumentasi sehingga tidak masuk ke repository; server PostgreSQL sementaranya sudah berhenti dan tidak ada database produksi dipakai. Validasi ulang mandiri oleh Antigravity (apply `ERD.sql` pada PostgreSQL 18.6 lokal sementara di temp dir, 33 blok JSON, 3 SSE JSON, 22 endpoint, 6 layar, 24 AC, 40 tabel Markdown, dan 64 tautan/anchor lokal) juga lulus sebelum commit.

PostgreSQL15/Supabase aktual, runtime Python aplikasi, API HTTP, Flutter, Railway, keamanan operasional dan benchmark belum diuji sesi ini.
