$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

if (-not (Test-Path ".env.home")) {
    throw "Missing .env.home. Copy .env.home.example to .env.home and set CLOUDFLARE_TUNNEL_TOKEN."
}

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCommand) {
    throw "Flutter is required on this machine. Install Flutter and make sure 'flutter' is on PATH."
}

$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCommand) {
    throw "Docker Desktop is required on this machine. Install Docker Desktop and make sure 'docker' is on PATH."
}

Push-Location "app_flutter"
try {
    flutter pub get
    flutter build web --release --dart-define=MAYBEFLAT_API_BASE_URL=/api
}
finally {
    Pop-Location
}

docker compose -f docker-compose.home.yml --env-file .env.home up -d --build --remove-orphans
docker compose -f docker-compose.home.yml --env-file .env.home ps

Write-Host ""
Write-Host "Home self-hosting stack started."
Write-Host "Local check: http://127.0.0.1:8080"
Write-Host "Public traffic should arrive through Cloudflare Tunnel only."
