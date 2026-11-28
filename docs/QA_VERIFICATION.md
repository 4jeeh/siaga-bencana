# Verifikasi QA, Aksesibilitas & NFR (Hari 11 — 28 November 2026)

**Author:** Jiddan Ibnu Ali (`24051214203`)  
**Cakupan:** Seluruh modul backend (`backend/`), aplikasi Flutter (`mobile/`), audit aksesibilitas (`flutter_a11y_agent`), uji kontrak HTTP & offline `SIMULASI`, pengukuran NFR terukur, dan walkthrough langsung pada perangkat Android fisik.

---

## 1. Ringkasan Suite Otomatis

| Pemeriksaan | Perintah / Alat | Hasil Terobservasi |
|---|---|---|
| Lint Backend | `ruff check backend/` | **Lolos** (`All checks passed!`) |
| Backend Test Suite | `pytest backend/tests` (PostgreSQL terisolasi) | **537 passed** (unit, SQL constraint/trigger, radar/CAP, moderasi konkurensi, SSE, enhancement `C2/C3/C5/C6`) |
| Analisis Statis Mobile | `flutter analyze` | **Lolos** (`No issues found!`) |
| Mobile Unit/Widget/A11y Test | `flutter test` | **116 passed** (termasuk `meetsGuideline` untuk tap target, label, dan kontras teks pada layar utama) |
| Live HTTP Smoke | `python backend/scripts/smoke_live.py` (`live_smoke.dart`) | **1 passed** (Flutter HTTP -> Uvicorn -> PostgreSQL round trip) |

---

## 2. Temuan Audit Aksesibilitas (`flutter_a11y_agent`) & Perbaikan Hari 11

Audit terhadap 14 berkas UI Flutter (`WCAG 2.1 AA` & `NFR-09`) menemukan dan langsung memperbaiki temuan berikut tanpa mengubah fitur atau palet warna terkunci:

1. **Kontras teks peringatan (High → Selesai):** Pada [status_banners.dart](../mobile/lib/core/widgets/status_banners.dart) (`FreshnessBanner`) dan [ui_kit.dart](../mobile/lib/core/widgets/ui_kit.dart) (`StatusPill`), teks kecil di atas tint amber (`AppColors.warning` `#B45309` pada `#F8FAFC`/`#FFFFFF` ~`4.33–4.39:1`) kini memakai `AppColors.textPrimary` (`#0F172A`, kontras tinggi) sembari mempertahankan ikon dan garis tepi warna `AppColors.warning`.
2. **Semantics cuaca Hero Card (Medium → Selesai):** Memisahkan node `Semantics` pada ringkasan cuaca [home_screen.dart](../mobile/lib/features/home/home_screen.dart) (`excludeSemantics: true`) agar pembaca layar tidak membacakan metrik `MetricStrip` secara ganda.
3. **Kliping notice Peta saat font 200% (Medium → Selesai):** Menyesuaikan tinggi maksimum area notice + membungkusnya dengan `Scrollbar(thumbVisibility: true)` di [map_screen.dart](../mobile/lib/features/map/map_screen.dart).
4. **Pengumuman error dinamis (Medium → Selesai):** Menambahkan `Semantics(liveRegion: true)` pada notice dinamis di [location_search_field.dart](../mobile/lib/features/zone/location_search_field.dart), [map_screen.dart](../mobile/lib/features/map/map_screen.dart), [report_panel.dart](../mobile/lib/features/reports/report_panel.dart), [event_detail_screen.dart](../mobile/lib/features/event_detail/event_detail_screen.dart), dan [profile_screen.dart](../mobile/lib/features/profile/profile_screen.dart).
5. **Skala tinggi `NavigationBar` & heading/aksi (Medium → Selesai):** Menyesuaikan tinggi `NavigationBar` (`80 -> 96` saat skala teks besar) + `tooltip` di [app_router.dart](../mobile/lib/core/routing/app_router.dart), menambahkan `Semantics(header: true)` di judul utama/sheet ([account_screen.dart](../mobile/lib/features/auth/account_screen.dart), [zone_form.dart](../mobile/lib/features/zone/zone_form.dart), [report_form.dart](../mobile/lib/features/reports/report_form.dart), [report_panel.dart](../mobile/lib/features/reports/report_panel.dart)), serta memberi label kontekstual pada tombol `Lihat` di [reports_screen.dart](../mobile/lib/features/reports/reports_screen.dart) dan [event_detail_screen.dart](../mobile/lib/features/event_detail/event_detail_screen.dart).
6. **Uji `meetsGuideline` otomatis (Medium → Selesai):** Menambahkan pengujian `androidTapTargetGuideline`, `labeledTapTargetGuideline`, dan `textContrastGuideline` di [enhancements_test.dart](../mobile/test/enhancements_test.dart).

