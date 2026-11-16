# Jadwal Proyek — Siaga Bencana

**Author:** Jiddan Ibnu Ali (`24051214203`)  
**Revisi Jadwal:** 16 November 2026 — dimajukan agar **finalisasi rilis `v1.0.0` tercapai pada Senin, 30 November 2026** (sebelumnya `02 Desember 2026`) tanpa memotong fase QA, Security Audit, dan Deploy.

## Ringkasan Penyesuaian
* **Planning Lock:** Tetap akhir **Selasa, 17 November 2026** (Hari 3).
* **Fase Build (`18–26 Nov`, 9 hari):** Dipadatkan 2 hari dari rencana awal dengan menggabungkan *scaffolding* Backend+Mobile pada Hari 4 (`18 Nov`) serta menggabungkan logika `notification_logs` + stream SSE/polling pada Hari 11 (`25 Nov`), karena struktur skema log disiapkan sejak awal.
* **Feature Freeze:** **Kamis, 26 November 2026** (Hari 12) — dilarang menambah fitur setelah tanggal ini. Fitur bonus **Maritim (`maritim.bmkg.go.id`)** ditangguhkan ke pasca-UAS `v1.0.0` kecuali seluruh fitur inti tuntas lebih awal sebelum 26 November.
* **QA, Security, Deploy & Rilis (`27–30 Nov`, 4 hari penuh):** Utuh sesuai porsi awal.
* **Pasca-rilis (`01 Des – UAS`):** 2 hari ekstra untuk video demo minimal 10 menit (YouTube) dan artikel maksimal 11–12 halaman.

---

## Jadwal Harian (15 November – UAS Minggu 16)

