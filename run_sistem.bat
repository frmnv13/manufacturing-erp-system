@echo off
setlocal

set "ROOT=%~dp0"
set "API_BASE_URL=http://localhost:8080"
set "FLUTTER_DEVICE=chrome"

echo ==========================================
echo  Sistem Istri - Auto Run
echo ==========================================
echo Root      : %ROOT%
echo API       : %API_BASE_URL%
echo Device    : %FLUTTER_DEVICE%
echo.

where docker >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Docker tidak ditemukan di PATH.
  echo Jalankan Docker Desktop lalu pastikan command "docker" bisa dipakai.
  pause
  exit /b 1
)

where flutter >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Flutter tidak ditemukan di PATH.
  pause
  exit /b 1
)

if exist "%ROOT%backend\docker-compose.yml" (
  echo [1/2] Menjalankan backend Docker...
  pushd "%ROOT%backend"
  docker compose up -d
  if errorlevel 1 (
    echo.
    echo [ERROR] Gagal menjalankan docker compose.
    echo Pastikan Docker Desktop sudah running.
    popd
    pause
    exit /b 1
  )
  popd
) else (
  echo [WARN] File backend\docker-compose.yml tidak ditemukan, backend dilewati.
)

echo.
echo [2/2] Menjalankan Flutter di window baru...
start "Sistem Istri - Flutter" cmd /k "cd /d ""%ROOT%"" && flutter pub get && flutter run -d %FLUTTER_DEVICE% --dart-define=API_BASE_URL=%API_BASE_URL%"

echo.
echo Selesai. Jika window Flutter tidak muncul, cek pesan error di atas.
exit /b 0

