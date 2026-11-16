# Backend Slice 1

Python 3.15.0; dependencies utama dipin di `requirements.txt`, seluruh paket environment awal
di `requirements-lock.txt`. Tidak ada perubahan paket pada `.venv` dalam implementasi ini.
Lima endpoint aktif: `POST /api/v1/auth/register`, `POST /api/v1/auth/login`,
`GET /api/v1/me`, `GET /api/v1/health`, `GET /api/v1/ready`.

## Jalankan lokal (PowerShell dari backend/)

```powershell
.venv/Scripts/python.exe scripts/local_pg.py start
.venv/Scripts/python.exe scripts/bootstrap_local.py
.venv/Scripts/python.exe scripts/configure_local.py
.venv/Scripts/python.exe -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --workers 1 --no-proxy-headers
```

`configure_local.py` membuat `.env` yang di-ignore dengan dua secret acak independen;
tidak mencetak rahasia atau menimpa `.env` yang sudah ada. Jangan salin `.env` ke GitHub.
`bootstrap_local.py` hanya menyasar cluster disposable `127.0.0.1:54329`, membuat role/database
yang belum ada, tanpa reset. Cluster ini menggunakan trust loopback, khusus dev/test.
Tidak digunakan sebagai pola autentikasi database hosting.

Jika `pg_ctl start` gagal dengan restricted-token Windows error 87 di sandbox, gunakan
`.venv/Scripts/python.exe scripts/local_pg.py foreground` pada terminal terpisah. Ini menjalankan
PostgreSQL dengan hak proses yang sama; tidak mengubah keamanan OS. `start` biasa memakai
`stderr=DEVNULL`, batas tunggu 30 detik dan timeout proses 40 detik agar tidak menggantung.
Cluster yang sudah berjalan dipertahankan. Tidak tersedia perintah reset destruktif.

```powershell
.venv/Scripts/python.exe scripts/local_pg.py status
.venv/Scripts/python.exe scripts/local_pg.py stop
```

Untuk emulator Android: backend bind `0.0.0.0` bila diperlukan lingkungan emulator/HP LAN,
dan gunakan `API_BASE_URL=http://10.0.2.2:8000/api/v1` (emulator) atau IP LAN komputer (HP).
Jangan membuka port PostgreSQL ke jaringan. Flutter web memerlukan origin eksplisit, misalnya
`CORS_ORIGINS=["http://localhost:8080"]`, lalu `flutter run -d chrome --web-port=8080`.

## Migrasi dan privilege

`scripts/migrate.py` membaca **MIGRATION_DATABASE_URL**, bukan DATABASE_URL. Jalankan dengan
owner schema terpisah. Role `siaga_runtime` harus dibuat operator terlebih dahulu, LOGIN,
NOSUPERUSER, NOCREATEDB, NOCREATEROLE, NOREPLICATION, NOBYPASSRLS, bukan anggota owner.
Di hosting berikan password melalui secret manager; runtime DATABASE_URL memakai psycopg
dan TLS (`sslmode=require` atau `verify-full`). Supabase pooler boleh dipakai sesuai jaringan;
schema `siaga` tidak boleh diekspos melalui PostgREST.

DDL bisnis tetap berasal dari `../docs/ERD.sql` tanpa perubahan. Runner mengganti pembungkus
BEGIN/COMMIT dengan transaksi atomik yang mencakup DDL, checksum SHA256, pencatatan
`siaga.schema_migrations` revisi `0001_foundation`, serta grants. Advisory transaction lock
mencegah apply bersamaan. Apply ulang memverifikasi checksum; schema tanpa tracking atau
revision/hash berbeda ditolak, tanpa DROP atau adopsi diam-diam.

