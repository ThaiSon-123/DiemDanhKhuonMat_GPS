# Chạy backend trên máy dev với cấu hình dev (nới GPS, khuôn viên phủ cả nước): migration rồi uvicorn.
# Chạy từ thư mục backend:  powershell -ExecutionPolicy Bypass -File scripts\dev_backend.ps1 [-Docker] [-Lan]
#   -Docker : dùng Postgres trong Docker (deploy/docker-compose.dev.yml) và DATABASE_URL trong .env
#             (mặc định: Postgres nhúng pgserver ở backend/.pgdata, không cần Docker)
#   -Lan    : nghe 0.0.0.0 để điện thoại cùng Wi-Fi gọi được (nhớ mở cổng 8000 trên Windows Firewall)
param([switch]$Docker, [switch]$Lan)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$py = '.\.venv\Scripts\python.exe'
if ($Docker) {
    docker compose -f ..\deploy\docker-compose.dev.yml up -d db
    Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue  # lấy từ .env
} else {
    $env:DATABASE_URL = & $py scripts\dev_db.py
    Write-Host "CSDL: $env:DATABASE_URL"
}
$env:CONFIG_FILE = 'config.dev.yaml'
& $py -m alembic upgrade head
$hostAddr = if ($Lan) { '0.0.0.0' } else { '127.0.0.1' }
& $py -m uvicorn app.main:app --reload --env-file .env --host $hostAddr --port 8000
