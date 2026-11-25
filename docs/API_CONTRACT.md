# Kontrak REST API — Siaga Bencana v1.0.0

**LOCKED: 16 November 2026.** Acuan: [PRD](PRD.md), [arsitektur](ARCHITECTURE.md), [DDL](ERD.sql), [UI](UI_SPEC.md), [handoff](HANDOFF.md). Prefix tunggal `/api/v1`. Kontrak ini untuk implementasi Antigravity; contoh adalah fixture SIMULASI, bukan informasi bencana aktual. Nama final `is_simulated`, `priority_algo`, `priority_reasons`, `zone_version`, `since_sequence` menggantikan istilah rancangan sebelumnya; tidak menyediakan alias ganda.

## 1. Aturan lintas endpoint

- HTTPS produksi; HTTP hanya development lokal. JSON UTF-8, UTC RFC3339 dengan `Z`, UUID string lowercase, angka finite, satuan km/jam/M sebagaimana kolom. Tidak menerima NaN/Infinity. ID contoh tetap UUID valid. Field nullable wajib hadir sebagai `null`, kecuali field yang secara eksplisit privat/khusus jenis DTO. Properti request tidak dikenal ditolak `422 VALIDATION_ERROR`; query tidak dikenal juga ditolak.
- Semua endpoint bisnis membutuhkan `Authorization: Bearer <token>`, kecuali register/login, health/ready dan signed media route yang dijelaskan di §8. GET tidak mempunyai body; contoh request GET ditulis sebagai URL/header, **jangan mengirim `{}`**. Error memakai envelope tunggal §2. Respons sukses object memakai `data`; list memakai `items` dan `page`; semuanya `meta`.
- `meta`: `server_time` UTC clock evaluasi, `mode` enum `production_live|local_live|simulation`, `is_simulated` boolean. Dalam simulation semua event/report/log bernilai true, dalam live false; request tidak boleh menentukan flag. Mode tidak berganti otomatis. Jam fixture hanya domain (evaluasi, cutoff zona, created/updated/read_at bisnis); service memasok timestamp domain secara konsisten, tidak mencampur default SQL now() dengan clock fixture. JWT, masa berlaku signed URL, lease, rate limit memakai jam dinding aktual. `meta.server_time` mengungkap jam evaluasi fixture; expiry kredensial tetap waktu aktual.
- Metadata tambahan radius/score: `evaluated_at` pada DTO, `zone_version` pada meta dan item relevan. Satu response memakai satu jam evaluasi dan snapshot zona; client membuang respons dari versi zona/filter lama. Source freshness di `meta.sources`: array dua sumber dengan `source`, `state=healthy|degraded|stale|unavailable`, `last_success_at` UTC/null, `last_attempt_at` UTC/null. Partial/failed/abandoned → degraded; >15 menit sejak sukses → stale mengungguli degraded; tanpa sukses/cache → unavailable. Bootstrap partial yang sudah punya cache namun belum sukses → degraded. Mode simulation tidak menyamar sebagai sumber live: fixture memberi metadata kesegaran eksplisit dengan banner SIMULASI.
- Pagination daftar: `limit` integer default 20, 1..50; `offset` default 0, >=0. `page={limit,offset,next_offset,has_more}`, `next_offset=null` bila habis. Ambil limit+1 untuk has_more; tidak ada total count mahal. Urutan selalu punya ID pemutus seri. Offset bukan snapshot: client dedup ID, refresh dari 0 jika data berubah. Peta memakai hard cap sendiri. Sync notifikasi memakai sequence, **tanpa offset**.
- Semua contoh JSON adalah bentuk wire valid; nilai waktu/ID ilustratif. Contoh endpoint yang memakai `EventSummary`, `ReportPrivate`, dll. mengikuti definisi DTO §3. Tabel schema bersifat normatif termasuk nullability/privasi; jangan serialize ORM langsung. `Cache-Control: no-store` untuk respons terautentikasi, auth, photo-url, signed media dan SSE. `X-Request-ID` server UUID pada semua respons dan sama dengan `request_id` error.
- SQL schema `siaga`. Semua writer zona/notifikasi lock `users` lalu `alert_zones`, urut UUID user, sampai commit. Semua error transaksi rollback. Detail storage/schema/traceback tidak dikirim ke client. Default HTTP error middleware FastAPI harus dinormalisasi, termasuk validation dan body terlalu besar.

### Autentikasi dan throttle

JWT HS256 (allowlist hanya HS256), `sub=user UUID`, `iss`, `aud`, `iat`, `exp`; validasi signature/issuer/audience/subject/expiry, lalu ambil `users.active` dan role dari DB. TTL dapat dikonfigurasi **`3600–604800` detik** (default **`604800`** / 7 hari), tanpa refresh/revocation MVP. Di mobile Flutter (`Tetap masuk` default aktif), token disimpan terenkripsi di `flutter_secure_storage` (tanpa password) dan dipulihkan via `GET /api/v1/me`. Logout lokal menutup kanal dan menghapus token tersimpan; token lama yang sudah diterbitkan tetap valid hingga expiry. Password Argon2, 10..128 karakter tanpa trim; email trim/lowercase, maksimal 254, valid format email. display_name trim 1..80 karakter. Provisioning admin hanya operator; register selalu citizen, role input ditolak.

`401` token hilang/invalid/expired, akun nonaktif atau login gagal; kirim `WWW-Authenticate: Bearer`. `403` token valid tetapi role/self-review/non-owner klaim dilarang. `404` objek privat tidak terlihat (termasuk foto/audit), tidak membocorkan keberadaannya. Mode guest bukan role SQL.

Limit satu instans: login 5/menit/IP, register 3/menit/IP, submit laporan 5/menit/user (termasuk replay), baca 120/menit/user, satu SSE aktif/user. Pelanggaran `429` dengan `Retry-After` detik integer >=1. Poll internal SSE bukan request HTTP tambahan user. Middleware mutation lain boleh memakai budget 120/menit/user yang sama; dua admin tetap ditentukan transaksi, bukan throttle. Counter in-memory reset restart; deployment MVP satu instans/proses, trust proxy dibatasi. `503` transient boleh retry GET dengan backoff, POST laporan hanya key+payload sama; keputusan moderasi tidak auto-retry.

## 2. Error envelope dan katalog

```json
{
  "code": "VALIDATION_ERROR",
  "message": "Radius harus 25, 50, atau 100 km.",
  "details": {
    "fields": [
      {
        "field": "radius_km",
        "code": "invalid_choice"
      }
    ]
  },
  "request_id": "90000000-0000-4000-8000-000000000001"
}
```

`message` teks Indonesia aman, bukan string SQL. `details` object atau null; jangan echo password/token/file/koordinat zona. Field error memakai path stabil. Aplikasi bercabang pada `code`, bukan message.

| HTTP | code final | Kondisi / details |
|---|---|---|
| 400 | MALFORMED_REQUEST | JSON tidak terurai, multipart boundary rusak, query parameter duplikat ambigu; details null. |
| 401 | AUTH_REQUIRED, INVALID_CREDENTIALS, TOKEN_INVALID, TOKEN_EXPIRED | Sesi/login; details null; jangan retry loop. |
| 403 | FORBIDDEN, SELF_REVIEW_FORBIDDEN, CLAIM_NOT_OWNED | Role, laporan sendiri, keputusan oleh non-pemegang klaim; details null. |
| 403 | MEDIA_SIGNATURE_INVALID, MEDIA_URL_EXPIRED | Signed media lokal tidak sah/kedaluwarsa; details null. |
| 404 | RESOURCE_NOT_FOUND, PHOTO_NOT_FOUND | Tidak ada/tidak berhak tahu; photo missing setelah akses report diperiksa. |
| 409 | EMAIL_ALREADY_REGISTERED | Email normalized telah ada; details null. |
| 409 | IDEMPOTENCY_CONFLICT | Key sama hash berbeda; details `{client_request_id}` hanya pemilik. |
| 409 | VERSION_CONFLICT, INVALID_TRANSITION | Moderasi; details `{current_version,current_status}` setelah otorisasi. |
| 409 | ZONE_REQUIRED | Operasi perhitungan butuh zona; details `{action:"setup_zone"}`. |
| 409 | CURSOR_OUT_OF_RANGE, CURSOR_USER_MISMATCH | Cursor numerik >high-water atau identitas beda; details `{action:"fetch_baseline"}`; tidak bocorkan sequence user lain. |
| 413 | FILE_TOO_LARGE, REQUEST_TOO_LARGE | JPEG >2097152 byte, body >3145728 byte; details `{max_bytes}`. |
| 415 | UNSUPPORTED_MEDIA_TYPE | Content-Type request salah, file bukan JPEG/signature non-JPEG. |
| 422 | VALIDATION_ERROR, INVALID_IMAGE | Tipe/range/enum/query/cursor malformed; JPEG signature benar tetapi decode invalid, >4096 px/sisi atau >16000000 piksel. |
| 429 | RATE_LIMITED, STREAM_LIMIT_REACHED | Retry-After wajib; details null. |
| 503 | SERVICE_UNAVAILABLE, STORAGE_UNAVAILABLE | DB/pool/service atau media adapter gagal; details null, Retry-After bila diketahui. |

