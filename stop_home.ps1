$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

if (Test-Path ".env.home") {
    docker compose -f docker-compose.home.yml --env-file .env.home down
} else {
    docker compose -f docker-compose.home.yml down
}
