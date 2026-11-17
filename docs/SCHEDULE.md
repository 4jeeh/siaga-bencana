# Jadwal Proyek — Siaga Bencana

**Author:** Jiddan Ibnu Ali (`24051214203`)  
**Revisi Jadwal (Final):** 16 November 2026 — dimajukan menjadi **13 hari kalender (`15–27 Nov 2026`)** agar **finalisasi rilis `v1.0.0` tercapai pada Jumat, 27 November 2026**.

## Ringkasan Penyesuaian
* **Lock Planning (Selesai Hari Ini, `16 Nov`):** Seluruh dokumen perencanaan (`PRD.md`, `ARCHITECTURE.md`, `ERD.sql`, `API_CONTRACT.md`, `UI_SPEC.md`) serta full wireframe FigCraft (Page 1 Low-Fi `20` frame + Page 2 Palet, Hi-Fi `23` frame & Prototype interaktif + `45` PNG) sudah selesai, dikunci, dan di-push pada **Senin, 16 November 2026**.
* **Fase Build (`17–24 Nov`, 8 hari penuh):** Seluruh Vertical Slice (Foundation -> Auth/Zona -> BMKG/Radar/Peta/Detail -> Lapor/Moderasi -> SSE/Notifikasi/Uji Perangkat) diselesaikan sebelum freeze.
* **Feature Freeze (`24 Nov`):** Mutlak pada **Selasa malam, 24 November 2026** — dilarang menambah fitur setelah tanggal ini. Fitur bonus **Maritim (`maritim.bmkg.go.id`)** resmi ditangguhkan ke pasca-UAS `v1.0.0`.
* **QA, Security, Deploy & Rilis (`25–27 Nov`, 3 hari):** QA & pengujian lengkap (`25 Nov`), Security Audit + Deploy Railway & verifikasi fallback `localhost`/`SIMULASI` (`26 Nov`), dan Smoke Test Final + tag rilis **`v1.0.0`** (`27 Nov`).
* **Pasca-rilis (`28 Nov – UAS`):** Video demo minimal 10 menit (YouTube) dan artikel maksimal 11–12 halaman.

---

## Jadwal Harian (15 – 27 November 2026 + UAS)

