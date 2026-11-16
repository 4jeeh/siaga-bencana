# Jadwal Proyek — Siaga Bencana

**Author:** Jiddan Ibnu Ali (`24051214203`)  
**Revisi Jadwal (Final):** 16 November 2026 — dimajukan menjadi **13 hari kalender (`15–27 Nov 2026`)** agar **finalisasi rilis `v1.0.0` tercapai pada Jumat, 27 November 2026**.

## Ringkasan Penyesuaian
* **Lock Planning (Dimajukan ke Hari Ini, `16 Nov`):** Karena `PRD.md` dan `ARCHITECTURE.md` selesai pagi hari `16 Nov`, penyusunan `ERD.sql`, `API_CONTRACT.md`, dan `UI_SPEC.md` (termasuk wireframe ASCII; visual FigCraft tindak lanjut terpisah) langsung dituntaskan dan dikunci pada **Senin, 16 November 2026**.
* **Fase Build (`17–24 Nov`, 8 hari penuh):** Seluruh Vertical Slice (Foundation -> Auth/Zona -> BMKG/Radar/Peta/Detail -> Lapor/Moderasi -> SSE/Notifikasi/Uji Perangkat) diselesaikan sebelum freeze.
* **Feature Freeze (`24 Nov`):** Mutlak pada **Selasa malam, 24 November 2026** — dilarang menambah fitur setelah tanggal ini. Fitur bonus **Maritim (`maritim.bmkg.go.id`)** resmi ditangguhkan ke pasca-UAS `v1.0.0`.
* **QA, Security, Deploy & Rilis (`25–27 Nov`, 3 hari):** QA & pengujian lengkap (`25 Nov`), Security Audit + Deploy Railway & verifikasi fallback `localhost`/`SIMULASI` (`26 Nov`), dan Smoke Test Final + tag rilis **`v1.0.0`** (`27 Nov`).
* **Pasca-rilis (`28 Nov – UAS`):** Video demo minimal 10 menit (YouTube) dan artikel maksimal 11–12 halaman.

---

## Jadwal Harian (15 – 27 November 2026 + UAS)

