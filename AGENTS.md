# AGENTS.md — Siaga Bencana (Project Rules & Dual-Agent Guide)

Dokumen ini adalah acuan bersama untuk **Codex (`gpt-6-astra`)** dan **Antigravity** di repository proyek UAS mata kuliah **Pemrograman Aplikasi Bergerak** (Semester 5).

---

## 1. Aturan Wajib Proyek (Non-Negotiable)

1. **Aplikasi Lengkap:** Wajib mencakup **Frontend + Backend REST API + Database**.
2. **Frontend Wajib Flutter:** Dibangun dengan **Flutter (`3.47.7` / Dart `3.13.5`)** di folder `mobile/`.
3. **Database Wajib Relasional (SQL):** Menggunakan **PostgreSQL (Supabase)**. **DILARANG keras memakai NoSQL** (seperti Firestore atau MongoDB) sebagai database aplikasi. Wajib ada struktur tabel relasional (`Primary Key`, `Foreign Key`, `Index`).
4. **Backend REST API Terpisah:** Dibangun dengan **Python FastAPI (`0.163.0` / Python `3.15`)** di folder `backend/`. Flutter **tidak boleh** mengakses tabel Supabase langsung untuk logika bisnis utama—semua alur data, sinkronisasi BMKG, kalkulasi radius lokasi, upload/validasi laporan warga, dan trigger notifikasi harus melewati Backend REST API FastAPI.
5. **Karya Sendiri & Unik:** Tidak boleh copy-paste proyek orang lain; harus memiliki pembeda/fitur unggulan yang jelas.
6. **Perkembangan Repo GitHub dari Awal:** Commit harus berjalan bertahap sejak Minggu 13 (mulai 15 Nov 2026) hingga rampung di akhir Minggu 14 / awal Minggu 15 (28 Nov – 02 Des 2026), jauh sebelum UAS Minggu 16.

---

## 2. Tech Stack Resmi

* **Mobile Frontend (`mobile/`):**
  * **Flutter (`3.47.7`)**, **Dart (`3.13.5`)**
  * State Management: `Riverpod` / `Provider`
  * Routing: `go_router`
  * Peta: `flutter_map` + OpenStreetMap *(dipilih agar 100% gratis tanpa billing Google Maps SDK, kecuali user memutuskan memakai Google Maps)*
  * Lokasi & HTTP: `geolocator`, `http` / `dio`
  * Notifikasi: `flutter_local_notifications` + polling REST API, atau `firebase_messaging` **khusus push delivery saja (tanpa Firestore NoSQL)**
* **Backend REST API (`backend/`):**
  * **Python `3.15.0`**, **FastAPI (`0.163.0`)**, **Uvicorn (`0.54.0`)**
  * ORM & Validasi: `SQLModel`, `SQLAlchemy`, `Pydantic v2`, `pydantic-settings`
  * Driver PostgreSQL: `psycopg[binary]` / `asyncpg`
  * HTTP Client & Upload: `httpx` (untuk fetch Open Data BMKG), `python-multipart`
  * Testing: `pytest`
  * *(Catatan Python 3.15: gunakan paket yang sudah memiliki prebuilt wheel `cp315`; hindari library C-extension GIS berat seperti `geopandas`/`shapely`—gunakan perhitungan rumus Haversine di Python/SQL atau fungsi PostgreSQL.)*
* **Database & Storage:**
  * **PostgreSQL di Supabase** (tabel relasional: misalnya `users`, `disaster_events`, `citizen_reports`, `alert_zones`, `notification_logs`, plus relasi FK yang jelas).
  * **Supabase Storage** untuk menyimpan file foto laporan warga (URL metadata tetap tersimpan di tabel PostgreSQL).
  * *(Catatan teknis Railway -> Supabase: gunakan Connection Pooler URL jika dibutuhkan dan perhatikan `statement_cache_size=0` bila memakai `asyncpg` dengan PgBouncer Transaction mode.)*
* **Hosting & Fallback Lokal:**
  * Backend FastAPI di-deploy ke **Railway** (termasuk scheduler penarik data BMKG berkala).
  * Proyek **WAJIB** tetap mudah dijalankan 100% di **`localhost`** melalui `.env` sebagai cadangan saat demo UAS jika kuota trial Railway habis.

---

## 3. Pembagian Tugas AI & Aturan Kolaborasi

### A. Codex (`gpt-6-astra`) — Planning, Brainstorming, PRD & Arsitektur (`docs/`)
* **Tugas Codex:**
  1. Brainstorming konsep & fitur pembeda unik -> tulis ke `docs/IDEA.md`
  2. Menyusun Product Requirements Document (PRD) -> `docs/PRD.md`
  3. Menggambar User Flowchart & System Architecture Diagram (Mermaid) -> `docs/ARCHITECTURE.md`
  4. Merancang skema DDL SQL Relasional lengkap -> `docs/ERD.sql`
  5. Mengunci kontrak REST API JSON (endpoint, request/response, status error) -> `docs/API_CONTRACT.md`
  6. Menulis ringkasan keputusan & tugas berikutnya setiap akhir sesi -> `docs/HANDOFF.md`