| Hari | Tanggal | Fase / Slice | Fokus & Deliverable Utama | Penanggung Jawab / Fokus Teknis | Status & Guardrail |
|---|---|---|---|---|---|
| **Hari 1** | Min, 15 Nov | Planning & Ide | Repo GitHub, [AGENTS.md](../AGENTS.md), form dosen, [IDEA.md](IDEA.md), kunci 4 keputusan | Codex + Antigravity | **SELESAI** (`280fe21`) |
| **Hari 2** | Sen, 16 Nov | **PRD, Arsitektur & LOCK PLANNING** | [PRD.md](PRD.md), [ARCHITECTURE.md](ARCHITECTURE.md), pembaruan [SCHEDULE.md](SCHEDULE.md), [ERD.sql](ERD.sql), [API_CONTRACT.md](API_CONTRACT.md), [UI_SPEC.md](UI_SPEC.md), plus wireframe [siaga-bencana-v1.figcraft](wireframes/siaga-bencana-v1.figcraft) & PNG | Codex (dokumen teks/SQL); Antigravity (review, FigCraft & Git) | **SELESAI** (`04f44d7` & `c924d39`); siap Slice 1 pada 17 Nov |
| **Hari 3** | Sel, 17 Nov | **Slice 1 — Foundation, Auth, & DB Migration** | Setup `backend/` + migrasi [ERD.sql](ERD.sql), fondasi JWT/Argon2 register/login/me, `/api/v1/health` dan `/api/v1/ready`; skeleton `mobile/` (`go_router` 5 layar + Detail) dan smoke auth/health | Codex + Antigravity (`fastapi`, `supabase`, `flutter`) | **SELESAI** (17 Nov); lihat [SLICE1_VERIFICATION.md](SLICE1_VERIFICATION.md) |
| **Hari 4** | Rab, 18 Nov | Slice 2 — Auth & Zona | Finalisasi auth & endpoint/UI zona (`GET/PUT /api/v1/me/zone`, **UI-01c** `25/50/100 km`, GPS sekali/`UI-03` manual picker, 2 toggle) — **2 micro-batch (Backend lalu Mobile)** | Codex `medium` (tulis kode) + Hydrogen (pub/`context7`/tes/Git) | 1 titik aktif/akun; tanpa GPS background; tanpa `flutter.bat` di Codex |
| **Hari 5** | Kam, 19 Nov | Slice 3A — Backend BMKG & Radar | **3 micro-batch:** (1) Haversine, antimeridian, ray-casting, `eq/cap-priority-v1`; (2) Worker TEWS JSON + CAP XML + lease; (3) `/events`, `/events/{id}`, `/map/markers` | Codex (`3A-1 high`, `3A-2/3 medium`) + Hydrogen (`pytest`/EXPLAIN/Git) | Tanpa `geopandas`/`shapely`; jangan gabung 3A dalam 1 call |
| **Hari 6** | Jum, 20 Nov | Slice 3B — Peta & Feed | Layar **Beranda & Feed (`UI-02`)** + **Peta Interaktif (`UI-03` Browse)** (`flutter_map` OSM, lingkaran radius, maks `100` marker, alasan prioritas) | Codex `medium` (kode Dart) + Hydrogen (`flutter analyze/test`/Git) *(opsional `Opus Medium` poles UI)* | Material 3 standar fungsional; filter Sekitar/Semua |
| **Hari 7** | Sab, 21 Nov | Slice 3C — Detail Bencana & Uji Radar | Halaman **Detail Bencana (`UI-06`)** (atribut TEWS/CAP, keterangan tsunami, laporan verified terkait) + uji batas radius/antimeridian | Codex `medium` (Dart/fixture) + Hydrogen (uji penuh `pytest`+Flutter/Git) | Tanpa halaman detail laporan terpisah |
| **Hari 8** | Min, 22 Nov | Slice 4A — Backend Lapor Warga | **2 micro-batch:** (1) Sanitasi JPEG Pillow, `report-payload-v1`, adapter lokal & Supabase Storage; (2) Endpoint `POST/GET /reports`, photo-url, claim/decision transaksi | Codex (`4A-1 high/medium`, `4A-2 high`) + Hydrogen (`supabase`/uji concurrent `pytest`/Git) | Maks. 1 foto; bucket privat + URL baca 5 menit |
| **Hari 9** | Sen, 23 Nov | Slice 4B — Flutter Lapor & Moderasi | Layar **Lapor Warga (`UI-04`)** (`Sekitar`/`Saya`, kompresi ~`1024 px` JPEG `75%`, `ReportPanel`), Tab **Tinjau** Admin, dialog alasan & konflik `409` | Codex `medium` (kode Dart) + Hydrogen (`flutter test`/Git) *(opsional `Opus Medium` poles UI)* | Tanpa web admin terpisah / live chat |
| **Hari 10** | Sel, 24 Nov | **Slice 5 + FEATURE FREEZE** | **3 micro-batch:** (1) `notification_logs` counter lock + `/sync` cursor; (2) `SSE /stream`; (3) Mobile `NotificationCoordinator` + polling fallback + **`UI-05` Profil** + `SIMULASI` | Codex (`5-1/2 high`, `5-3 medium`) + Hydrogen (`android-cli-plugin`/uji HP fisik/Git) | **Feature Freeze mutlak malam 24 Nov**; Maritim post-UAS |
| **Hari 11** | Rab, 25 Nov | QA & Testing | `pytest` (unit + PostgreSQL), Postman `api-testing`, widget & integration test Flutter, a11y (`flutter_a11y_agent`), cek NFR (`AC-01..24`) | Hydrogen (`postman`, `flutter`, `e2e`) + Codex `medium` *(fix temuan QA terisolasi)* | Uji `AC-01..24` termasuk konflik & replay |
| **Hari 12** | Kam, 26 Nov | Security Audit, Deploy & Fallback | Audit (`security-audit`, `supabase` `get_advisors`, `postgresql-code-review`, `coderabbit`), bugfix, deploy Railway + verifikasi `localhost` & `SIMULASI` | Hydrogen (`use-railway`, audit) + `Opus` hanya bila mentok >30m | Aturan 30 menit mentok; wajib jalan lokal |
| **Hari 13** | Jum, 27 Nov | **Finalisasi Rilis `v1.0.0`** | Smoke test final (Railway & `localhost`), rapikan [README.md](../README.md), tag rilis **`v1.0.0`** | Hydrogen (`verification-before-completion`) | **Target rilis `v1.0.0` pada 27 Nov; belum dilaksanakan** |
| **Pasca-rilis** | **28 Nov – UAS** | Deliverables UAS (Minggu 16) | Pembuatan video demo minimal **10 menit** (YouTube) & artikel laporan maksimal **11–12 halaman** | User (+ Codex `medium` draf & opsional `Opus` poles bahasa) | Waktu lega setelah `v1.0.0` rilis |

