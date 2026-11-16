# Full Wireframe — Siaga Bencana

- Page 1 — Low-Fi Complete: 20 frame (12 frame Opus + 8 langkah/mode internal).
- Page 2 — Palet, Hi-Fi & Prototype: 23 frame, grid enam kolom, 19 paint styles.
- Baseline seluruh frame: 360 × 800; PNG individual: 720 × 1600.
- Dua flow: **Alur Utama Warga** dan **Alur Moderasi Admin**.
- 205 interaksi onClick tersimpan; smartAnimate 220 ms; kembali memakai action back.
- Seluruh tujuan navigasi dicek terhadap frame yang tersimpan. Settings: Custom size 360 × 800.

## Konsistensi dan ruang lingkup

Seluruh frame menggunakan class Screen dari skrip asli Opus tanpa mengubah file sumber. Dua belas frame asli dibuat ulang langsung dari fungsi aslinya. Hi-Fi menerapkan pemetaan palet pada komponen yang sama; geometri, radius, jarak, dan tipografi tetap mengikuti Opus. Semua tambahan adalah langkah, mode, tab, sheet, dialog, atau state UI-01..06.

Tab Tinjau hanya hadir untuk admin sesuai UI_SPEC. Jalur Sekitar → Tinjau tersedia pada varian **Admin Sekitar**, bukan akun citizen. Tambahan baris keempat: polling, tab Saya, picker pick_report, Admin Sekitar, serta dialog Tolak. Picker menggunakan back agar kembali ke pemanggil; dialog Setujui/Tolak memiliki state masing-masing. Panel foto mencontohkan konteks pemilik/admin untuk jejak peninjauan.

## Verifikasi

`figcraft-info.txt` mencatat hasil CLI info. `verification.json` mencatat ID frame, koneksi, flow, settings, hash skrip Opus, dan validasi file tersimpan. Seluruh 45 PNG lolos CRC setiap chunk dan dekompresi; kedua overview memiliki variasi data gambar, bukan render kosong. Overview Low-Fi dan Hi-Fi diperiksa secara visual, termasuk detail cuaca.

Prototype adalah demonstrasi navigasi dengan data tetap. Input, password eye, toggle, GPS, unggah, dan validasi backend bukan implementasi aplikasi. Tombol sumber membuka situs BMKG; tidak mengklaim URL event demo nyata. Ini bukan hasil uji Flutter/TalkBack atau layanan backend.

Artefak utama: `siaga-bencana-v1.figcraft`. Overview: `png/overview.png`, `png/overview-hifi.png`. Frame Low-Fi di `png/`; seluruh frame Hi-Fi di `png/hifi/`.
