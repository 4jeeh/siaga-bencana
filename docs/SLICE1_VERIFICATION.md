# Slice 1 — Foundation, Auth, & DB Migration

Tanggal pelaksanaan: **17 November 2026**. Implementasi Codex berdasarkan instruksi khusus user
yang memperluas tugas sesi ini dari planning ke coding Slice1. Tidak menjalankan perintah Git.
Kontrak `API_CONTRACT.md`, DDL bisnis `ERD.sql`, `UI_SPEC.md`, dan palet wireframe tidak diubah.

## Hasil

Backend mempunyai struktur core/db/models/schemas/repositories/services/api-v1. Register/login/me
memakai PostgreSQL nyata, Argon2id, JWT HS256 iss/aud/sub/iat/exp TTL3600. DTO dipisahkan dari ORM;
role/active dibaca ulang dari DB, register selalu citizen. JSON/body/query/error/throttle/header
mengikuti kontrak. Health liveness, ready mengecek role/grants/schema/revision/checksum/storage.
Jam domain simulasi tidak mengubah expiry kredensial atau limiter.

Migrasi memakai DDL terkunci secara atomik, advisory lock dan tracking `0001_foundation`.
Database dev `siaga_dev` telah dimigrasikan, owner `siaga_owner`, runtime `siaga_runtime`.
Tabel bisnis12 ditambah `schema_migrations`; FK13. Runtime tidak mendapat DELETE/TRUNCATE/CREATE,
audit tidak bisa UPDATE, log hanya UPDATE(read_at). Grant lama per kolom juga dicabut saat reapply.
Schema bisnis tidak diekspos langsung ke Flutter/Supabase PostgREST.

Flutter memiliki enam rute dan empat tab, tema Material3 sesuai Page2, Provider MVVM,
DTO manual dan http. Login/register/me berfungsi, health menampilkan mode server, expiry/401
menghapus sesi memori, respons sesi lama diabaikan. Akun tanpa zona tetap UI-01c placeholder.
UI-02..06 adalah placeholder eksplisit. Belum ada endpoint zona, worker BMKG, data peta,
upload laporan, SSE, atau implementasi Slice2–5.

## Bukti eksekusi

Environment terverifikasi: Python3.15.0; PostgreSQL18.6 lokal; Flutter3.47.7/Dart3.13.5.
Paket `.venv` dipertahankan; pin utama dan lock lengkap tersedia. Flutter dependencies
berhasil diresolve offline dari cache, dengan lockfile yang disimpan.

| Gate | Perintah / hasil aktual |
|---|---|
| Apply dev | `python scripts/bootstrap_local.py` → `siaga_dev ready; migration owner and non-owner runtime are separate.` |
| Backend | `.venv/Scripts/python.exe -m pytest -q` → **87 passed, 1 warning** |
| Python lint | `.venv/Scripts/python.exe -m ruff check . ../scripts` → **All checks passed!** |
| Flutter dependencies | `flutter pub get --offline` → **Got dependencies!** |
| Flutter static analysis | `flutter analyze --no-pub` → **No issues found!** |
| Flutter suite | `flutter test --no-pub test/widget_test.dart` → **+12: All tests passed!** |
| Real HTTP integration | `python scripts/smoke_live.py` → **+1: All tests passed!**; **Smoke API stopped; isolated PostgreSQL database removed.** |

Flutter dijalankan melalui `scripts/flutter_local.py`: Dart executable + SDK tool snapshot
versi yang sama, flag no-version-check/suppress-analytics. SDK terpasang read-only di sandbox;
salinan SDK/cache berada di `.tooling/` yang di-ignore. Launcher flutter.bat tidak dipakai karena
memanggil Git internal. Tidak ada perintah Git untuk menilai perubahan atau membuat commit.

Warning backend tunggal berasal dari Starlette TestClient yang mendeprekasi httpx menuju httpx2.
Tes tetap lulus dengan versi terkunci user; tidak mengganti dependensi hanya untuk menghapus warning.
Pub melaporkan dua versi transitive lebih baru di luar constraint; resolver berhasil tanpa upgrade.

Tes PostgreSQL mencakup apply bersih/idempotent/checksum drift, FK/tabel, penolakan DELETE/TRUNCATE
di seluruh12 tabel, pembatasan audit/log/role, pemulihan ACL, dan registrasi bersamaan201/409.
API mencakup health/ready200/503, DB putus/role-owner/revision salah/probe stale, normalisasi akun,
extra field/role injection/password, login salah/akun nonaktif, JWT expiry/issuer/audience/subject/
missing claim/future-iat/alg-none/HS384, unknown/duplicate query, malformed JSON/tipe/body limit,
HTTPException/500 sanitasi, rate5/3/120 serta pemulihan window, dan waktu simulasi.
Konfigurasi/storage diuji terhadap secret lemah, driver/role salah, pemisahan simulasi,
path publik/root/file invalid dan cleanup probe.

Tes Flutter mencakup DTO/error/mode, header Bearer/Accept/GET tanpa body,401 reset, late401 lintas
sesi, expiry UTC, respons malformed/Retry-After, health offline, login/register→me→zona placeholder,
logout dan password clear, enam rute/guard/deep-link, palette/touch-target. Akun login/register,
zona placeholder, empat tab dan detail diperiksa tanpa framework overflow pada360px/font200%.
Smoke nyata menggunakan **client Flutter http asli → Uvicorn TCP → runtime PostgreSQL**, tanpa
MockClient atau mock repository, untuk health/ready/register/me/login.

