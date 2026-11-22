# AGENTS.md — Siaga Bencana (Project Rules & Dual-Agent Guide)

Dokumen ini adalah acuan bersama untuk **Codex (`gpt-6.2-astra`)** dan **Antigravity** di repository proyek UAS mata kuliah **Pemrograman Aplikasi Bergerak** (Semester 5).

---

## 1. Aturan Wajib Proyek (Non-Negotiable)

1. **Aplikasi Lengkap:** Wajib mencakup **Frontend + Backend REST API + Database**.
2. **Frontend Wajib Flutter:** Dibangun dengan **Flutter (`3.47.7` / Dart `3.13.5`)** di folder `mobile/`.
3. **Database Wajib Relasional (SQL):** Menggunakan **PostgreSQL (Supabase)**. **DILARANG keras memakai NoSQL** (seperti Firestore atau MongoDB) sebagai database aplikasi. Wajib ada struktur tabel relasional (`Primary Key`, `Foreign Key`, `Index`).
4. **Backend REST API Terpisah:** Dibangun dengan **Python FastAPI (`0.163.0` / Python `3.15`)** di folder `backend/`. Flutter **tidak boleh** mengakses tabel Supabase langsung untuk logika bisnis utama—semua alur data, sinkronisasi BMKG, kalkulasi radius lokasi, upload/validasi laporan warga, dan trigger notifikasi harus melewati Backend REST API FastAPI.
5. **Karya Sendiri & Unik:** Tidak boleh copy-paste proyek orang lain; harus memiliki pembeda/fitur unggulan yang jelas.
6. **Perkembangan Repo GitHub dari Awal:** Commit harus berjalan bertahap sejak Minggu 13 (mulai 15 Nov 2026) hingga rampung pada **26 Nov 2026** (freeze **23 Nov**), jauh sebelum UAS Minggu 16.

---

## 2. Tech Stack Resmi

* **Mobile Frontend (`mobile/`):**
  * **Flutter (`3.47.7`)**, **Dart (`3.13.5`)**
  * State Management: **`Provider` / `ChangeNotifier` (MVVM)** *(tanpa `build_runner` codegen agar kompilasi cepat dan aplikasi tetap ringan)*
  * Routing: `go_router`
  * Peta: `flutter_map` + OpenStreetMap *(dipilih agar 100% gratis dan jauh lebih ringan dibanding native Google Maps SDK; batasi marker aktif & gunakan filter radius agar peta tetap mulus)*
  * Lokasi & HTTP: `geolocator`, **`http`** *(dipilih menggantikan `dio` agar dependency minimal dan selaras dengan skill `flutter-use-http-package`)*
  * Notifikasi (Tanpa Firebase SDK): **`flutter_local_notifications` + SSE (`StreamingResponse` FastAPI) / smart polling hemat baterai** *(tanpa `firebase_core` atau `firebase_messaging` agar ukuran APK kecil, build Gradle cepat, dan 100% bebas ekosistem Firebase)*
  * Media Upload: kompresi gambar laporan warga di sisi client sebelum dikirim (resolusi maks ~`1024px`, kualitas JPEG ~`75%`)
* **Backend REST API (`backend/`):**
  * **Python `3.15.0`**, **FastAPI (`0.163.0`)**, **Uvicorn (`0.54.0`)**
  * ORM & Validasi: `SQLModel`, `SQLAlchemy`, `Pydantic v2`, `pydantic-settings`
  * Driver PostgreSQL: **`psycopg[binary]`** *(satu driver stabil untuk sync/async pada Python 3.15 & Railway -> Supabase tanpa isu PgBouncer `statement_cache_size`)*
  * HTTP Client, SSE & Upload: `httpx` (fetch & sinkronisasi Open Data BMKG ke PostgreSQL), `StreamingResponse` (real-time alert stream SSE), `python-multipart` (validasi tipe & batas ukuran file upload)
  * Testing: `pytest`
  * *(Catatan Python 3.15: gunakan paket yang sudah memiliki prebuilt wheel `cp315`; hindari library C-extension GIS berat seperti `geopandas`/`shapely`—gunakan perhitungan rumus Haversine di Python/SQL atau fungsi PostgreSQL.)*
* **Database & Storage:**
  * **PostgreSQL di Supabase** (skema relasional kuat dengan PK, FK, Index, dan constraint: misalnya `users`, `disaster_events`, `citizen_reports`, `report_verifications`, `alert_zones`, `notification_logs`).
  * **Supabase Storage** untuk menyimpan file foto laporan warga terkompresi (URL metadata tetap tersimpan di tabel PostgreSQL).
  * *(Catatan teknis Railway -> Supabase: gunakan Supabase Connection Pooler URL jika dibutuhkan di lingkungan IPv4/Railway.)*
