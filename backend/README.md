# Backend Keuangan Kampus

Backend ini menyediakan API berbasis PHP + MySQL untuk sinkronisasi state aplikasi Flutter dan login dasar berbasis session token.

## Stack

- PHP 8.3 (Apache)
- MySQL 8.4
- phpMyAdmin
- Docker Compose

## Endpoint

- `GET /health`
- `POST /api/auth/login`
- `GET /api/auth/me`
- `POST /api/auth/logout`
- `POST /api/auth/change-password`
- `GET /api/users`
- `POST /api/users`
- `PUT /api/users/{id}`
- `GET /api/audit-logs`
- `GET /api/relational/status`
- `POST /api/relational/bootstrap`
- `GET /api/bank-mutations`
- `POST /api/bank-mutations/import`
- `POST /api/bank-mutations/{id}/approve`
- `POST /api/bank-mutations/{id}/reject`
- `GET /api/reports/summary`
- `GET /api/state`
- `PUT /api/state`

## Menjalankan

1. Salin env:

```bash
copy .env.example .env
```

2. Jalankan service:

```bash
docker compose up -d --build
```

3. Cek health API:

`http://localhost:8080/health`

4. Akses phpMyAdmin:

`http://localhost:8081`

## Akun Login Default

- Username: `admin`
- Password: `admin123`
- Role: `owner`
- Office: `default`

Ganti password admin secepatnya setelah environment stabil.

## Contoh Auth API

Login:

```bash
curl -X POST http://localhost:8080/api/auth/login ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"admin\",\"password\":\"admin123\"}"
```

Cek user aktif (`TOKEN` hasil login):

```bash
curl http://localhost:8080/api/auth/me -H "Authorization: Bearer TOKEN"
```

Logout:

```bash
curl -X POST http://localhost:8080/api/auth/logout -H "Authorization: Bearer TOKEN"
```

Ganti password sendiri:

```bash
curl -X POST http://localhost:8080/api/auth/change-password ^
  -H "Authorization: Bearer TOKEN" ^
  -H "Content-Type: application/json" ^
  -d "{\"currentPassword\":\"admin123\",\"newPassword\":\"passwordBaru123\"}"
```

List user (owner/admin):

```bash
curl http://localhost:8080/api/users -H "Authorization: Bearer TOKEN"
```

Ringkasan data dari `app_state`:

```bash
curl http://localhost:8080/api/reports/summary -H "Authorization: Bearer TOKEN"
```

Cek status tabel relasional:

```bash
curl http://localhost:8080/api/relational/status -H "Authorization: Bearer TOKEN"
```

Migrasi awal dari `app_state` ke tabel relasional:

```bash
curl -X POST http://localhost:8080/api/relational/bootstrap -H "Authorization: Bearer TOKEN"
```

Import mutasi bank (contoh JSON baris hasil parsing Excel/CSV):

```bash
curl -X POST http://localhost:8080/api/bank-mutations/import ^
  -H "Authorization: Bearer TOKEN" ^
  -H "Content-Type: application/json" ^
  -d "{\"sourceFile\":\"mutasi_feb.xlsx\",\"rows\":[{\"mutationDate\":\"2026-02-24 08:00:00\",\"description\":\"TRF 2301001 SPP\",\"amount\":1500000,\"isCredit\":true}]}"
```

Lihat daftar auto-match (hijau/kuning):

```bash
curl "http://localhost:8080/api/bank-mutations?status=matched&limit=100" -H "Authorization: Bearer TOKEN"
```

Approve hasil match:

```bash
curl -X POST http://localhost:8080/api/bank-mutations/123/approve -H "Authorization: Bearer TOKEN"
```

Setelah migrasi, data inti tersimpan di tabel:
- `finance_students`
- `finance_payment_types`
- `finance_payment_type_prerequisites`
- `finance_invoices`
- `finance_payments`
- `finance_cash_transactions`
- `finance_bank_mutations`

## Integrasi Flutter (Kompatibel Lama)

Mode lama dengan static bearer token tetap bisa dipakai:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080 --dart-define=API_TOKEN=dev-secret-token
```

Tanpa `API_BASE_URL`, aplikasi tetap memakai penyimpanan lokal.