Runtime mendapat USAGE dan SELECT; INSERT tabel bisnis; UPDATE dibatasi per kolom untuk
users/zona/laporan/log. Tidak ada UPDATE role/active users, DELETE/TRUNCATE, CREATE schema,
atau mutasi tracking. `report_verifications` SELECT/INSERT saja; `notification_logs`
UPDATE(read_at) saja. Grants PUBLIC, anon/authenticated bila ada, dan ACL kolom lama dicabut
sebelum grant ulang. Permission ingestion tambahan belum dibuat pada Slice 1.

## Operasional

- JWT HS256 TTL3600, Argon2id, role/active dibaca dari DB setiap `/me`. Token client hanya memori.
- Error HTTP/validasi/DB mengikuti kontrak; semua response no-store dan UUID request server.
- Limiter rolling window dalam satu proses: login5/register3 per IP/menit; read120 per user/menit.
  Jalankan **satu worker/instans**; `--no-proxy-headers` menghindari percaya X-Forwarded-For bebas.
  Railway/proxy allowlist perlu dikonfigurasi dan diuji sebelum deploy.
- Health tidak mengakses dependency. Ready memeriksa role, 12 tabel, tracking/checksum/grants,
  serta hasil storage probe privat. Probe startup dan setiap30detik di luar request;
  cache >60detik gagal503. File probe langsung dibersihkan, storage tidak disajikan statis.
- STORAGE_ROOT adalah nama kanonis; LOCAL_STORAGE_DIR alias opsional yang harus konsisten.
  Adapter Supabase/upload belum diimplementasikan: pilihan supabase sengaja belum ready.
- SIMULATION_CLOCK hanya untuk jam domain; JWT dan limiter tetap waktu aktual. Simulation
  harus memakai nama DB berakhiran `_simulation`, folder berakhiran `simulation`, sync nonaktif.
  Tidak ada seed/switch otomatis. BMKG settings dicadangkan, worker belum tersedia.

## Uji nyata

```powershell
.venv/Scripts/python.exe -m pytest -q
.venv/Scripts/python.exe -m ruff check . ../scripts
.venv/Scripts/python.exe scripts/smoke_live.py
```

Pytest memerlukan PostgreSQL lokal di54329, membuat DB `siaga_test_<uuid>` milik owner,
apply DDL asli, lalu menghapus **hanya DB yang dibuat tes** pada teardown. Tidak memakai
SQLite atau mock repository. Smoke menyalakan Uvicorn sementara, menjalankan client Flutter
HTTP nyata, kemudian menghentikan server dan menghapus DB terisolasi.

Skill dan acuan implementasi: FastAPI, python-testing-patterns, Supabase Postgres best practices,
Flutter architecture/routing/http/manual serialization/responsive/widget-test/static-analysis,
ui-ux-pro-max. Kontrak proyek mengungguli rekomendasi codegen/deployment dari skill.
Rujukan API yang diperiksa: [FastAPI errors](https://fastapi.tiangolo.com/tutorial/handling-errors/),
[PyJWT claims](https://pyjwt.readthedocs.io/en/latest/usage.html),
[Flutter HTTP](https://docs.flutter.dev/cookbook/networking/send-data).

## Tool Flutter dalam sandbox

SDK terpasang `C:/Users/Administrator/develop/flutter` tidak dapat menulis lockfile dari sandbox;
salinan SDK dan Pub cache tersedia di root `.tooling/` (di-ignore). `scripts/flutter_local.py`
menjalankan `dart.exe flutter_tools.snapshot --no-version-check --suppress-analytics`, sehingga
tidak menjalankan perintah Git yang biasa dipanggil launcher flutter.bat. Helper ini memerlukan
salinan SDK lengkap, termasuk packages/dev/examples/bin cache, dan Pub cache; tanpa folder `.git`.
Tidak mengubah SDK sistem atau `.venv`.

Dari `mobile/`, `../backend/.venv/Scripts/python.exe ../scripts/flutter_local.py <argumen>`
setara menjalankan tool Flutter terpasang. Jika sandbox tidak membatasi SDK dan larangan Git
internal sudah tidak berlaku, operator dapat memakai Flutter CLI biasa sesuai kebijakan sesi.