* **Hosting & Fallback Lokal:**
  * Backend FastAPI di-deploy ke **Railway** (termasuk scheduler penarik data BMKG berkala).
  * Proyek **WAJIB** tetap mudah dijalankan 100% di **`localhost`** melalui `.env` sebagai cadangan saat demo UAS jika kuota trial Railway habis.

---

## 3. Pembagian Tugas AI & Aturan Kolaborasi

### A. Codex (`gpt-6.2-astra`) — Planning (`docs/`) & Coding Micro-Batch Terisolasi
* **Tugas Codex:**
  1. **Planning & Kontrak (`docs/`, SELESAI):** `IDEA.md`, `PRD.md`, `ARCHITECTURE.md`, `ERD.sql`, `API_CONTRACT.md`, `UI_SPEC.md`, `HANDOFF.md`, serta wireframe FigCraft.
  2. **Implementasi Kode (`Slice 1–5`, per micro-batch terpisah):** menulis modul kode backend (`backend/app/`, `backend/tests/`) atau file Dart frontend (`mobile/lib/`, `mobile/test/`) sesuai kontrak terkunci.
* **Aturan Keras & Hemat Kuota untuk Codex:**
  * **DILARANG jalankan `git init`, `git commit`, `git push`, atau mengubah remote GitHub.** Seluruh urusan Git & GitHub ditangani oleh Antigravity.
  * **Pecah per sub-batch kecil:** Backend & Mobile **tidak boleh** digabung dalam satu eksekusi Codex; slice backend berat (`Slice 3A`, `4A`, `5`) dipecah `2–3` micro-batch terpisah.
  * **DILARANG menyalin SDK `.tooling/` atau menjalankan `flutter` CLI (`flutter.bat`) di sandbox Windows:** untuk Mobile, Codex cukup menulis/mengubah file `.dart` lalu berhenti agar Antigravity yang menjalankan `flutter pub/analyze/test` di sistem normal.
  * **Effort (`gpt-6.2-astra`):** gunakan **`medium` sebagai default** (`3A-2/3` worker & endpoint, `3B`, `3C`, `4A-1` upload/Pillow, `4B`, `5-3` mobile UI, fix QA, draf pasca-rilis); gunakan **`high` secara selektif** hanya pada titik kritis logika/konkurensi/streaming (`3A-1` geometri CAP/antimeridian/Haversine/skor, `4A-2` idempotensi & transaksi moderasi `409`, `5-1`/`5-2` counter lock, cursor & SSE stream); hindari `low` maupun `xhigh`/`ultra`/`max`.
  * Baca hanya section dokumen `docs/` yang relevan dengan micro-batch yang sedang dikerjakan.

### B. Antigravity — Orkestrasi, Pengujian Berat (`Orchestrator (Neon)` / fallback `Gemini 4 Argon`), Spesialis UI Opsional (`Orchestrator (Opus 5.5)`), QA & Git
* **Tugas Antigravity (`Orchestrator (Neon)` sebagai orkestrator & penguji harian, otomatis beralih ke `Gemini 4 Argon` bila terkena limit — menggantikan full `Gemini 4 Hydrogen`):**
  1. **Persiapan & Riset:** menjaga plugin/MCP tetap minimal per hari (lihat `docs/SCHEDULE.md`), mengecek API library baru via `context7` / `flutter pub`, serta selalu menyertakan ringkasan konteks skill yang relevan ke dalam prompt sebelum mendelegasikan penulisan kode ke Codex.
  2. **Pengujian Berat, Perbaikan Cepat & Verifikasi Nyata:** menjalankan `local_pg.py`, migrasi PostgreSQL, full `pytest`, `smoke_live.py`, `flutter pub get/analyze/test`, dan uji emulator/HP Android; error minor/lint langsung diperbaiki **Orchestrator (Neon)** (atau **`Gemini 4 Argon`** saat fallback limit) sendiri tanpa membebani kuota Codex.
  3. **Git, QA, Audit & Deploy:** mengelola repo GitHub (`4jeeh/siaga-bencana` via `gh` CLI), commit bertahap (**1–3 commit terfokus per hari**), `git push`, sinkronisasi `HANDOFF.md`/`SCHEDULE.md`, QA Testing, Security Audit, dan Deploy ke Railway.