Kegagalan pengembangan yang sudah diperbaiki: restricted-token87 pada pg_ctl (fallback foreground),
SDK lockfile read-only (salinan lokal), await pada reset tester yang void, lint Dart, dan cleanup
Uvicorn di Windows (server thread dengan should_exit/join). Hasil tabel di atas adalah hasil
setelah perbaikan, bukan klaim semua percobaan awal langsung lolos.

## Batas bukti dan tindak lanjut

- Pengujian DB dilakukan pada PostgreSQL18.6 lokal, belum Supabase/Railway/pooler target.
- APK/emulator/perangkat fisik/TalkBack belum diuji. Asset launcher masih scaffold Flutter.
- Adapter Supabase Storage dan ingestion/SSE belum dibangun. STORAGE_BACKEND=supabase belum ready,
  supaya endpoint tidak mengklaim adapter yang belum ada sebagai sehat.
- Jalankan satu worker/instans untuk limiter. Proxy allowlist, TLS hosting, migrasi/grants target,
  dan uji Android lifecycle diselesaikan pada gate deploy/slice yang sesuai.
- Token logout tetap valid server hingga expiry sesuai kontrak MVP; hanya sesi client yang dihapus.

Cara menjalankan dan mengulang pengujian tersedia di [backend README](../backend/README.md)
dan [mobile README](../mobile/README.md). `.env` lokal telah dibuat dengan secret acak tanpa
menampilkannya; `.env.example` tidak berisi rahasia. `.localdb/`, `.storage/`, `.tooling/`, `.venv/`,
build/cache dan `.env` di-ignore. Source kontrak SQL/wire tetap asli.

## Manifest file sesi

Daftar berikut menyebut source/config/test/docs dan scaffolding Flutter yang dibuat atau diubah.
Artefak ignored seperti cache, `.env`, cluster dan SDK tidak masuk daftar commit-review ini.

```text
.gitignore
backend/.env.example
backend/README.md
backend/app/__init__.py
backend/app/api/__init__.py
backend/app/api/v1/__init__.py
backend/app/api/v1/routes.py
backend/app/core/__init__.py
backend/app/core/config.py
backend/app/core/errors.py
backend/app/core/rate_limit.py
backend/app/core/security.py
backend/app/db/__init__.py
backend/app/db/migrations.py
backend/app/db/session.py
backend/app/main.py
backend/app/models/__init__.py
backend/app/models/user.py
backend/app/repositories/__init__.py
backend/app/repositories/users.py
backend/app/schemas/__init__.py
backend/app/schemas/auth.py
backend/app/schemas/common.py
backend/app/services/__init__.py
backend/app/services/auth.py
backend/app/services/readiness.py
backend/pyproject.toml
backend/requirements-lock.txt
backend/requirements.txt
backend/scripts/__init__.py
backend/scripts/bootstrap_local.py
backend/scripts/configure_local.py
backend/scripts/local_pg.py
backend/scripts/migrate.py
backend/scripts/smoke_live.py
backend/tests/__init__.py
backend/tests/conftest.py
backend/tests/test_api.py
backend/tests/test_config_storage.py
backend/tests/test_database.py
docs/HANDOFF.md
docs/SLICE1_VERIFICATION.md
mobile/.gitignore
mobile/.metadata
mobile/README.md
mobile/analysis_options.yaml
mobile/android/.gitignore
mobile/android/app/build.gradle.kts
mobile/android/app/src/debug/AndroidManifest.xml
mobile/android/app/src/main/AndroidManifest.xml
mobile/android/app/src/main/kotlin/id/ac/siaga/siaga_bencana/MainActivity.kt
mobile/android/app/src/main/res/drawable-v21/launch_background.xml
mobile/android/app/src/main/res/drawable/launch_background.xml
mobile/android/app/src/main/res/mipmap-hdpi/ic_launcher.png
mobile/android/app/src/main/res/mipmap-mdpi/ic_launcher.png
mobile/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
mobile/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
mobile/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
mobile/android/app/src/main/res/values-night/styles.xml
mobile/android/app/src/main/res/values/styles.xml
mobile/android/app/src/profile/AndroidManifest.xml
mobile/android/build.gradle.kts
mobile/android/gradle.properties
mobile/android/gradle/wrapper/gradle-wrapper.properties
mobile/android/settings.gradle.kts
mobile/lib/app.dart
mobile/lib/core/config/api_config.dart
mobile/lib/core/network/api_client.dart
mobile/lib/core/network/api_envelope.dart
mobile/lib/core/routing/app_router.dart
mobile/lib/core/routing/placeholder_page.dart
mobile/lib/core/session/session_coordinator.dart
mobile/lib/core/theme/app_theme.dart
mobile/lib/features/auth/account_screen.dart
mobile/lib/features/auth/auth_dto.dart
mobile/lib/features/auth/auth_repository.dart
mobile/lib/features/auth/auth_view_model.dart
mobile/lib/features/event_detail/event_detail_screen.dart
mobile/lib/features/home/home_screen.dart
mobile/lib/features/map/map_screen.dart
mobile/lib/features/profile/profile_screen.dart
mobile/lib/features/reports/reports_screen.dart
mobile/lib/main.dart
mobile/pubspec.lock
mobile/pubspec.yaml
mobile/test/live_smoke.dart
mobile/test/widget_test.dart
mobile/web/favicon.png
mobile/web/icons/Icon-192.png
mobile/web/icons/Icon-512.png
mobile/web/icons/Icon-maskable-192.png
mobile/web/icons/Icon-maskable-512.png
mobile/web/index.html
mobile/web/manifest.json
scripts/flutter_local.py
```
