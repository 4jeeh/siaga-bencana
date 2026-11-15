# Handoff — Hari 1, 15 November 2026

- Acuan yang dibaca: `AGENTS.md`, `README.md`, dan `docs/README.md`.
- Hasil sesi: `docs/IDEA.md`, berisi usulan dua pembeda, tepat lima layar utama dan satu detail, tujuh entitas relasional, batas MVP, serta empat keputusan sebelum PRD.
- Dua pembeda yang diusulkan: Radar Radius dengan alasan prioritas transparan; laporan warga dengan status dan jejak verifikasi admin.
- Belum dikunci user: cakupan kategori kejadian, bentuk skor, pilihan radius, dan kanal moderasi. Lihat bagian 6 `IDEA.md`.
- Hal yang perlu diverifikasi saat persiapan implementasi: kontrak/cakupan feed BMKG, kompatibilitas versi stack dan wheel Python, transport SSE, serta konfigurasi Railway–Supabase. Tidak ada riset web dalam sesi ini.
- Batas penting: skor bukan model risiko; alert real-time hanya saat aplikasi aktif; sumber warga terpisah dari BMKG; mode lokal mencakup PostgreSQL dan penyimpanan lokal, sementara data live/tile peta tetap bergantung jaringan.
- Berikutnya: user mengunci empat keputusan, lalu Codex menyusun `docs/PRD.md` pada Hari 2; arsitektur, ERD, dan kontrak API diselesaikan sebelum planning lock akhir 17 November 2026.
- Tidak menjalankan perintah Git, mengubah file acuan, atau membuat kode aplikasi. Git/GitHub, implementasi per slice, QA, dan deploy menjadi tanggung jawab Antigravity.
