# Keuangan Kampus

Aplikasi dashboard administrasi keuangan kampus berbasis Flutter.

## Fitur Utama

- Dashboard responsif (desktop dan mobile)
- Sidebar navigasi untuk modul utama
- Ringkasan saldo buku, pemasukan, pengeluaran, dan selisih rekening
- Master jenis pembayaran (admin bisa tambah jenis baru + atur prasyarat)
- Validasi prasyarat pembayaran (contoh: UTS tidak bisa dibayar jika semester belum lunas)
- Input saldo output/pengeluaran (expo, penggajian, operasional)
- Laporan keuangan yang otomatis menyesuaikan sisa saldo
- Rekonsiliasi saldo buku dengan saldo rekening real
- Penyimpanan lokal offline (Sembast)
- Sinkronisasi ke API MySQL (opsional) via `API_BASE_URL` + `API_TOKEN`

## Menjalankan Project

1. Install Flutter SDK.
2. Jalankan:

```bash
flutter pub get
flutter run -d chrome
```

## Menjalankan Dengan Backend MySQL (Disarankan)

1. Masuk folder backend:

```bash
cd backend
copy .env.example .env
docker compose up -d --build
```

2. Jalankan Flutter dengan konfigurasi API:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080 --dart-define=API_TOKEN=dev-secret-token
```

Jika backend tidak aktif, aplikasi tetap jalan dengan penyimpanan lokal.

## Struktur Folder Utama

- `backend/` untuk API + MySQL + phpMyAdmin (Docker)
- `lib/data/` untuk penyimpanan lokal dan sinkronisasi API
- `lib/screens/` untuk layar utama
- `lib/widgets/` untuk komponen UI reusable
- `test/` untuk widget test