---

## 3. Pengukuran Non-Functional Requirements (`NFR-01..10`)

Catatan lingkungan pengukuran: Windows 11 lokal, PostgreSQL 18.6 (`127.0.0.1:54329`), satu proses Uvicorn lokal, dan perangkat fisik Android 13 (`CPH2145` / `42bdf1f7`, 88 event di `siaga_dev`).

| ID | Target [PRD](PRD.md) | Hasil Pengukuran Nyata | Status |
|---|---|---|---|
| **NFR-01** | `p95 <= 500 ms` pada 20 req konkuren; catat query count & EXPLAIN bila gagal | **Per request sekuensial:** `/events` `91.6 ms` (`eval 8.6 ms` + `feed 83.0 ms`, `7` query SQL), `/map/markers` `129.2 ms` (`8` query SQL); `EXPLAIN ANALYZE` query kandidat `0.257 ms` (`shared hit=23`). **20 req konkuren (1 worker Uvicorn + `pool_size=5, max_overflow=0`):** `/events` `p50=961.2 ms, p95=1944.3 ms`, `/map/markers` `p50=1160.1 ms, p95=2123.4 ms` (terjadi antrean koneksi sengaja karena batas pool `5` untuk kompatibilitas pooler Supabase; `/health` tanpa DB `p95=25.0 ms`). | **Tercatat & dijelaskan** |
| **NFR-02** | `/events` `<= 100 KiB`, `/map/markers` `<= 150 KiB`, tanpa polygon/audit/base64 | `/events` (20 item) = **`27.09 KiB`**; `/map/markers` (30 marker) = **`11.95 KiB`**. Scan JSON mengonfirmasi nol `vertices`, `data:image/`, `password_hash`, dan nol field privat pada `ReportPublic` non-pemilik. | **Lulus** |
| **NFR-03** | Responsivitas render & lazy media | Verifikasi interaksi nyata pada `CPH2145`: Impeller aktif, feed/peta responsif, foto dimuat lazy lewat signed URL, nol `RenderFlex overflow` maupun frame drop fatal di `logcat`. *(Profiling 60-detik DevTools frame-time formal tidak dijalankan terpisah.)* | **Terverifikasi fungsional** |
| **NFR-04** | APK arm64 release `<= 40 MiB` | `flutter build apk --release --split-per-abi`: `app-arm64-v8a-release.apk` = **`20.4 MB`** (`armeabi-v7a` `18.4 MB`, `x86_64` `21.8 MB`). *(Peak RSS tidak diukur dengan profiler memori terpisah.)* | **Lulus (`20.4 MB`)** |
| **NFR-05** | SSE live + fallback polling | Diuji di `backend/tests/test_notifications_stream.py`, `mobile/test/notifications_profile_test.dart`, dan HP nyata (`Status kanal: Notifikasi Real-Time Aktif`). | **Lulus** |
| **NFR-06** | Satu SSE aktif & nol timer saat paused | Diuji di `mobile/test/notifications_profile_test.dart` (`didChangeAppLifecycleState` & single active SSE registry). | **Lulus** |
| **NFR-07** | Idempotensi & konkurensi di PostgreSQL asli | Diuji pada PostgreSQL nyata lewat `pytest`: double claim `409`, idempotent upload replay `200`/`409`, dan atomic notification counter locks. | **Lulus** |
| **NFR-08** | Privasi, auth, XML/foto hardening | Diuji di `pytest` (`test_api.py`, `test_reports_api.py`, `test_bmkg_sync.py`) + verifikasi live `401`/`403`/`422` + verifikasi `ReportPublic` non-pemilik di DB simulasi terisolasi. Audit keamanan lengkap dijadwalkan di Hari 12. | **Lulus QA awal** |
| **NFR-09** | Bahasa Indonesia, `360px`, `200%` text, `48dp`, a11y | Audit `flutter_a11y_agent`, 6 perbaikan kontras/semantics/scrollbar, serta uji widget `360px / 200%` + `meetsGuideline` lulus (`116/116`). | **Lulus** |
| **NFR-10** | Start `Local SIMULASI` `<= 10 menit` tanpa internet | Uji E2E DB `siaga_qa_*_simulation` terisolasi (`APP_MODE=simulation`, `BMKG_SYNC_ENABLED=false`) dari migrasi → registrasi → zona → gempa → pencarian `LOCAL_FALLBACK` → weather `null` → lapor warga → moderasi `verified` → sync selesai dalam **`1.18 detik`**. | **Lulus (`1.18 s`)** |