| Hari | Tanggal | Fase / Slice | Fokus & Deliverable Utama | Penanggung Jawab / Fokus Teknis | Status & Guardrail |
|---|---|---|---|---|---|
| **Hari 1** | Min, 15 Nov | Planning & Ide | Repo GitHub, [AGENTS.md](../AGENTS.md), form dosen, [IDEA.md](IDEA.md), kunci 4 keputusan | Codex + Antigravity | **SELESAI** (`280fe21`) |
| **Hari 2** | Sen, 16 Nov | **PRD, Arsitektur & LOCK PLANNING** | [PRD.md](PRD.md), [ARCHITECTURE.md](ARCHITECTURE.md), pembaruan [SCHEDULE.md](SCHEDULE.md), lalu **Lock Planning:** [ERD.sql](ERD.sql), [API_CONTRACT.md](API_CONTRACT.md), [UI_SPEC.md](UI_SPEC.md) + wireframe ASCII; visual FigCraft sesi berikutnya | Codex (dokumen teks/SQL); Antigravity (review dan implementasi) | **LOCK PLANNING SELESAI**; siap Slice 1 pada 17 Nov |
| **Hari 3** | Sel, 17 Nov | **Slice 1 — Foundation, Auth, & DB Migration** | Setup `backend/` + migrasi [ERD.sql](ERD.sql), fondasi JWT/Argon2 register/login/me, `/api/v1/health` dan `/api/v1/ready`; skeleton `mobile/` (`go_router` 5 layar + Detail) dan smoke auth/health | Antigravity (`fastapi`, `supabase`, `flutter`) | Maks. 5 layar utama (+ Detail) |
| **Hari 4** | Rab, 18 Nov | Slice 2 — Auth & Zona | Finalisasi integrasi auth dan endpoint/UI zona setelah fondasi Slice 1; **Akun & Set Radius** (`25/50/100 km`, default `50 km`), koordinat GPS/manual, 2 toggle | Antigravity (`fastapi`, `flutter`, `geolocator`) | 1 titik aktif/akun; tanpa GPS background |
| **Hari 5** | Kam, 19 Nov | Slice 3A — Backend BMKG & Radar | Sync worker `TEWS JSON` + `Nowcast CAP XML`, Haversine, `eq-priority-v1`, `cap-priority-v1`, `GET /api/v1/events` & `/api/v1/map/markers` | Antigravity (`fastapi`, `httpx`, `pytest`) | Tanpa `geopandas`/`shapely`; cache di PostgreSQL |
| **Hari 6** | Jum, 20 Nov | Slice 3B — Peta & Feed | Layar **Beranda & Feed** + **Peta Interaktif** (`flutter_map` OSM, lingkaran radius, maks `100` marker, alasan prioritas) | Antigravity (`flutter`, `ui-ux-pro-max`) | Material 3 standar fungsional; filter Sekitar/Semua |
| **Hari 7** | Sab, 21 Nov | Slice 3C — Detail Bencana & Uji Radar | Halaman **Detail Bencana** (atribut resmi BMKG, keterangan tsunami, laporan verified terkait) + uji batas radius/antimeridian | Antigravity (`flutter`, `pytest`) | Tanpa halaman detail laporan terpisah |
| **Hari 8** | Min, 22 Nov | Slice 4A — Backend Lapor Warga | Endpoint laporan 5 kategori, sanitasi JPEG Pillow (hapus EXIF), idempotensi `client_request_id`, Supabase Storage & adapter lokal | Antigravity (`fastapi`, `python-multipart`, `supabase`) | Maks. 1 foto; bucket privat + URL baca 5 menit |
| **Hari 9** | Sen, 23 Nov | Slice 4B — Flutter Lapor & Moderasi | Layar **Lapor Warga** (kompresi ~`1024 px`, JPEG `75%`), Tab **Tinjau** Admin, transaksi & audit `report_verifications`, uji konflik `409` | Antigravity (`flutter`, `fastapi`) | Tanpa web admin terpisah / live chat |
| **Hari 10** | Sel, 24 Nov | **Slice 5 + FEATURE FREEZE** | `notification_logs` (dedup + sequence replay), SSE, `flutter_local_notifications`, polling fallback, **Profil/Riwayat**, uji HP fisik & **SIMULASI** | Antigravity (`fastapi`, `flutter`, `android-cli-plugin`) | **Feature Freeze mutlak malam 24 Nov**; Maritim post-UAS |
| **Hari 11** | Rab, 25 Nov | QA & Testing | `pytest` (unit + PostgreSQL), Postman `api-testing`, widget & integration test Flutter, a11y (`flutter_a11y_agent`), cek NFR | Antigravity (`postman`, `flutter`, `e2e`) | Uji `AC-01..24` termasuk konflik & replay |
| **Hari 12** | Kam, 26 Nov | Security Audit, Deploy & Fallback | Audit (`security-audit`, `supabase` `get_advisors`, `postgresql-code-review`, `coderabbit`), bugfix, deploy Railway + verifikasi `localhost` & **SIMULASI** | Antigravity (`use-railway`) | Aturan 30 menit mentok; wajib jalan lokal |
| **Hari 13** | Jum, 27 Nov | **Finalisasi Rilis `v1.0.0`** | Smoke test final (Railway & `localhost`), rapikan [README.md](../README.md), tag rilis **`v1.0.0`** | Antigravity (`verification-before-completion`) | **Target rilis `v1.0.0` pada 27 Nov; belum dilaksanakan** |
| **Pasca-rilis** | **28 Nov – UAS** | Deliverables UAS (Minggu 16) | Pembuatan video demo minimal **10 menit** (YouTube) & artikel laporan maksimal **11–12 halaman** | User | Waktu lega setelah `v1.0.0` rilis |
