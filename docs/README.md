# Dokumentasi Perencanaan — Siaga Bencana

**Lock Planning selesai: 16 November 2026.** Siap Slice 1 (17 Nov): Foundation, Auth, & DB Migration. Implementasi dan seluruh urusan Git/GitHub ditangani Antigravity.

1. [IDEA.md](IDEA.md) — Konsep dan dua fitur pembeda.
2. [PRD.md](PRD.md) — Kebutuhan, scope, UI/FR/AC/NFR dan aturan bisnis.
3. [ARCHITECTURE.md](ARCHITECTURE.md) — Layer, Mermaid, transaksi, lifecycle dan fallback.
4. [ERD.sql](ERD.sql) — DDL PostgreSQL15+ dengan 12 tabel, constraint, indeks dan trigger audit.
5. [API_CONTRACT.md](API_CONTRACT.md) — REST `/api/v1`, DTO/error, upload, auth, SSE/replay.
6. [UI_SPEC.md](UI_SPEC.md) — Enam layar Material3, wireframe ASCII, state, endpoint dan a11y; wireframe visual, palet warna & prototype FigCraft selesai di [siaga-bencana-v1.figcraft](wireframes/siaga-bencana-v1.figcraft) ([overview.png](wireframes/png/overview.png) & [overview-hifi.png](wireframes/png/overview-hifi.png)).
7. [HANDOFF.md](HANDOFF.md) — Keputusan final, hasil validasi dan instruksi Slice 1.
8. [SCHEDULE.md](SCHEDULE.md) — Freeze 23 Nov, target rilis 26 Nov; bukan klaim rilis sudah dilakukan.

Nama/DDL normatif di ERD.sql, wire DTO/endpoint di API_CONTRACT.md, presentasi di UI_SPEC.md; semuanya mengimplementasikan PRD. Jangan mengubah kontrak salah satu tanpa menyelaraskan lainnya dan mencatat handoff. Runtime paket, UI dan deployment tetap gate implementasi.