---

## 4. Matriks Keterlusuran `AC-01..24`

Seluruh 24 Acceptance Criteria ([PRD.md](PRD.md)) telah memiliki cakupan pengujian otomatis dan/atau verifikasi live:

- **`AC-01`–`AC-03` (Auth, role guard, validasi zona & koordinat):** `backend/tests/test_api.py`, `test_zones_api.py` (`401`/`403`/`422`), `mobile/test/widget_test.dart`, plus verifikasi HTTP live (`401` guest, `403` citizen claim, `422` query invalid).
- **`AC-04`–`AC-07` (Haversine, antimeridian, skor `S=60P+25M+15T`, TEWS merge):** `backend/tests/test_radar.py`, `test_bmkg_sync.py`, `test_events_map.py`.
- **`AC-08`–`AC-11` (Nowcast multi-polygon, antimeridian CAP, lifecycle, XML hardening & source failure isolation):** `backend/tests/test_radar.py`, `test_bmkg_sync.py`, `test_events_map.py`, `test_report_media.py`.
- **`AC-12`–`AC-13` (Preferensi notif, pagination, marker cap `100` & client dedup):** `backend/tests/test_notifications_stream.py`, `test_events_map.py`, `mobile/test/events_feed_test.dart`, `mobile/test/map_browse_test.dart`.
- **`AC-14`–`AC-18` (Validasi foto JPEG/Pillow, idempotensi `report-payload-v1`, cleanup, privasi `ReportPublic`, klaim konkurensi & audit immutability):** `backend/tests/test_reports_api.py`, `test_report_media.py`, `mobile/test/reports_test.dart`, + uji `ReportPublic` di QA simulasi.
- **`AC-19`–`AC-21` (Cursor sequence per-user, SSE replay/backoff/lifecycle paused-resumed, rollback transaksi):** `backend/tests/test_notifications_stream.py`, `backend/tests/test_bmkg_sync.py`, `mobile/test/notifications_profile_test.dart`.
- **`AC-22`–`AC-24` (Offline `Local SIMULASI`, izin notif ditolak/app killed, logout/URL expired/rate limit `429`):** E2E `Local SIMULASI` (`1.18 detik`), `backend/tests/test_api.py`, `test_reports_api.py`, `mobile/test/enhancements_test.dart`.

---

## 5. Uji Perangkat Android Fisik (`CPH2145` / `42bdf1f7`)

- **Transport & App Startup:** `adb reverse tcp:8000 tcp:8000`, instalasi APK debug terbaru pasca-perbaikan a11y (`47.8s`), auto-restore sesi terenkripsi (`flutter_secure_storage`) dari cold start berjalan lancar ke Beranda.
- **Layar Terverifikasi Secara Visual & Interaktif:**
  - `UI-02` Beranda: Hero Card `#0F4C5C`, cuaca saat ini (`Open-Meteo`), strip 3 metrik, filter `Sekitar`/`Semua` & `Gempa`/`Cuaca Ekstrem`, kartu `AccentCard` dengan `Keparahan: Sedang` (`#0F172A` kontras tinggi).
  - `UI-03` Peta Interaktif: Tile OSM Surabaya–Madura–Pasuruan, radius `50 km`, filter 1 baris, pin warga `verified`, legenda.
  - `UI-04` Lapor Warga & Form: Kunjungan pertama langsung terisi tanpa error, Extended FAB `Tulis Laporan`, 5 ChoiceChip kategori, validasi input + peringatan privasi.
  - `UI-05` Profil: Info akun/zona, status kanal **`Notifikasi Real-Time Aktif`**, status izin `Diizinkan`, riwayat notifikasi.
  - `UI-06` Detail Bencana: Header kejadian, pill keparahan/prioritas, ikon pin lokasi sejajar, panel `Mengapa?`, dan atribut cuaca.
- **Pemeriksaan `adb logcat -s flutter`:** Nol `RenderFlex overflowed`, nol uncaught exception.