* **Aturan Keras untuk Codex:**
  * **JANGAN jalankan `git init`, `git commit`, `git push`, atau mengubah remote GitHub.** Seluruh urusan Git & GitHub ditangani oleh Antigravity.
  * Tulis seluruh keputusan langsung ke folder `docs/` agar bisa dibaca Antigravity tanpa copy-paste chat.
  * Gunakan reasoning effort secukupnya (`medium` atau `high` untuk efisiensi kuota; hindari `ultra`).

### B. Antigravity — GitHub, Coding, QA, Security Audit & Deploy
* **Tugas Antigravity:**
  1. Mengelola repo GitHub (`4jeeh/siaga-bencana` via `gh` CLI), review perubahan dari Codex, membuat branch/commit bertahap (1–3 commit terfokus per hari), dan `git push`.
  2. Membangun aplikasi secara **Vertical Slice** (*Database -> FastAPI -> Flutter -> Test -> Commit*), bukan membangun semua layar lalu menggabungkannya di akhir.
  3. Melakukan QA Testing, Code Review, Security Audit, dan Deploy ke Railway.
* **Daftar Skills & MCP Antigravity yang Digunakan Proyek Ini:**
  * *Planning & GitHub Workflow:* `superpowers` (`brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion`, `finishing-a-development-branch`), `coderabbit` (`code-review`, `autofix`), `codegraph` (MCP), `context7` (MCP), `keenable` (`keenable-web` MCP).
  * *Design & UI/UX Flutter:* `ui-ux-pro-max` (stack `flutter`), `impeccable`, `logo-design`, `generative-icons` (MCP), `figma` (`figma-spec`, `figma-generate-diagram`, `figma-generate-design`, `figma-design-to-code`), `google_maps_platform`.
  * *Flutter Build, Bugfix & Testing:* Plugin `flutter` (`dart-mcp-server`, `flutter-apply-architecture-best-practices`, `flutter-setup-declarative-routing`, `flutter-build-responsive-layout`, `flutter-use-http-package`, `flutter-implement-json-serialization`, `flutter-fix-layout-issues`, `dart-fix-runtime-errors`, `dart-run-static-analysis`, `dart-add-unit-test`, `flutter-add-widget-test`, `flutter-add-integration-test`, `flutter_a11y_agent`), `android-cli-plugin` (`device-hub`), `e2e`.
  * *Backend FastAPI, PostgreSQL & Deploy:* `fastapi`, `supabase` (`supabase_mcp`), `supabase-postgres-best-practices`, `postgresql-code-review`, `postgresql-optimization`, `postman` (`api-engineer`, `api-testing`, `api-mocking`, `api-documentation`), `use-railway` (`railway_mcp`), `security-audit`, `humanizer`.
  * *(Catatan Antigravity: karena sebagian skill berada di luar budget auto-load prompt saat banyak plugin menyala, baca file `SKILL.md` yang relevan secara eksplisit sebelum memulai setiap slice.)*

---

## 4. Batasan Ketat Anti-Bablas (Guardrails)

1. **Maksimal 5 Layar Utama (+ Detail):** Login/Set Radius, Beranda & Feed Bencana, Peta Interaktif, Form/Feed Lapor Warga, Profil/Riwayat Notifikasi + Halaman Detail Bencana.
2. **Maksimal 1–2 Fitur Pembeda Unik:** Fokus membuat fitur utama sangat solid ketimbang menambah banyak fitur setengah jadi.
3. **Tanpa Web Admin Terpisah / Live Chat:** Jika butuh moderasi laporan, gunakan role/tab Admin di aplikasi Flutter yang sama atau Swagger `/docs` FastAPI.
4. **Milestone Deadline:**
   * **Hari 1–3 (15–17 Nov 2026):** Planning & Dokumen (`docs/`) — **Lock Planning di akhir Hari 3**.
   * **Hari 4–14 (18–28 Nov 2026):** Coding iteratif per slice — **Feature Freeze mutlak di Hari 14**.
   * **Hari 15–18 (29 Nov – 02 Des 2026):** QA/Testing, `security-audit`, Deploy Railway, tag rilis `v1.0.0`.
   * **03 Des – UAS (Minggu 16):** Video demo min. 10 menit (YouTube) + Artikel maks. 11–12 halaman.
5. **Keamanan Repo:** DILARANG keras commit `.env`, API key, token, atau password database ke GitHub.
