# Siaga Bencana mobile — Slice 1

Flutter3.47.7 / Dart3.13.5, Material3, Provider/ChangeNotifier, go_router, package:http.

Dari folder ini:

```powershell
../backend/.venv/Scripts/python.exe ../scripts/flutter_local.py pub get --offline
../backend/.venv/Scripts/python.exe ../scripts/flutter_local.py analyze --no-pub
../backend/.venv/Scripts/python.exe ../scripts/flutter_local.py test --no-pub
../backend/.venv/Scripts/python.exe ../scripts/flutter_local.py run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Helper memakai salinan SDK lokal `.tooling/` tanpa perintah Git; lihat [backend README](../backend/README.md).
`pubspec.lock` dipertahankan. Paket: provider6.1.5+1, go_router14.8.1, http1.6.0,
flutter_lints6.0.0. Semua berhasil diresolve dari cache lokal untuk SDK yang diminta.

Default API: Android emulator10.0.2.2:8000/api/v1, web/desktop127.0.0.1:8000/api/v1.
Perangkat fisik menggunakan IP LAN komputer lewat dart-define. Debug Android mengizinkan HTTP
untuk demo lokal; release mewajibkan HTTPS dan INTERNET permission tersedia. Web memerlukan
CORS origin eksplisit di backend. Tidak ada URL/kredensial Supabase di client.

Enam rute: /account, /home, /map, /reports, /profile, /events/:eventId.
Empat tab NavigationBar: Beranda/Peta/Lapor/Profil. Tanpa token atau belum dikonfirmasi /me
kembali akun; token valid tanpa zona menampilkan UI-01c placeholder. Tujuan deep-link detail
disimpan sampai sesi+zona valid. Zone picker/GET/PUT zona tidak dibuat pada Slice1.

Akun login/daftar terhubung ke API; status /health dan SIMULASI berasal dari metadata server.
Token hanya memori, expiry UTC, 401 menghapus sesi, respons dari generation sesi lama ditolak.
Password tidak dipangkas/disimpan/log; dihapus setelah submit. Error envelope dan Retry-After
mendukung pesan field dan cooldown tombol. Tidak ada refresh token, persistence, SSE/polling,
map data, upload, atau notifikasi pada Slice1.

`test/widget_test.dart` mencakup DTO/error, header HTTP, guard/rute, race401, expiry, health,
login/register, tema, dan overflow pada360px/200%. `test/live_smoke.dart` khusus smoke nyata,
dipanggil oleh `backend/scripts/smoke_live.py` dengan database/API sementara.

Android/web scaffolding sudah dibuat. Build APK, emulator/perangkat, TalkBack, deployment dan
uji lifecycle notifikasi belum diklaim; itu gate implementasi berikutnya.
