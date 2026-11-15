# Siaga Bencana

Aplikasi mobile **Flutter** dengan backend **Python FastAPI REST API** dan database relasional **PostgreSQL (Supabase)** untuk informasi gempa bumi, potensi tsunami, bencana besar (erupsi gunung api & banjir) dari sumber terbuka **BMKG**, pemetaan lokasi terdampak, notifikasi berbasis radius pengguna, serta pelaporan kondisi oleh warga.

> Proyek Tugas Besar / UAS — Pemrograman Aplikasi Bergerak (Semester 5)

---

## Arsitektur Singkat

```text
Flutter Mobile App (mobile/)
        │  REST API (HTTPS / JSON)
        ▼
FastAPI Backend (backend/ — Railway / Localhost)
   ├── Worker / Sync Open Data BMKG
   ├── Kalkulasi Radius & Logika Peringatan
   └── Auth, Validasi & Upload Laporan Warga
        │
        ▼
PostgreSQL Relasional + Storage (Supabase)
```

---

## Struktur Repository

* `docs/` — Brainstorming ide (`IDEA.md`), PRD, flowchart arsitektur, ERD SQL relasional, kontrak API, dan handoff antar sesi.
* `backend/` — Backend REST API menggunakan Python FastAPI + SQLModel + PostgreSQL *(disiapkan di Fase Build)*.
* `mobile/` — Aplikasi mobile Flutter *(disiapkan di Fase Build)*.

---

## Roadmap Bertahap

* [x] **Minggu 13 — Hari 1:** Inisialisasi repo GitHub, aturan proyek (`AGENTS.md`), & struktur dokumentasi.
* [ ] **Minggu 13 — Hari 1–3:** Brainstorming fitur unik (`IDEA.md`), PRD (`PRD.md`), Flowchart & Arsitektur, ERD Relasional SQL (`ERD.sql`), Kontrak API, & desain Figma.
* [ ] **Minggu 13 Akhir – Minggu 14:** Build iteratif per fitur (*Pondasi -> Auth & Radius -> BMKG & Peta -> Laporan Warga -> Notifikasi & Fitur Pembeda*).
* [ ] **Minggu 15 Awal:** QA Testing (`pytest`, Flutter widget/integration test), Security Audit, dan Deploy (Railway + fallback `localhost`).