---

## Panduan Hemat Token: Plugin, MCP & Kolaborasi AI per Fase

Agar baseline prompt tetap ringan dan kuota **Codex + Antigravity** awet, buka **chat baru di tiap slice** (atau gunakan `/compact` bila perlu), pisahkan sub-batch **Backend vs Mobile** saat mendelegasikan ke Codex, larang Codex memanggil `flutter.bat`/`.tooling/` atau `git`, dan atur plugin sesuai tabel di bawah.

### 1. Klasifikasi Plugin & MCP Proyek

* **Aktif rutin saat coding (`Slice 2–5`):** Plugin `flutter`, `context7` *(cukup 2 ini di hari normal!)*; MCP `codegraph` *(opsional bila codebase membesar)*.
* **Skill lokal (dibaca maksimal `2–3` `SKILL.md` seperlunya per sub-batch, jangan sekaligus banyak):** `fastapi`, `python-testing-patterns`, `postgresql-optimization`, `postgresql-code-review`, `ui-ux-pro-max`.
* **Matikan permanen untuk proyek ini (tidak terpakai / dilarang `AGENTS.md`):**
  * Plugin: `auth0`, `base44`, `browse`, `canva`, `chrome-devtools-plugin`, `data-agent-kit-plugin`, `databricks`, `datadog`, `figma` *(diganti `figcraft`)*, `firebase` *(dilarang)*, `gcalendar`, `gdocs`, `gdrive`, `gemini-api`, `google-antigravity-sdk`, `google-cloud-developer`, `google-developer-knowledge`, `google_maps_platform` *(pakai OSM)*, `gsheets`, `gslides`, `keenable`, `keenable-select`, `modern-web-guidance-plugin`, `mongodb-atlas` *(NoSQL dilarang)*, `netlify`, `qodo`, `taste-skill`, `vercel-plugin`, `virustotal`.
  * MCP standalone: `lottiefiles`, `lottiefiles-creator`.

### 2. Nyalakan On-Demand & Pembagian Model / Effort per Hari

