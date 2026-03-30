param(
  [string]$DeviceId = "",
  [switch]$InstallOnly
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

# Ensure adb is available for this shell session.
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  $adbCandidate = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
  if (Test-Path $adbCandidate) {
    $env:Path += ";$(Split-Path $adbCandidate -Parent)"
  }
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  throw "adb not found. Install Android platform-tools or add adb to PATH."
}

if (-not $DeviceId) {
  $devicesJson = flutter devices --machine | Out-String
  $devices = $devicesJson | ConvertFrom-Json
  $androidDevice = $devices | Where-Object { $_.targetPlatform -like "android*" } | Select-Object -First 1

  if (-not $androidDevice) {
    throw "No Android device detected. Connect phone and enable USB debugging."
  }

  $DeviceId = [string]$androidDevice.id
}

Write-Host "Using Android device: $DeviceId"

# Route phone localhost:8000 -> host localhost:8000 via USB.
adb -s $DeviceId reverse tcp:8000 tcp:8000 | Out-Host

if ($InstallOnly) {
  Write-Host "Installing debug APK only (fast path)..."
  flutter install --debug -d $DeviceId
  exit $LASTEXITCODE
}

Write-Host "Running Flutter app with --no-pub (faster iterative deploy)..."
flutter run -d $DeviceId --target lib/main.dart --no-pub
exit $LASTEXITCODE