Error tak terduga memakai `500 INTERNAL_ERROR` envelope sama, request_id, tanpa detail internal; bukan 503 untuk bug program. Cache BMKG stale/degraded tetap **200**, bukan 503 jika API+DB sehat. `ready` gagal memakai 503 envelope, `health` tidak memeriksa dependency.

## 3. Kamus DTO dan aturan evaluasi

### User, Zone, sumber dan kategori

`User`: `id:UUID`, `email:string`, `display_name:string`, `role:citizen|admin`, `has_zone:boolean`. Hanya akun sendiri, tanpa hash/counter internal. `Zone`: `id:UUID`, `latitude:number[-90,90]`, `longitude:number[-180,180)`, `radius_km:25|50|100`, `notify_earthquake:boolean`, `notify_weather:boolean`, `zone_version:integer>0`, `alert_eligible_since:UTC`, `updated_at:UTC`. Input menerima +180 lalu normalisasi -180. Tidak membatasi ke bbox Indonesia karena fixture bumi/antimeridian PRD wajib; UX awal berpusat Indonesia.

| Domain | Nilai wire/SQL | Label UI |
|---|---|---|
| Official source | BMKG_TEWS / BMKG_NOWCAST | BMKG — Gempa / BMKG — Cuaca |
| Report source (derived, bukan kolom SQL) | CITIZEN | Warga — ditinjau admin aplikasi (hanya verified) |
| Category | earthquake, flood, eruption, extreme_weather, haze_other | Gempa, Banjir, Erupsi, Cuaca Ekstrem, Kabut Asap/Lainnya |
| Event category | earthquake / extreme_weather saja | Sesuai sumber |
| Report status | pending / in_review / verified / rejected | Menunggu / Ditinjau / Ditinjau admin aplikasi / Ditolak |
| CAP status | Actual / Exercise / System / Test / Draft | Nilai sumber; live hanya Actual |
| CAP msg_type | Alert / Update / Cancel / Ack / Error | Nilai sumber; Ack/Error tidak aktif |
| CAP severity | Extreme / Severe / Moderate / Minor / Unknown | Teks sumber, bukan probabilitas |
| CAP urgency | Immediate / Expected / Future / Past / Unknown | Teks sumber |
| CAP certainty | Observed / Likely / Possible / Unlikely / Unknown | Teks sumber |

Nilai severity/urgency/certainty tak dikenal dinormalisasi `Unknown`, field absen null; nilai mentah hanya provenance internal. Status/msg_type tak dikenal ditolak ingest, bukan dibuat enum baru. Feed live dan detail publik menyaring status non-Actual; detail non-live tersembunyi 404. SIMULASI fixture tetap memakai Actual dengan flag true.

Identity ingest TEWS dikunci `SHA256("TEWS|" + UTC_timestamp + "|" + latitude_6 + "|" + longitude_6)` lowercase hex. UTC_timestamp selalu `YYYY-MM-DDTHH:MM:SS.ffffffZ` (enam digit mikrodetik); input presisi di atas mikrodetik ditolak, bukan dipotong diam-diam. Koordinat Decimal half-up enam desimal, -0→0, +180→-180 termasuk setelah rounding; signed fixed-point enam digit, tanpa tanda+ untuk positif. Nilai koordinat kanonik yang sama disimpan/dipakai key. Namespace SQL BMKG_TEWS, bukan nama file. CAP key identifier persis (bukan RSS guid); resolution references harus cocok sender/identifier/sent. Payload content_hash mengabaikan metadata first/last_seen dan clock pengambilan; identical content tidak menaikkan content_version. Konflik field satu siklus auto→terkini→dirasakan, null tidak menimpa field valid. Tidak fuzzy-merge revisi koordinat/waktu.

### EventSummary dan Priority

EventSummary selalu memiliki `id,source,category,title,occurred_at,latitude,longitude,is_simulated,content_version,lifecycle_status,priority` serta `cap` (object cuaca, null gempa). latitude/longitude boleh null untuk CAP tanpa geometri. `lifecycle_status` derived: gempa `current|historical|invalid_time`; CAP `active|scheduled|expired|cancelled|superseded|incomplete`. Untuk CAP precedence cancelled (termasuk pesan Cancel sendiri), superseded, incomplete (interval/references tak lengkap atau bukan Alert/Update), expired, scheduled, active. Gempa historical bila umur >24h; invalid_time bila >5 menit masa depan. Data gempa yang waktu/koordinat identitasnya invalid disisihkan saat ingest; magnitude null tetap dapat tersimpan.

`Priority`: `priority_algo:eq-priority-v1|cap-priority-v1`, `priority_score:number[0,100]|null` mentah, `priority_display:string|null` satu desimal half-up, `priority_label:ordinary|attention|high|information|unavailable`, `priority_reasons:Reason[]`, `components:object|null`, `match_method:point_distance|inside_polygon|near_polygon_sample|no_geometry`, `match_distance_km:number>=0|null`, `within_radius:boolean|null`, `evaluated_at:UTC`, `zone_version:integer>0`.

`Reason`: `{code:string,text:string,values:object}`. Code/urutan gempa tetap `distance_radius`, `magnitude`, `age`, `application_priority`; bila input skor hilang tambahkan `missing_data` sebelum application_priority. Values masing-masing `{distance_km,radius_km}`, `{magnitude}`, `{age_hours}`, `{priority_label}`, missing `{fields:[...]}`. Code/urutan CAP tetap `area`, `location_match`, `severity`, `urgency_certainty`, `validity`; values `{area_descriptions:[...]}`, `{match_method,match_distance_km,within_radius}`, `{severity}`, `{urgency,certainty}`, `{effective,expires,lifecycle_status}`. Array bersifat snapshot di log, dihitung ulang di detail. Warga tidak mempunyai Priority.

Gempa `P=clamp(1-d/r,0,1)`, `M=clamp(m/10,0,1)`, `T=clamp(1-max(0,age_hours)/24,0,1)`, `S=60P+25M+15T`. components `{p,m,t,age_hours,radius_km,magnitude}`. Label sebelum pembulatan: <35 ordinary, 35..<65 attention, >=65 high. Missing magnitude/waktu/koordinat atau waktu invalid → score/display/components null, unavailable. Jarak tetap boleh tersedia walau skor null. Kedalaman/potensi tidak memengaruhi skor. Contoh normatif frozen clock:

```json
{
  "priority_algo": "eq-priority-v1",
  "priority_score": 74.25,
  "priority_display": "74.3",
  "priority_label": "high",
  "priority_reasons": [
    {
      "code": "distance_radius",
      "text": "10 km dari titik pantau, radius 50 km",
      "values": {
        "distance_km": 10,
        "radius_km": 50
      }
    },
    {
      "code": "magnitude",
      "text": "Magnitudo 5",
      "values": {
        "magnitude": 5
      }
    },
    {
      "code": "age",
      "text": "Umur informasi 2 jam",
      "values": {
        "age_hours": 2
      }
    },
    {
      "code": "application_priority",
      "text": "Prioritas tinggi",
      "values": {
        "priority_label": "high"
      }
    }
  ],
  "components": {
    "p": 0.8,
    "m": 0.5,
    "t": 0.9166666666666666,
    "age_hours": 2,
    "radius_km": 50,
    "magnitude": 5
  },
  "match_method": "point_distance",
  "match_distance_km": 10,
  "within_radius": true,
  "evaluated_at": "2026-11-16T03:00:00Z",
  "zone_version": 1
}
```