| Hari | Tanggal | Fase / Slice | Fokus & Deliverable Utama | Penanggung Jawab / Fokus Teknis | Status & Guardrail |
|---|---|---|---|---|---|
| **Hari 1** | Min, 15 Nov | Planning & Ide | Repo GitHub, [AGENTS.md](../AGENTS.md), form dosen, [IDEA.md](IDEA.md), [HANDOFF.md](HANDOFF.md), kunci 4 keputusan | Codex + Antigravity | **SELESAI** (`280fe21`) |
| **Hari 2** | Sen, 16 Nov | Planning (PRD & Arsitektur) | [PRD.md](PRD.md), [ARCHITECTURE.md](ARCHITECTURE.md) (7 diagram Mermaid), pembaruan [HANDOFF.md](HANDOFF.md), revisi jadwal `30 Nov` | Codex + Antigravity | **SELESAI** (`4f3e656` + update jadwal) |
| **Hari 3** | Sel, 17 Nov | **LOCK PLANNING** | `docs/ERD.sql`, `docs/API_CONTRACT.md`, `docs/UI_SPEC.md` (+ wireframe) | Codex + Antigravity (`figcraft`, `figma`, `postman`, `postgresql-optimization`) | **Planning dikunci akhir hari** |
| **Hari 4** | Rab, 18 Nov | **Slice 1 — Foundation (Backend + Mobile)** | Setup `backend/` FastAPI + migrasi `ERD.sql` (`/health`) **dan** setup skeleton `mobile/` Flutter (`go_router` 5 layar + tes `/health`) | Antigravity (`fastapi`, `supabase`, `flutter`) | Dipadatkan 1 hari; maksimal 5 layar utama (+ Detail) |
| **Hari 5** | Kam, 19 Nov | Slice 2 — Auth & Zona | Auth JWT Argon2, endpoint & UI **Akun & Set Radius** (`25/50/100 km`, default `50 km`), koordinat GPS/manual, 2 toggle | Antigravity (`fastapi`, `flutter`, `geolocator`) | 1 titik aktif/akun; tanpa GPS background |
| **Hari 6** | Jum, 20 Nov | Slice 3A — Backend BMKG & Radar | Sync worker `TEWS JSON` + `Nowcast CAP XML`, Haversine, `eq-priority-v1`, `cap-priority-v1`, `GET /events` & `/map/markers` | Antigravity (`fastapi`, `httpx`, `pytest`) | Tanpa `geopandas`/`shapely`; cache di PostgreSQL |
| **Hari 7** | Sab, 21 Nov | Slice 3B — Peta & Feed | Layar **Beranda & Feed** + **Peta Interaktif** (`flutter_map` OSM, lingkaran radius, maks `100` marker, alasan prioritas) | Antigravity (`flutter`, `ui-ux-pro-max`) | Payload ringkas; filter Sekitar/Semua |
| **Hari 8** | Min, 22 Nov | Slice 3C — Detail Bencana | Halaman **Detail Bencana** (atribut resmi BMKG, keterangan tsunami, laporan verified terkait) + uji batas radius/antimeridian | Antigravity (`flutter`, `pytest`) | Tanpa halaman detail laporan terpisah |
| **Hari 9** | Sen, 23 Nov | Slice 4A — Backend Lapor Warga | Endpoint laporan 5 kategori, sanitasi JPEG Pillow (hapus EXIF), idempotensi `client_request_id`, Supabase Storage & adapter lokal | Antigravity (`fastapi`, `python-multipart`, `supabase`) | Maks. 1 foto; bucket privat + URL baca 5 menit |
| **Hari 10** | Sel, 24 Nov | Slice 4B — Flutter Lapor & Moderasi | Layar **Lapor Warga** (kompresi ~`1024 px`, JPEG `75%`), Tab **Tinjau** Admin, transaksi & audit `report_verifications`, uji konflik `409` | Antigravity (`flutter`, `fastapi`) | Tanpa web admin terpisah / live chat |
| **Hari 11** | Rab, 25 Nov | **Slice 5 — Notifikasi SSE, Polling & Polish** | `notification_logs` (dedup + sequence replay), stream SSE, `flutter_local_notifications`, polling fallback, **Profil/Riwayat**, polish `impeccable` | Antigravity (`fastapi`, `flutter`, `impeccable`) | Dipadatkan 1 hari; bebas Firebase SDK |
| **Hari 12** | Kam, 26 Nov | **FEATURE FREEZE** | Uji end-to-end di HP fisik/Emulator (`device-hub`) + buffer penyelesaian bug fitur inti & verifikasi mode **SIMULASI** | Antigravity (`android-cli-plugin`) | **Dilarang tambah fitur setelah 26 Nov** |
| **Hari 13** | Jum, 27 Nov | QA & Testing | Jalankan `pytest` (unit + PostgreSQL), Postman `api-testing`, widget & integration test Flutter, a11y (`flutter_a11y_agent`), cek NFR | Antigravity (`postman`, `flutter`, `e2e`) | Uji `AC-01..24` termasuk konflik & replay |
| **Hari 14** | Sab, 28 Nov | Security Audit & Review | Audit keamanan (`security-audit`, `supabase` `get_advisors`, `postgresql-code-review`, `coderabbit`) + perbaikan bug | Antigravity | Pastikan nol `.env`/secret bocor di repo |
| **Hari 15** | Min, 29 Nov | Deploy & Fallback Lokal | Deploy FastAPI + worker ke Railway (cek SSE proxy & pooler Supabase) + verifikasi mode `localhost` & seed **SIMULASI** tanpa internet | Antigravity (`use-railway`) | Aturan 30 menit mentok; wajib jalan lokal |
| **Hari 16** | Sen, 30 Nov | **Finalisasi Rilis `v1.0.0`** | Smoke test final (Railway & `localhost`), rapikan [README.md](../README.md), tag rilis **`v1.0.0`** | Antigravity (`verification-before-completion`) | **Target rilis `v1.0.0` tercapai** |
| **Pasca-rilis** | **01 Des – UAS** | Deliverables UAS (Minggu 16) | Pembuatan video demo minimal **10 menit** (YouTube) & artikel laporan maksimal **11–12 halaman** | User | Dapat 2 hari napas ekstra (`01–02 Des`) |
