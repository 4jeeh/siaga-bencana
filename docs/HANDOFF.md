# Handoff — Hari 1 (Final), 15 November 2026

- Acuan yang dibaca: `AGENTS.md`, `README.md`, dan `docs/README.md`.
- Hasil sesi: `docs/IDEA.md` selesai **dan ke-4 keputusan Hari 1 sudah DIKUNCI oleh user**:
  1. **Cakupan Kejadian MVP (Terkunci):** Data resmi BMKG mengambil **Gempa & Potensi Tsunami (`DataMKG/TEWS` JSON)** + **Peringatan Dini Cuaca Ekstrem/Petir (`alerts/nowcast/id` RSS/CAP XML)** dilengkapi **toggle preferensi alert per user**. Feed **Maritim/Gelombang Tinggi (`maritim.bmkg.go.id`)** dicatat sebagai *bonus akhir opsional* hanya bila fitur inti beres lebih awal sebelum Feature Freeze `28 Nov`. Laporan warga mencakup **5 kategori** (*Gempa, Banjir, Erupsi, Cuaca Ekstrem, Kabut Asap/Lainnya*). Kualitas udara (`PM2.5`) dan erupsi gunung api tidak di-sync otomatis karena tidak ada REST API JSON terbuka yang simpel.
  2. **Pembeda & Skor (Terkunci — A):** Radar Radius dengan skor prioritas transparan (`S = 60P + 25M + 15T` untuk gempa; label aturan/status wilayah pada Nowcast) + alasan teks jelas + laporan warga berjejak verifikasi.
  3. **Pengaturan Zona (Terkunci — A):** 1 titik pantau GPS/manual, radius preset `25 / 50 / 100 km` (default `50 km`), plus toggle preferensi peringatan resmi di profil/zona.
  4. **Kanal Moderasi Admin (Terkunci — A):** Role `admin` memakai tab **Tinjau** di layar **Lapor Warga** (transaksi state machine `pending -> in_review -> verified/rejected` + audit log `report_verifications`).
- Catatan teknis untuk diuji sebelum/saat Hari 2–3: verifikasi payload aktual XML `bmkg.go.id/alerts/nowcast/id` (cara pencocokan wilayah provinsi/kecamatan atau koordinat agar sinkron ringan ke `disaster_events` + `alert_zones`), wheel Python 3.15, SSE, serta koneksi Railway–Supabase.
- Batas penting: skor bukan model risiko ilmiah; alert SSE hanya saat aplikasi aktif (bukan push latar belakang saat app mati); sumber warga terpisah dari BMKG; mode lokal mencakup PostgreSQL lokal, adapter storage lokal, dan seed demo bertanda **SIMULASI**.
- Berikutnya (**Hari 2**): Codex langsung menyusun **`docs/PRD.md`** berdasar 4 keputusan terkunci ini tanpa bertanya ulang dari nol; arsitektur (`ARCHITECTURE.md`), ERD (`ERD.sql`), dan kontrak API (`API_CONTRACT.md`) diselesaikan sebelum planning lock akhir **17 November 2026**.
- Git/GitHub dan commit bertahap ditangani oleh Antigravity.