Nowcast score/display/components selalu null. Untuk pesan **aktif dan cocok**, Extreme/Severe high, Moderate attention, Minor information, Unknown/null unavailable. Di luar radius/inactive → unavailable, lifecycle tetap tampil. `inside_polygon` jarak 0, `near_polygon_sample` minimum jarak seluruh centroid/vertex (bisa juga di luar radius), `no_geometry` jarak/within_radius null. Semua area diuji, boundary termasuk (1e-9 derajat), antimeridian unwrap. near_polygon_sample **bukan** jarak ke tepi atau irisan radius-poligon eksak. Semua distance Haversine R=6371.0088, cutoff inklusif r+0.000001 km, tidak dibulatkan untuk keputusan. `(0,179.9)` ke `(0,-179.9)` sekitar 22.239016 km → masuk radius25. Label skor adalah prioritas informasi, bukan risiko ilmiah; di luar radius bukan berarti aman.

`cap` pada list: `{severity,urgency,certainty,effective,expires,area_descriptions:string[]}`; semua enum/waktu dapat null kecuali effective yang memakai sent bila tidak ada. `EventDetail` menambah `source_url`, `first_seen_at`, `last_seen_at`, `earthquake` (object/null), `weather` (object/null), `areas:Area[]`, `references:Reference[]`. earthquake `{magnitude,depth_km,region,latitude_text,longitude_text,potential,felt,shakemap_url}` semuanya nullable. weather `{sender,sent,status,msg_type,language,cap_event,event_code,headline,description,web_url,lifecycle_complete}`; sender/sent/status/msg_type wajib, teks lain nullable. `Area={id,position,area_description,polygons}`; polygon `{id,position,geometry_valid,centroid_latitude,centroid_longitude,south,north,west,east,crosses_antimeridian,vertices:[{sequence,latitude,longitude}]}`; geometri invalid bbox/centroid/flag null, vertices hanya koordinat valid, UI tidak menggambarnya. `Reference={relation_type,referenced_source_key,referenced_event_id}`; ID nullable. Raw provenance/hash tidak publik. Payload polygon hanya detail, tidak list/marker. Laporan terkait diambil terpisah dengan `event_id`.

### Report, Verification, Notification

`ReportPublic`: `id,source="CITIZEN",event_id:UUID|null,category,description,latitude,longitude,status="verified",verified_at:UTC,has_photo:boolean,is_simulated,created_at:UTC,match_distance_km:number|null`. `ReportPrivate` berisi field umum yang sama, status empat nilai dan verified_at nullable; ditambah `reporter_id`, `reviewer_id:UUID|null`, `version`, `client_request_id`, `payload_hash`, `payload_hash_algo`, `claimed_at:UTC|null`, `decided_at:UTC|null`, `latest_reason:string|null`, `updated_at`. Pemilik/admin selalu mendapat Private, akun lain verified mendapat Public. Tidak ada email/display_name pelapor, object key, signed URL atau audit di list. Foto lewat endpoint khusus. `match_distance_km=null` bila akun belum punya zona pada detail/Saya/Tinjau.

`Verification`: semua kolom tabel audit (`id,report_id,moderator_id,from_status,to_status,reason,resulting_version,created_at`), hanya pemilik/admin. `Notification`: `id,event_id,kind="official_new",sequence,zone_version,priority_algo,priority_score,priority_label,priority_reasons,priority_components,match_method,match_distance_km,evaluated_at,created_at,read_at,is_simulated` dari log; tambahan derived `title`, `event_category`, `current_lifecycle_status`, `present_as_active_alert`. Yang terakhir true hanya bila status event saat delivery masih layak (gempa <=24 jam/tidak invalid, CAP Actual aktif), bukan snapshot lama; cache sumber gagal tidak otomatis membatalkan log. Read_at bukan cursor. Snapshot alasan tidak ditimpa zona baru. Logs tidak dipangkas otomatis.

Pemetaan derived ke SQL: User.has_zone=EXISTS alert_zones; Report.verified_at=decided_at hanya jika verified, has_photo=(photo_object_key IS NOT NULL), latest_reason=reason audit dengan resulting_version terbesar atau null. Report.source=CITIZEN dan match_distance_km dihitung, bukan kolom report. Priority dihitung per zona dari event/area/vertices; components Event DTO disalin ke notification_logs.priority_components saat penerbitan. Notification.title/event_category/current_lifecycle_status dari event saat dibaca; alasan/zone_version tetap snapshot. unread_count=COUNT log read_at IS NULL; page/meta adalah hasil query, bukan tabel tambahan.

## 4. Auth dan akun

### POST /api/v1/auth/register

Anonim; JSON `{email,password,display_name}` wajib. Server normalisasi email/nama, hash password, INSERT users citizen lalu issue token sesudah commit. `201`; email duplicate409, validasi422, malformed400, throttle429, DB503. Tidak membuat zona; retry register bukan idempoten, arahkan login jika respons hilang.

```json
{
  "email": "warga@example.test",
  "password": "ContohSandiDemo123!",
  "display_name": "Warga Demo"
}
```