| Sesi / Hari | Plugin & MCP Aktif Hari Itu (sisanya matikan) | Skill Lokal Dibaca Saat Perlu (`<=2–3`/batch) | Pembagian Codex (`gpt-6-astra`) + Hydrogen + Opus |
|---|---|---|---|
| **Hari 2 — FigCraft** *(Selesai)* | MCP `figcraft` *(sudah dimatikan lagi)* | — | Selesai (`c924d39` & `cffbfcf`) |
| **Hari 3 — Slice 1** *(Selesai)* | `flutter`, `context7`, `supabase` *(dimatikan setelah selesai)* | `fastapi`, `python-testing-patterns`, `ui-ux-pro-max` | Selesai (`4521adc`, `bf2d044`, `aa98074`) |
| **Hari 4 — Slice 2** | **`flutter`, `context7`** *(tanpa `supabase`)* | Batch A: `fastapi`; Batch B: `ui-ux-pro-max`, `flutter-build-responsive-layout` | Codex **`medium`** (Batch A backend + Batch B `.dart`) · Hydrogen (`pub add`, `context7`, uji penuh, Git) |
| **Hari 5 — Slice 3A** | **`context7`**, opsional `codegraph` *(matikan `flutter` saat backend murni)* | `fastapi`, `postgresql-optimization`, `python-testing-patterns` | Codex (`3A-1` **`high`**, `3A-2/3` **`medium`**) · Hydrogen (`pytest` radar/antimeridian, Git) |
| **Hari 6 — Slice 3B** | **`flutter`, `context7`**; opsional `generative-icons`, `impeccable` | `ui-ux-pro-max`, `flutter-build-responsive-layout` | Codex **`medium`** (kode Dart) · Hydrogen (`flutter test`/fix minor/Git) · Opsional `Opus Medium` (1x poles UI) |
| **Hari 7 — Slice 3C** | **`flutter`, `context7`**, opsional `codegraph` | — | Codex **`medium`** (Dart & fixture test) · Hydrogen (uji penuh `pytest`+Flutter, Git) |
| **Hari 8 — Slice 4A** | **`context7`, `supabase`** *(nyalakan untuk Storage)* | `fastapi`, `python-testing-patterns` | Codex (`4A-1` `medium`/`high`, `4A-2` **`high`**) · Hydrogen (uji race `pytest` & Storage, Git) |
| **Hari 9 — Slice 4B** | **`flutter`, `context7`** *(matikan `supabase`)* | `ui-ux-pro-max` | Codex **`medium`** (kode Dart) · Hydrogen (`flutter test`/fix minor/Git) · Opsional `Opus Medium` (1x poles UI) |
| **Hari 10 — Slice 5 + Freeze** | **`flutter`, `context7`, `android-cli-plugin`** | `fastapi` | Codex (`5-1/2` **`high`**, `5-3` `medium`) · Hydrogen (uji emulator/HP Android + `SIMULASI`, Git) |
| **Hari 11 — QA & Testing** | **`postman`** *(HARI INI saja)*, **`flutter`, `android-cli-plugin`, `coderabbit`** | `e2e`, `flutter_a11y_agent` | Hydrogen (QA `AC-01..24` + Postman + Flutter tests) · Codex **`medium`** (fix terisolasi bila ada temuan) |
| **Hari 12 — Security & Deploy** | Matikan `postman`; nyalakan **`supabase`, `security-audit`, `coderabbit`, `railway`** | `postgresql-code-review` | Hydrogen (audit, deploy Railway, cek `localhost`) · `Opus` hanya jika bug mentok >30 menit |
| **Hari 13 — Rilis `v1.0.0`** | Minimal (`flutter`/`context7` + `superpowers`); matikan `railway`, `security-audit`, `coderabbit` | — | Hydrogen (`verification-before-completion`, smoke final, tag `v1.0.0`) |

> **Catatan hemat kuota:** `postman` dimatikan di luar Hari 11; `supabase` dimatikan kecuali di `Slice 1`, `4A`, dan `Hari 12`; **Codex** fokus menulis kode per micro-batch (`medium` default) tanpa `flutter.bat`/`.tooling/`/`git`; **Hydrogen** menjalankan semua uji berat & Git; **`Claude Opus 5.5` (`Medium`)** disimpan khusus untuk poles UI (`3B`/`4B`), cadangan bug mentok >30m, atau poles bahasa laporan.
