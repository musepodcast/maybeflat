$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$appDir = Join-Path $root "app_flutter"

Set-Location $appDir

Write-Host "Ensuring Flutter project files exist..."
flutter create . --platforms=android,ios,windows,linux,macos,web

Write-Host "Installing Flutter dependencies..."
flutter pub get

Write-Host "Starting Maybeflat Flutter app..."
flutter run