```json
{
  "data": {
    "access_token": "contoh-token-bukan-kredensial",
    "token_type": "bearer",
    "expires_in": 604800,
    "expires_at": "2026-11-23T03:00:00Z",
    "user": {
      "id": "10000000-0000-4000-8000-000000000001",
      "email": "warga@example.test",
      "display_name": "Warga Demo",
      "role": "citizen",
      "has_zone": false
    }
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### POST /api/v1/auth/login

Anonim; JSON email/password wajib; generik INVALID_CREDENTIALS401 untuk email/password salah atau inactive. `200` Auth DTO sama register (has_zone aktual); tidak mutasi akun/zona, bukan sesi DB. 400/415/422/429/503 umum.

```json
{
  "email": "warga@example.test",
  "password": "ContohSandiDemo123!"
}
```

```json
{
  "data": {
    "access_token": "contoh-token-bukan-kredensial",
    "token_type": "bearer",
    "expires_in": 604800,
    "expires_at": "2026-11-23T03:00:00Z",
    "user": {
      "id": "10000000-0000-4000-8000-000000000001",
      "email": "warga@example.test",
      "display_name": "Warga Demo",
      "role": "citizen",
      "has_zone": true
    }
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### GET /api/v1/me

Request `GET /api/v1/me` + Bearer; citizen/admin, akun sendiri. `200 User`, SELECT users+zone existence; 401/429/503. Tidak ada endpoint logout/refresh/ubah-role.

```json
{
  "data": {
    "id": "10000000-0000-4000-8000-000000000001",
    "email": "warga@example.test",
    "display_name": "Warga Demo",
    "role": "citizen",
    "has_zone": true
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

## 5. Zona pantau

### GET /api/v1/me/zone

Request `GET /api/v1/me/zone` + Bearer; sendiri. `200 data:Zone|null` (belum setup bukan404), read-only; 401/429/503.

```json
{
  "data": {
    "id": "20000000-0000-4000-8000-000000000001",
    "latitude": -7.25,
    "longitude": 112.75,
    "radius_km": 50,
    "notify_earthquake": true,
    "notify_weather": true,
    "zone_version": 1,
    "alert_eligible_since": "2026-11-16T00:00:00Z",
    "updated_at": "2026-11-16T00:00:00Z"
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### PUT /api/v1/me/zone

Bearer citizen/admin; full replacement lima field di bawah wajib (UI default radius50, toggle true). `200 Zone` baik create/update. No-op nilai kanonik sama tidak menaikkan versi/cutoff; perubahan nyata increments zone_version (create=1), cutoff/update waktu server. Serial lock users → zona, last committed PUT menang; tidak ada expected_version untuk zona. Return server snapshot, refetch feed setelah sukses. Tidak memproduksi backlog/notifikasi; toggle bukan filter feed. 400/401/415/422/429/503. Field version/cutoff/id input ditolak422.

```json
{
  "latitude": -7.25,
  "longitude": 112.75,
  "radius_km": 25,
  "notify_earthquake": true,
  "notify_weather": false
}
```

```json
{
  "data": {
    "id": "20000000-0000-4000-8000-000000000001",
    "latitude": -7.25,
    "longitude": 112.75,
    "radius_km": 25,
    "notify_earthquake": true,
    "notify_weather": false,
    "zone_version": 2,
    "alert_eligible_since": "2026-11-16T03:00:00Z",
    "updated_at": "2026-11-16T03:00:00Z"
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### GET /api/v1/locations/search

Bearer citizen/admin. Query `q` (wajib, `2..100` karakter) dan `limit` (`1..10`, default `6`). Pada mode live mencoba OpenStreetMap Nominatim (`countrycodes=id`, throttle 1 req/dtk, cache TTL 15 menit) dan otomatis jatuh ke daftar lokal terkurasi (`LOCAL_FALLBACK`) bila timeout/error; pada `simulation` memakai `LOCAL_FALLBACK`. `200 Envelope[LocationSearchData]`; 401/422/429/503.

```json
{
  "data": {
    "items": [
      {
        "label": "Bandung",
        "subtitle": "Jawa Barat",
        "latitude": -6.9175,
        "longitude": 107.6191,
        "source": "LOCAL_FALLBACK"
      }
    ]
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### GET /api/v1/me/weather

Bearer citizen/admin; zona wajib (`409 ZONE_REQUIRED` bila belum diatur). Mengambil ringkasan cuaca saat ini untuk koordinat zona dari Open-Meteo (cache TTL 10 menit). Bila penyedia timeout/error atau mode `simulation`, tetap mengembalikan `200` dengan `data: null` (non-blocking). 401/409/429/503.

```json
{
  "data": {
    "temperature_c": 27.5,
    "humidity_percent": 78,
    "precipitation_mm": 0.2,
    "wind_speed_kmh": 8.4,
    "weather_code": 3,
    "condition_code": "cloudy",
    "condition_label": "Berawan",
    "observed_at": "2026-11-26T04:00",
    "source": "OPEN_METEO",
    "is_cached": false
  },
  "meta": {
    "server_time": "2026-11-26T04:00:00Z",
    "mode": "local_live",
    "is_simulated": false
  }
}
```

## 6. Event dan peta

### GET /api/v1/events

Bearer citizen/admin, zona wajib termasuk Semua agar alasan personal konsisten (409 ZONE_REQUIRED). Query `category=earthquake|extreme_weather` opsional (absen=campuran), `radius_only=true` default, `weather_status=active|all` default active, `sort=recent|priority` default recent, `limit/offset`. `sort=priority` hanya category earthquake, selain itu422. Semua=`radius_only=false`; weather_status=all hanya di Semua (422 bila radius_only=true). Scope gempa list 7 hari terakhir, Detail tetap bisa event lama. Live non-Actual tidak tampil; CAP all mencakup scheduled/expired/cancelled/superseded/incomplete. Filter radius lebih dahulu; no_geometry tidak masuk Sekitar. Gempa sort recent occurred_at DESC,id DESC; priority score DESC NULLS LAST,occurred_at DESC,id DESC. Cuaca saja: active dahulu kemudian occurred_at DESC,id DESC; campuran waktu DESC,id DESC, **tidak** mencampur skor dengan severity.

Read-only cache DB, tidak fetch BMKG. `200 items:EventSummary[]`; 401/409/422/429/503. Contoh request `GET /api/v1/events?category=earthquake&radius_only=true&limit=20&offset=0` + Bearer. Fixture ini magnitude hilang untuk mengunci null semantics (reason list tetap lengkap).

```json
{
  "items": [
    {
      "id": "30000000-0000-4000-8000-000000000001",
      "source": "BMKG_TEWS",
      "category": "earthquake",
      "title": "SIMULASI — Gempa contoh",
      "occurred_at": "2026-11-16T01:00:00Z",
      "latitude": -7.25,
      "longitude": 112.75,
      "is_simulated": true,
      "content_version": 1,
      "lifecycle_status": "current",
      "cap": null,
      "priority": {
        "priority_algo": "eq-priority-v1",
        "priority_score": null,
        "priority_display": null,
        "priority_label": "unavailable",
        "priority_reasons": [
          {
            "code": "distance_radius",
            "text": "Di titik pantau, radius 50 km",
            "values": {
              "distance_km": 0,
              "radius_km": 50
            }
          },
          {
            "code": "magnitude",
            "text": "Magnitudo belum tersedia",
            "values": {
              "magnitude": null
            }
          },
          {
            "code": "age",
            "text": "Umur 2 jam",
            "values": {
              "age_hours": 2
            }
          },
          {
            "code": "missing_data",
            "text": "Prioritas belum tersedia",
            "values": {
              "fields": [
                "magnitude"
              ]
            }
          },
          {
            "code": "application_priority",
            "text": "Prioritas belum tersedia",
            "values": {
              "priority_label": "unavailable"
            }
          }
        ],
        "components": null,
        "match_method": "point_distance",
        "match_distance_km": 0,
        "within_radius": true,
        "evaluated_at": "2026-11-16T03:00:00Z",
        "zone_version": 1
      }
    }
  ],
  "page": {
    "limit": 20,
    "offset": 0,
    "next_offset": null,
    "has_more": false
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true,
    "zone_version": 1,
    "sources": [
      {
        "source": "BMKG_TEWS",
        "state": "healthy",
        "last_success_at": "2026-11-16T03:00:00Z",
        "last_attempt_at": "2026-11-16T03:00:00Z"
      },
      {
        "source": "BMKG_NOWCAST",
        "state": "stale",
        "last_success_at": "2026-11-16T02:40:00Z",
        "last_attempt_at": "2026-11-16T02:55:00Z"
      }
    ]
  }
}
```

### GET /api/v1/events/{event_id}

Bearer citizen/admin, zona wajib. Request `GET /api/v1/events/30000000-0000-4000-8000-000000000002`; read-only `200 EventDetail`; 401/404/409/422/429/503. Event expired tetap dapat dibuka; source hidden/non-Actual404. Contoh CAP expired tanpa geometri, bukan marker fiktif. Meta sources wajib pada detail seperti feed.

```json
{
  "data": {
    "id": "30000000-0000-4000-8000-000000000002",
    "source": "BMKG_NOWCAST",
    "category": "extreme_weather",
    "title": "SIMULASI — Peringatan cuaca",
    "occurred_at": "2026-11-16T00:00:00Z",
    "latitude": null,
    "longitude": null,
    "is_simulated": true,
    "content_version": 1,
    "lifecycle_status": "expired",
    "cap": {
      "severity": "Severe",
      "urgency": "Immediate",
      "certainty": "Observed",
      "effective": "2026-11-16T00:00:00Z",
      "expires": "2026-11-16T02:00:00Z",
      "area_descriptions": [
        "Area contoh"
      ]
    },
    "priority": {
      "priority_algo": "cap-priority-v1",
      "priority_score": null,
      "priority_display": null,
      "priority_label": "unavailable",
      "priority_reasons": [
        {
          "code": "area",
          "text": "Area contoh",
          "values": {
            "area_descriptions": [
              "Area contoh"
            ]
          }
        },
        {
          "code": "location_match",
          "text": "Kecocokan lokasi belum tersedia",
          "values": {
            "match_method": "no_geometry",
            "match_distance_km": null,
            "within_radius": null
          }
        },
        {
          "code": "severity",
          "text": "Severe",
          "values": {
            "severity": "Severe"
          }
        },
        {
          "code": "urgency_certainty",
          "text": "Immediate / Observed",
          "values": {
            "urgency": "Immediate",
            "certainty": "Observed"
          }
        },
        {
          "code": "validity",
          "text": "Peringatan telah kedaluwarsa",
          "values": {
            "effective": "2026-11-16T00:00:00Z",
            "expires": "2026-11-16T02:00:00Z",
            "lifecycle_status": "expired"
          }
        }
      ],
      "components": null,
      "match_method": "no_geometry",
      "match_distance_km": null,
      "within_radius": null,
      "evaluated_at": "2026-11-16T03:00:00Z",
      "zone_version": 1
    },
    "source_url": "https://www.bmkg.go.id/alerts/nowcast/id",
    "first_seen_at": "2026-11-16T00:01:00Z",
    "last_seen_at": "2026-11-16T02:40:00Z",
    "earthquake": null,
    "weather": {
      "sender": "fixture@example.test",
      "sent": "2026-11-16T00:00:00Z",
      "status": "Actual",
      "msg_type": "Alert",
      "language": "id-ID",
      "cap_event": "Cuaca ekstrem contoh",
      "event_code": null,
      "headline": "SIMULASI",
      "description": "Snapshot historis untuk demo.",
      "web_url": null,
      "lifecycle_complete": true
    },
    "areas": [
      {
        "id": "31000000-0000-4000-8000-000000000001",
        "position": 1,
        "area_description": "Area contoh",
        "polygons": []
      }
    ],
    "references": []
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true,
    "zone_version": 1,
    "sources": [
      {
        "source": "BMKG_TEWS",
        "state": "healthy",
        "last_success_at": "2026-11-16T03:00:00Z",
        "last_attempt_at": "2026-11-16T03:00:00Z"
      },
      {
        "source": "BMKG_NOWCAST",
        "state": "stale",
        "last_success_at": "2026-11-16T02:40:00Z",
        "last_attempt_at": "2026-11-16T02:55:00Z"
      }
    ]
  }
}
```

Fixture tambahan Priority CAP (proyeksi field berikut; implementasi tetap mengirim DTO penuh):

```json
[
  {
    "match_method": "inside_polygon",
    "match_distance_km": 0,
    "within_radius": true,
    "lifecycle_status": "active",
    "priority_algo": "cap-priority-v1",
    "priority_score": null,
    "priority_label": "high",
    "severity": "Severe"
  },
  {
    "match_method": "near_polygon_sample",
    "match_distance_km": 12.5,
    "within_radius": true,
    "lifecycle_status": "active",
    "priority_algo": "cap-priority-v1",
    "priority_score": null,
    "priority_label": "attention",
    "severity": "Moderate"
  },
  {
    "match_method": "near_polygon_sample",
    "match_distance_km": 120,
    "within_radius": false,
    "lifecycle_status": "active",
    "priority_algo": "cap-priority-v1",
    "priority_score": null,
    "priority_label": "unavailable",
    "severity": "Severe"
  },
  {
    "match_method": "no_geometry",
    "match_distance_km": null,
    "within_radius": null,
    "lifecycle_status": "incomplete",
    "priority_algo": "cap-priority-v1",
    "priority_score": null,
    "priority_label": "unavailable",
    "severity": "Unknown"
  }
]
```

### GET /api/v1/map/markers

Bearer citizen/admin, zona wajib. Query `category` opsional kelima kategori, `radius_only` default true, `include_reports` default true, `bbox=west,south,east,north` opsional. West/east [-180,180], south/north [-90,90], south<=north; west>east berarti antimeridian; -180/180 bbox dunia diizinkan sebagai batas query (bukan longitude tersimpan). Jangan memakai limit/offset; hard cap **100 total**. Filter radius dan viewport sebelum cap; pilih match_distance_km ASC, waktu DESC,id DESC (UUID global unik operasional). Gempa 7 hari, cuaca aktif, warga verified; no_geometry tidak punya marker. Bbox menguji **koordinat marker**; CAP membership radius tetap semua polygon, marker representatif bisa di luar viewport. Perluasan viewport/refilter untuk melihatnya; peta tidak mengklaim seluruh polygon terlihat.

`200 {items:Marker[],truncated:boolean,cap:100,meta}`; Marker `{id,kind:event|report,source,category,title,latitude,longitude,match_method,match_distance_km,priority_label:null|enum,is_simulated,magnitude:null|number,depth_km:null|number,potential:null|string}`. Field `magnitude`/`depth_km`/`potential` terisi untuk marker gempa (`BMKG_TEWS`) bila tersedia, dan `null` untuk cuaca ekstrem maupun laporan warga (warga juga `match_method=point_distance`, `priority_label=null`). Tidak ada polygon/foto/full priority. 401/409/422/429/503. Request `GET /api/v1/map/markers?bbox=112,-8,114,-6&radius_only=true&include_reports=true` + Bearer.

```json
{
  "items": [
    {
      "id": "30000000-0000-4000-8000-000000000001",
      "kind": "event",
      "source": "BMKG_TEWS",
      "category": "earthquake",
      "title": "SIMULASI — Gempa contoh",
      "latitude": -7.25,
      "longitude": 112.75,
      "match_method": "point_distance",
      "match_distance_km": 0,
      "priority_label": "unavailable",
      "is_simulated": true,
      "magnitude": 5.2,
      "depth_km": 10.0,
      "potential": "Tidak berpotensi TSUNAMI"
    }
  ],
  "truncated": false,
  "cap": 100,
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true,
    "zone_version": 1,
    "sources": [
      {
        "source": "BMKG_TEWS",
        "state": "healthy",
        "last_success_at": "2026-11-16T03:00:00Z",
        "last_attempt_at": "2026-11-16T03:00:00Z"
      },
      {
        "source": "BMKG_NOWCAST",
        "state": "stale",
        "last_success_at": "2026-11-16T02:40:00Z",
        "last_attempt_at": "2026-11-16T02:55:00Z"
      }
    ]
  }
}
```

## 7. Laporan warga dan idempotensi

### POST /api/v1/reports

Bearer citizen/admin; `multipart/form-data`. Field wajib `client_request_id:UUID`, `category`, `description` trim20..1000, `latitude`, `longitude`; opsional `event_id:UUID` dan satu part `photo` MIME image/jpeg. Absen event_id=null; jangan kirim string "null". Tanpa foto tidak memanggil storage. Tidak menerima reporter/status/reviewer/version/is_simulated/payload_hash dari client. **payload_hash dihitung server**, karena client tidak mengetahui byte hasil sanitasi server. Key UUID dibuat sekali per draft final dan dipertahankan bersama byte foto pada retry; edit payload menghasilkan key baru.

Contoh request HTTP (nilai field setara JSON di bawah; JSON hanya dokumentasi nilai, bukan body endpoint):

```http
POST /api/v1/reports HTTP/1.1
Authorization: Bearer <token>
Content-Type: multipart/form-data; boundary=demo-boundary

--demo-boundary
Content-Disposition: form-data; name="client_request_id"

50000000-0000-4000-8000-000000000001
--demo-boundary
Content-Disposition: form-data; name="category"

flood
--demo-boundary
Content-Disposition: form-data; name="description"

SIMULASI genangan terlihat di jalan utama.
--demo-boundary
Content-Disposition: form-data; name="latitude"

-7.25
--demo-boundary
Content-Disposition: form-data; name="longitude"

112.75
--demo-boundary--
```

```json
{
  "client_request_id": "50000000-0000-4000-8000-000000000001",
  "category": "flood",
  "description": "SIMULASI genangan terlihat di jalan utama.",
  "latitude": -7.25,
  "longitude": 112.75
}
```

File <=**2097152 byte**, total body termasuk multipart overhead <=**3145728 byte**, cek streaming byte aktual walau tanpa Content-Length. Satu file opsional, part ganda/field berulang ambigu400. Input sisi <=4096, luas <=16000000; bomb/invalid decode422, signature atau MIME non-JPEG415. Client max1024px/JPEG~75%, server decode/re-encode lagi max1024, JPEG75 tanpa EXIF/GPS/ICC/comment, RGB, orientation diterapkan sebelum membuang metadata. Hasil byte juga <=2MiB atau413; tidak membuang foto diam-diam.

**report-payload-v1 (server):** normalize description dengan Unicode NFC lalu trim whitespace Unicode; lat/lon Decimal dari teks, finite range dahulu, half-up **6 desimal**, -0→0, +180→-180 (setelah rounding juga), persist nilai kanonik yang sama. Untuk menyelaraskan SQL btrim, hasil trim service tidak menyisakan whitespace tepi. UUID lowercase. Foto pipeline deterministik: Pillow pin versi, exif_transpose → RGB (alpha tidak diterima karena JPEG), thumbnail LANCZOS tanpa upscale max1024, JPEG quality75, subsampling2, optimize=false, progressive=false, metadata kosong. photo_sha256 SHA256 byte hasil, null bila absen. Hash UTF-8 JSON dengan key sort lexicographic, separators `,`/`:`, ensure_ascii=false, tepat object `{algo:"report-payload-v1",category,description,event_id:null|UUID,latitude:"-7.250000",longitude:"112.750000",photo_sha256:null|hex}`. Hash tidak mencakup key/requester/timestamp. Pin sanitizer/encoder selama MVP; perubahan versi memerlukan strategi kompatibilitas retry dan kontrak baru, bukan berubah diam-diam.

Validasi+hash dahulu, lookup `(reporter_id,client_request_id)`: hash sama → **200** laporan yang sama dengan state terkini (dapat sudah dimoderasi), `Idempotent-Replay: true`; hash berbeda → **409 IDEMPOTENCY_CONFLICT**. Baru → upload objek privat acak → INSERT pending/version1 → commit → **201**, `Location: /api/v1/reports/{id}`, `Idempotent-Replay:false`. Unique race loser membaca winner lalu banding hash; hapus hanya objek loser yang tak direferensikan. Commit ambigu → lookup key setelah DB pulih sebelum delete; error503 tetap retry key sama. Cleanup gagal dicatat SQL/reconciliation saat DB sehat, inventory >24jam dan bukan in-flight. Tidak ada audit submit awal atau alert warga. Rate limit berlaku pada retry. 400/401/404(event tersembunyi/tidak ada)/409/413/415/422/429/503.

Contoh 201 (200 replay DTO sama, ID tidak berubah; hash ilustratif 64 hex):

```json
{
  "data": {
    "id": "40000000-0000-4000-8000-000000000001",
    "source": "CITIZEN",
    "event_id": null,
    "category": "flood",
    "description": "SIMULASI genangan terlihat di jalan utama.",
    "latitude": -7.25,
    "longitude": 112.75,
    "status": "pending",
    "verified_at": null,
    "has_photo": false,
    "is_simulated": true,
    "created_at": "2026-11-16T03:00:00Z",
    "match_distance_km": 0,
    "reporter_id": "10000000-0000-4000-8000-000000000001",
    "reviewer_id": null,
    "version": 1,
    "client_request_id": "50000000-0000-4000-8000-000000000001",
    "payload_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "payload_hash_algo": "report-payload-v1",
    "claimed_at": null,
    "decided_at": null,
    "latest_reason": null,
    "updated_at": "2026-11-16T03:00:00Z"
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### GET /api/v1/reports

Bearer citizen/admin. Query `scope=nearby|mine|review|verified` default nearby; `category` kelima enum opsional; `status` opsional; `event_id` opsional; limit/offset. nearby=verified dalam radius (zona wajib409), mine=semua status milik sendiri, review=admin saja403 default pending+in_review (filter boleh salah satu, final ditolak422), verified=semua verified nasional untuk panel terkait (UI selalu menambah event_id bila dari Detail). Status nearby/verified hanya verified atau absen; mine semua empat nilai. event_id valid tetapi tidak ada → list kosong, bukan bocor private. nearby/mine/verified terbaru created_at DESC,id DESC; review tertua created_at ASC,id ASC. SELECT-only, 200; 401/403/409/422/429/503. List DTO Public/Private mengikuti pemilik/admin, **bukan** scope saja.

Request `GET /api/v1/reports?scope=verified&category=flood&limit=20&offset=0` + Bearer dari citizen lain:

```json
{
  "items": [
    {
      "id": "40000000-0000-4000-8000-000000000001",
      "source": "CITIZEN",
      "event_id": null,
      "category": "flood",
      "description": "SIMULASI genangan terlihat di jalan utama.",
      "latitude": -7.25,
      "longitude": 112.75,
      "status": "verified",
      "verified_at": "2026-11-16T03:05:00Z",
      "has_photo": false,
      "is_simulated": true,
      "created_at": "2026-11-16T03:00:00Z",
      "match_distance_km": 0
    }
  ],
  "page": {
    "limit": 20,
    "offset": 0,
    "next_offset": null,
    "has_more": false
  },
  "meta": {
    "server_time": "2026-11-16T03:06:00Z",
    "mode": "simulation",
    "is_simulated": true,
    "zone_version": 1
  }
}
```

### GET /api/v1/reports/{report_id}

Bearer; pemilik/admin semua status, orang lain verified saja. Request `GET /api/v1/reports/40000000-0000-4000-8000-000000000001`; read-only200 Public/Private, 401/404/422/429/503. Ditampilkan inline/bottom sheet UI-04/UI-03/UI-06, tidak membuat layar ketujuh. Contoh public:

```json
{
  "data": {
    "id": "40000000-0000-4000-8000-000000000001",
    "source": "CITIZEN",
    "event_id": null,
    "category": "flood",
    "description": "SIMULASI genangan terlihat di jalan utama.",
    "latitude": -7.25,
    "longitude": 112.75,
    "status": "verified",
    "verified_at": "2026-11-16T03:05:00Z",
    "has_photo": false,
    "is_simulated": true,
    "created_at": "2026-11-16T03:00:00Z",
    "match_distance_km": 0
  },
  "meta": {
    "server_time": "2026-11-16T03:06:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

## 8. Foto privat

### GET /api/v1/reports/{report_id}/photo-url

Bearer; otorisasi sama report detail (periksa dulu, termasuk pending→404 untuk orang lain), lalu foto ada atau404 PHOTO_NOT_FOUND. Request `GET /api/v1/reports/40000000-0000-4000-8000-000000000002/photo-url`. Read SQL+signed URL adapter, `200`, 401/404/422/429/503. Tidak simpan URL ke SQL/log. Tidak idempoten byte URL; setiap GET dapat menerbitkan URL berbeda, masing-masing TTL300 detik jam dinding. Contoh lokal:

```json
{
  "data": {
    "url": "http://10.0.2.2:8000/api/v1/media/reports/40000000-0000-4000-8000-000000000002/photo?expires=1794798480&signature=contoh-signature",
    "expires_at": "2026-11-16T03:08:00Z",
    "expires_in": 300,
    "content_type": "image/jpeg",
    "is_simulated": true
  },
  "meta": {
    "server_time": "2026-11-16T03:03:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### GET /api/v1/media/reports/{report_id}/photo (adapter lokal saja)

Request memakai URL **persis** dari photo-url, tanpa bearer header; query `expires` integer Unix seconds dan `signature` base64url HMAC-SHA256 key server media terpisah. Tanda tangan mengikat `GET`, canonical path/report UUID, object key tersimpan, expiry, dan namespace mode/storage; compare constant-time, expiry maksimum300 detik sejak penerbitan (verifikasi batas pada waktu GET), jam dinding. Response **200 image/jpeg bytes**, bukan JSON; `Content-Disposition:inline`, `X-Content-Type-Options:nosniff`, `Cache-Control:no-store`. Contoh sukses biner secara sengaja tidak diberi JSON palsu. 403 signature/expiry, 404 report/foto setelah signature sah, 422 malformed query, 503 storage. Error memakai envelope §2. File root privat dan path resolved dalam root; tidak menerima path/object key mentah client.

Supabase adapter mengembalikan signed URL storage langsung dengan TTL sama; respons error storage dapat berbeda, repository foto memperlakukannya sebagai image load failure lalu meminta photo-url baru **sekali**. Flutter `Image.network(url)` memakai capability URL; jangan melampirkan JWT FastAPI ke host storage. Pemegang URL dapat membaca hingga expiry meski logout/perubahan role; jangan share/cache/log URL. **Tidak ada JWT query-token** untuk foto bisnis maupun SSE. Header bearer dipakai untuk memperoleh capability; short-lived signature hanya untuk unduhan ini. Signature contoh bukan kredensial valid.

## 9. Moderasi dan audit

Semua aksi membutuhkan admin aktif, bukan pelapor. Expected_version integer>0 wajib. Urutan validasi: auth/role, load objek, self-review, lalu lock/conditional transition; version/status conflict409 sebelum pengecekan owner klaim pada keputusan in_review. Keputusan valid versi oleh non-holder403. Request gagal tidak mengubah status/audit. Trigger DDL menolak transisi/actor/audit tidak sesuai; service tetap otorisasi requester dan mengubah error domain secara terkontrol.

### POST /api/v1/reports/{report_id}/claim

Admin; pending+version cocok → in_review, reviewer=requester, claimed_at=server, version2. Reason audit server tetap **"Laporan diambil untuk ditinjau."**. Tidak menerima reason client untuk claim. `200 {id,status,reviewer_id,version,claimed_at,decided_at}` ringkas bernama `ModerationResult`; UI refetch detail untuk Private lengkap. 400/401/403/404/409/415/422/429/503. Bukan replay-idempoten: retry setelah sukses409; refetch untuk tahu pemegang klaim. Tidak ada reassignment/timeout otomatis.

Request `POST /api/v1/reports/40000000-0000-4000-8000-000000000001/claim`:

```json
{
  "expected_version": 1
}
```

```json
{
  "data": {
    "id": "40000000-0000-4000-8000-000000000001",
    "status": "in_review",
    "reviewer_id": "10000000-0000-4000-8000-000000000002",
    "version": 2,
    "claimed_at": "2026-11-16T03:01:00Z",
    "decided_at": null
  },
  "meta": {
    "server_time": "2026-11-16T03:01:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### POST /api/v1/reports/{report_id}/decision

Admin pemegang klaim; JSON expected_version, `outcome=verified|rejected`, `reason` NFC/trim10..500 wajib. in_review version2→final version3, decided_at server; report update + audit INSERT satu transaksi. Response `200 ModerationResult`; error sama claim, ditambah CLAIM_NOT_OWNED403. Skip/final/repeat409, audit gagal rollback seluruh transaksi503/500 sesuai sebab. Tidak auto-retry, reload setelah409.

Request `POST /api/v1/reports/40000000-0000-4000-8000-000000000001/decision`:

```json
{
  "expected_version": 2,
  "outcome": "verified",
  "reason": "Kondisi pada laporan telah ditinjau untuk demo."
}
```

```json
{
  "data": {
    "id": "40000000-0000-4000-8000-000000000001",
    "status": "verified",
    "reviewer_id": "10000000-0000-4000-8000-000000000002",
    "version": 3,
    "claimed_at": "2026-11-16T03:01:00Z",
    "decided_at": "2026-11-16T03:05:00Z"
  },
  "meta": {
    "server_time": "2026-11-16T03:05:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

```json
{
  "code": "VERSION_CONFLICT",
  "message": "Laporan telah berubah. Muat ulang sebelum melanjutkan.",
  "details": {
    "current_version": 3,
    "current_status": "verified"
  },
  "request_id": "90000000-0000-4000-8000-000000000002"
}
```

### GET /api/v1/reports/{report_id}/verifications

Pemilik atau admin (bukan admin-only karena pemilik berhak catatan); akun lain404 bahkan verified. `limit/offset`; resulting_version ASC,id ASC; `200 Verification[]`, 401/404/422/429/503. Pending items kosong. SELECT-only, append-only tanpa API update/delete audit. Request `GET /api/v1/reports/40000000-0000-4000-8000-000000000001/verifications?limit=20&offset=0`:

```json
{
  "items": [
    {
      "id": "60000000-0000-4000-8000-000000000001",
      "report_id": "40000000-0000-4000-8000-000000000001",
      "moderator_id": "10000000-0000-4000-8000-000000000002",
      "from_status": "pending",
      "to_status": "in_review",
      "reason": "Laporan diambil untuk ditinjau.",
      "resulting_version": 2,
      "created_at": "2026-11-16T03:01:00Z"
    },
    {
      "id": "60000000-0000-4000-8000-000000000002",
      "report_id": "40000000-0000-4000-8000-000000000001",
      "moderator_id": "10000000-0000-4000-8000-000000000002",
      "from_status": "in_review",
      "to_status": "verified",
      "reason": "Kondisi pada laporan telah ditinjau untuk demo.",
      "resulting_version": 3,
      "created_at": "2026-11-16T03:05:00Z"
    }
  ],
  "page": {
    "limit": 20,
    "offset": 0,
    "next_offset": null,
    "has_more": false
  },
  "meta": {
    "server_time": "2026-11-16T03:06:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

## 10. Notifikasi, baseline, catch-up dan SSE

Server menerbitkan hanya event resmi **baru** (unique user/event/official_new), zona aktif, toggle sesuai, first_seen_at **>** alert_eligible_since dan waktu sumber **>=** cutoff (TEWS occurred_at, CAP sent), cocok lokasi. Gempa umur<=24h dan tidak >5 menit masa depan; CAP Actual/lifecycle lengkap/aktif, references Update valid. Skor/magnitudo tersedia bukan syarat, severity Unknown tetap boleh. Bootstrap pertama setiap sumber tanpa alert sampai traversal awal selesai; pengayaan identity sama/perubahan zona/laporan warga tidak alert. Batas transaksi event+log+checkpoint atomik, counter users di-lock sampai commit. `priority_algo` di log harus sesuai source event, flag sesuai mode. Runtime hanya boleh UPDATE(read_at) pada log.

**Cursor milik akun:** wire sequence integer 0..9223372036854775807. 0 berarti belum menerima. REST selalu menyertakan `cursor_user_id` bersama `since_sequence`; dibandingkan sub JWT. Ini mendeteksi cursor akun lain meski angka sequence kebetulan sama. Jangan menganggap sequence numerik sendiri mengidentifikasi pemilik. SSE id berbentuk `<user_uuid>:<sequence>`, numeric suffix adalah sequence per-user. Client menyimpan keduanya di memori, scoped akun. Tidak ada cursor global/timestamp. Prefix dan numeric canonical tanpa leading zero (kecuali0). Bad format422, user beda409, >high-water409. Retensi utuh membuat gap dalam 1..high-water menjadi pelanggaran integritas server503, bukan diam-diam lompat.

### GET /api/v1/me/notifications

Bearer, sendiri; `limit/offset`, `unread_only=false` default boolean. Order sequence DESC,id DESC; `200 items:Notification[]`, `page`, `unread_count` total user belum dibaca, `meta`; read-only, 401/422/429/503. Request `GET /api/v1/me/notifications?limit=20&offset=0&unread_only=false`:

```json
{
  "items": [
    {
      "id": "70000000-0000-4000-8000-000000000001",
      "event_id": "30000000-0000-4000-8000-000000000001",
      "kind": "official_new",
      "sequence": 1,
      "zone_version": 1,
      "priority_algo": "eq-priority-v1",
      "priority_score": null,
      "priority_label": "unavailable",
      "priority_reasons": [
        {
          "code": "distance_radius",
          "text": "Di titik pantau, radius 50 km",
          "values": {
            "distance_km": 0,
            "radius_km": 50
          }
        },
        {
          "code": "magnitude",
          "text": "Magnitudo belum tersedia",
          "values": {
            "magnitude": null
          }
        },
        {
          "code": "age",
          "text": "Umur 2 jam",
          "values": {
            "age_hours": 2
          }
        },
        {
          "code": "missing_data",
          "text": "Prioritas belum tersedia",
          "values": {
            "fields": [
              "magnitude"
            ]
          }
        },
        {
          "code": "application_priority",
          "text": "Prioritas belum tersedia",
          "values": {
            "priority_label": "unavailable"
          }
        }
      ],
      "priority_components": null,
      "match_method": "point_distance",
      "match_distance_km": 0,
      "evaluated_at": "2026-11-16T03:00:00Z",
      "created_at": "2026-11-16T03:00:00Z",
      "read_at": null,
      "is_simulated": true,
      "title": "SIMULASI — Gempa contoh",
      "event_category": "earthquake",
      "current_lifecycle_status": "current",
      "present_as_active_alert": true
    }
  ],
  "page": {
    "limit": 20,
    "offset": 0,
    "next_offset": null,
    "has_more": false
  },
  "unread_count": 1,
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### POST /api/v1/me/notifications/{notification_id}/read

Bearer pemilik, lainnya404. Body `{}`; unknown field422. `200 {id,read_at}`; UPDATE read_at=COALESCE(read_at,server_now) pertama kali saja, sehingga replay idempoten. Cursor tidak berubah; unread_count refresh histori. 400/401/404/415/422/429/503. Endpoint tambahan ini mewujudkan mark-read yang sudah diwajibkan PRD/HANDOFF, bukan fitur baru.

Request `POST /api/v1/me/notifications/70000000-0000-4000-8000-000000000001/read`:

```json
{}
```

```json
{
  "data": {
    "id": "70000000-0000-4000-8000-000000000001",
    "read_at": "2026-11-16T03:06:00Z"
  },
  "meta": {
    "server_time": "2026-11-16T03:06:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### GET /api/v1/me/notifications/sync

Bearer sendiri. Dua mode mutually exclusive:

1. `baseline=true` tanpa since_sequence/cursor_user_id/limit. `200 items:[]`, high_water_mark dari users dalam snapshot konsisten, next_sequence=high_water_mark, has_more=false. **Tidak** mengubah read_at. Login baru: baseline dahulu, baru fetch history, baru buka SSE dari baseline; record history yang overlap stream didedup tanpa mengabaikan record baru setelah baseline.
2. `since_sequence=N&cursor_user_id=UUID&limit=20` (1..50; baseline absen/false). Capture high_water_mark dan rows dalam transaksi read-only snapshot yang sama (REPEATABLE READ, singkat), ambil `N < sequence <= high_water_mark` ASC. next_sequence=sequence terakhir item atau N bila kosong; has_more=(next_sequence<high_water_mark). Sampai has_more=false, client lanjut next_sequence. High-water boleh bertambah antar batch; tidak ada lompatan tanpa item. Jangan memegang snapshot sepanjang SSE.

Read-only. `200 {items:Notification[],cursor_user_id,high_water_mark,next_sequence,has_more,meta}`. 401/409(cursor)/422/429/503. Contoh request `GET /api/v1/me/notifications/sync?baseline=true`:

```json
{
  "items": [],
  "cursor_user_id": "10000000-0000-4000-8000-000000000001",
  "high_water_mark": 1,
  "next_sequence": 1,
  "has_more": false,
  "meta": {
    "server_time": "2026-11-16T03:06:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

Contoh catch-up sudah menyamai high-water: `GET /api/v1/me/notifications/sync?since_sequence=1&cursor_user_id=10000000-0000-4000-8000-000000000001&limit=20`:

```json
{
  "items": [],
  "cursor_user_id": "10000000-0000-4000-8000-000000000001",
  "high_water_mark": 1,
  "next_sequence": 1,
  "has_more": false,
  "meta": {
    "server_time": "2026-11-16T03:06:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

Gap recovery: sequence loncat atau cursor409 → tutup kanal, jangan advance cursor. Untuk gap delivery, ulang sync dari last_received yang sah; jika409 persisted fetch baseline secara eksplisit, refresh history dan tampilkan “Riwayat disinkronkan ulang”, tanpa popup histori. Baseline baru berarti sesi menerima batas baru secara sadar, bukan silent skip. Integritas log503 harus diperbaiki server, jangan baseline untuk menutupi log hilang.

### GET /api/v1/me/notifications/stream

Bearer melalui Flutter `http.Client.send` streaming (bukan browser EventSource tanpa header). Query `since_sequence`+`cursor_user_id` wajib kecuali header `Last-Event-ID` tersedia. Jika header ada, header **menang**, query cursor diabaikan, header tetap divalidasi penuh. Tanpa keduanya422, bukan baseline otomatis. Server hanya satu stream/user429 untuk kedua, tidak memutus diam-diam sesi pertama. Sebelum headers:401/409/422/429/503 JSON; setelah mulai stream, dependency error menutup koneksi (tidak mengirim JSON HTTP error di tengah framing). Token expiry menutup stream, client memeriksa expires_at lalu login; retry berujung401 tidak berulang.

```http
GET /api/v1/me/notifications/stream?since_sequence=0&cursor_user_id=10000000-0000-4000-8000-000000000001 HTTP/1.1
Authorization: Bearer <token>
Accept: text/event-stream
```

`200 Content-Type:text/event-stream; charset=utf-8`, `Cache-Control:no-store`, `X-Accel-Buffering:no`. Framing UTF-8, blank line terminator; parser mendukung CRLF, multi-data, potongan chunk dan komentar. `retry:3000` saran reconnect pertama 3s jitter±10%, bukan loop setelah401. Connected/heartbeat tidak mempunyai id dan **tidak memajukan cursor**. connected berisi high-water untuk informasi, client tetap replay dari since. Alert data adalah **Notification DTO lengkap** persis sync/history (tanpa meta wrapper). Contoh framing JSON valid per data line:

```sse
retry: 3000
event: connected
data: {"cursor_user_id":"10000000-0000-4000-8000-000000000001","since_sequence":0,"high_water_mark":1,"heartbeat_seconds":20,"is_simulated":true}

id: 10000000-0000-4000-8000-000000000001:1
event: alert
data: {"id":"70000000-0000-4000-8000-000000000001","event_id":"30000000-0000-4000-8000-000000000001","kind":"official_new","sequence":1,"zone_version":1,"priority_algo":"eq-priority-v1","priority_score":null,"priority_label":"unavailable","priority_reasons":[{"code":"distance_radius","text":"Di titik pantau, radius 50 km","values":{"distance_km":0,"radius_km":50}},{"code":"magnitude","text":"Magnitudo belum tersedia","values":{"magnitude":null}},{"code":"age","text":"Umur 2 jam","values":{"age_hours":2}},{"code":"missing_data","text":"Prioritas belum tersedia","values":{"fields":["magnitude"]}},{"code":"application_priority","text":"Prioritas belum tersedia","values":{"priority_label":"unavailable"}}],"priority_components":null,"match_method":"point_distance","match_distance_km":0,"evaluated_at":"2026-11-16T03:00:00Z","created_at":"2026-11-16T03:00:00Z","read_at":null,"is_simulated":true,"title":"SIMULASI — Gempa contoh","event_category":"earthquake","current_lifecycle_status":"current","present_as_active_alert":true}

: keepalive
event: heartbeat
data: {"server_time":"2026-11-16T03:00:20Z"}

```

Server replay ascending batch20 (internal max50), query log sekitar2s, release koneksi DB setiap query, heartbeat20s walau belum ada alert. Client timeout45s tanpa frame/heartbeat. Setelah dua gagal SSE, polling60/120/240/300s saat gagal, ±10%, reset60 saat sukses; probe SSE tiap5menit saat resumed/online. Pada probe hentikan poll aktif sebelum stream; gagal kembali polling. Pause/inactive membatalkan kanal, subscription, reconnect dan timer; resume catch-up REST sampai habis lalu SSE dari cursor terakhir (server replay menutup celah commit). At-least-once: advance last_received hanya setelah proses record, dedup notification UUID; ID OS lokal dipetakan stabil per UUID dengan collision handling dalam sesi. Catch-up maksimal satu ringkasan popup; expired/cancelled/superseded present_as_active_alert=false tidak popup sebagai alert aktif. Read_at hanya saat aksi baca. Tidak ada push ketika app mati/di-kill. Izin OS ditolak tetap banner/riwayat.

## 11. Operasional

### GET /api/v1/health

Anonim, tanpa body/query: `GET /api/v1/health`. `200 data.status=ok`; liveness proses, tidak menyentuh DB/storage/BMKG, tidak menampilkan versi server/DSN. Metadata mode minimal untuk banner login; schema tetap sama lokal/live. Tidak mengklaim dependencies sehat.

```json
{
  "data": {
    "status": "ok"
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

### GET /api/v1/ready

Anonim, tanpa body/query: `GET /api/v1/ready`. `200 ready` jika koneksi DB, revision migrasi dan konfigurasi/akses adapter storage siap. Pemeriksaan probe storage berkala terbatas di luar request menyimpan hasil maksimal60s, bukan membuat objek setiap probe; boot probe privat dibersihkan. Saat belum diperiksa/gagal→503 SERVICE_UNAVAILABLE envelope. BMKG offline/stale **tidak** menggagalkan ready bila cache/API hidup; sumber detail hanya meta.sources endpoint event. Tidak bocor nama DB, filesystem, atau detail dependency publik.

```json
{
  "data": {
    "status": "ready"
  },
  "meta": {
    "server_time": "2026-11-16T03:00:00Z",
    "mode": "simulation",
    "is_simulated": true
  }
}
```

```json
{
  "code": "SERVICE_UNAVAILABLE",
  "message": "Layanan belum siap. Coba lagi sebentar.",
  "details": null,
  "request_id": "90000000-0000-4000-8000-000000000003"
}
```

## 12. Pemetaan implementasi dan gate uji

| FR / AC | Endpoint atau worker / bukti wajib |
|---|---|
| FR-01; AC-01..03,24 | Auth/me/zone, input extra ditolak, email unik, role, finite/180/preset, no-op PUT; JWT expiry/IDOR/rate limit. |
| FR-02; AC-07,10,11,21 | Worker TEWS/CAP (tidak ada endpoint trigger): source_key/content_version, lease300/deadline240, timeout15 retry2/4s, bootstrap, checkpoint commit atomik; cache tetap200. |
| FR-03; AC-04..06,08,09,12 | events/detail/markers: frozen-clock, half-up74.25→74.3, null, inside/near/no-geometry, tepi/antimeridian/kutub, cutoff dan toggle. |
| FR-04; AC-13 | events/reports/list, peta100/truncated, limit51→422, detail tanpa halaman laporan baru. |
| FR-05; AC-14..16,22,24 | reports multipart/photo-url/media: ukuran actual, sanitasi EXIF, hash deterministik, race replay, private visibility dan expired URL, local simulation. |
| FR-06; AC-17,18 | claim/decision/verifications: dua koneksi PostgreSQL, satu pemenang, self403, final409, audit gagal rollback. |
| FR-07; AC-12,19..23 | notification history/read/sync/stream: serial commit counter, baseline race, cursor identitas, gap/reconnect, stop paused, stale replay, tanpa popup histori login baru. |

JSON manual Flutter/Pydantic v2 terpisah ORM; `bigint` dibaca Dart int Android, UUID string, UTC DateTime, nullable eksplisit. Stack pin mengikuti PRD/arsitektur; hasil wheel Python3.15 dari user bukan bukti runtime. Tidak memerlukan PostGIS atau C-extension GIS. DDL memakai fitur core PostgreSQL15 ([UUID](https://www.postgresql.org/docs/15/functions-uuid.html), [constraints](https://www.postgresql.org/docs/15/ddl-constraints.html), [constraint triggers](https://www.postgresql.org/docs/15/sql-createtrigger.html)). Runtime HTTP/SSE, Supabase/Railway, integrasi paket dan performa tetap gate build, bukan otomatis lulus karena kontrak terkunci.