* **Peran Spesialis `Orchestrator (Opus 5.5)` (opsional & hemat kuota):**
  * Dipanggil selektif untuk **poles visual UI Flutter secara menyeluruh setelah seluruh fitur selesai** menjelang demo, **cadangan saat bug lintas-lapisan mentok >30 menit**, atau **review bahasa artikel pasca-rilis** — **bukan** untuk CRUD/backend atau suite test rutin.
* **Daftar Skills & MCP Antigravity yang Digunakan Proyek Ini:**
  * *Planning & GitHub Workflow:* `superpowers` *(opsional)*, `coderabbit`, `codegraph` (MCP), `context7` (MCP), `keenable` *(nonaktif saat coding)*.
  * *Design & UI/UX Flutter:* `ui-ux-pro-max` (stack `flutter`), `impeccable`, `logo-design`, `generative-icons` (MCP), `figcraft` (MCP, menggantikan Figma untuk wireframe), `google_maps_platform` *(opsional jika kelak beralih ke Google Maps SDK)*.
  * *Flutter Build, Bugfix & Testing:* Plugin `flutter` (`dart-mcp-server`, `flutter-apply-architecture-best-practices`, `flutter-setup-declarative-routing`, `flutter-build-responsive-layout`, `flutter-use-http-package`, `flutter-implement-json-serialization`, `flutter-fix-layout-issues`, `dart-fix-runtime-errors`, `dart-run-static-analysis`, `dart-add-unit-test`, `flutter-add-widget-test`, `flutter-add-integration-test`, `flutter_a11y_agent`), `android-cli-plugin` (`device-hub`), `e2e`.
  * *Backend FastAPI, PostgreSQL & Deploy:* `fastapi`, `python-testing-patterns`, `supabase` (`supabase_mcp`), `supabase-postgres-best-practices`, `postgresql-code-review`, `postgresql-optimization`, `postman` (`Hari 10 QA` saja), `use-railway` (`railway_mcp`), `security-audit`, `humanizer`.
  * *(Catatan Antigravity: aktifkan **hanya** plugin/MCP yang dipakai hari itu sesuai `docs/SCHEDULE.md` dan baca hanya `2–3` file `SKILL.md` yang relevan agar baseline prompt selalu ringan.)*

---

## 4. Prinsip Ringan-Kompleks & Batasan Anti-Bablas

1. **Ringan di Client, Kompleks di Backend & SQL (Wajib):**
   * **Mobile (Tipis & Mulus):** gunakan Material 3 bawaan tanpa library UI/animasi 3D berat; terapkan pagination (`limit`/`offset`) dan payload JSON ringkas agar hemat RAM/kuota di HP spek menengah.
   * **Backend & DB (Berbobot UAS):** fokuskan kompleksitas pada kedalaman skema relasional PostgreSQL, cache sinkronisasi BMKG di database (backend tidak menembak API BMKG di setiap request user), kalkulasi radius *Haversine* + skor level bahaya di server, alur verifikasi laporan warga bertahap, serta real-time alert stream SSE.
2. **Maksimal 5 Layar Utama (+ Detail):** Login/Set Radius, Beranda & Feed Bencana, Peta Interaktif, Form/Feed Lapor Warga, Profil/Riwayat Notifikasi + Halaman Detail Bencana.
3. **Maksimal 1–2 Fitur Pembeda Unik:** Fokus membuat fitur utama sangat solid ketimbang menambah banyak fitur setengah jadi.
4. **Tanpa Web Admin Terpisah / Live Chat:** Jika butuh moderasi laporan, gunakan role/tab Admin di aplikasi Flutter yang sama atau Swagger `/docs` FastAPI.
5. **Milestone Deadline (Internal Guardrail):**
   * **Hari 1–2 (15–16 Nov 2026):** Planning & Dokumen (`docs/`) — **Lock Planning di akhir 16 Nov**.
   * **Hari 3–9 (17–23 Nov 2026):** Coding iteratif per slice (termasuk Double Slice `4A`+`4B` pada `22 Nov`) — **Feature Freeze mutlak di 23 Nov**.
   * **Hari 10–12 (24–26 Nov 2026):** QA/Testing, `security-audit`, Deploy Railway & fallback lokal, tag rilis `v1.0.0` pada **26 Nov 2026**.
   * **27 Nov – UAS (Minggu 16):** Video demo min. 10 menit (YouTube) + Artikel maks. 11–12 halaman.
6. **Keamanan Repo:** DILARANG keras commit `.env`, API key, token, atau password database ke GitHub.
