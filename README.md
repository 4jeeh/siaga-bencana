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
