param(
  [string]$AdbPath = ""
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "== $Message ==" -ForegroundColor Cyan
}

function Find-Adb {
  param([string]$ExplicitPath)

  if ($ExplicitPath -and (Test-Path -LiteralPath $ExplicitPath)) {
    return (Resolve-Path -LiteralPath $ExplicitPath).Path
  }

  $fromPath = Get-Command adb -ErrorAction SilentlyContinue
  if ($fromPath) {
    return $fromPath.Source
  }

  $candidates = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
    "C:\Android\platform-tools\adb.exe"
  )

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }

  return $null
}

function Run-Adb {
  param(
    [string]$Adb,
    [string[]]$Args
  )

  & $Adb @Args
}

Write-Step "Find ADB"
$adb = Find-Adb -ExplicitPath $AdbPath
if (-not $adb) {
  Write-Host "adb.exe was not found." -ForegroundColor Red
  Write-Host "Install Android Platform Tools and add platform-tools to PATH."
  Write-Host "Common path: %LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
  exit 1
}
Write-Host "ADB: $adb" -ForegroundColor Green

Write-Step "Start ADB server"
Run-Adb -Adb $adb -Args @("start-server") | Out-Host

Write-Step "Check device authorization"
$devicesOutput = Run-Adb -Adb $adb -Args @("devices")
$devicesOutput | Out-Host
$deviceLines = $devicesOutput | Where-Object { $_ -match "^\S+\s+(device|unauthorized|offline)$" }

if (-not $deviceLines) {
  Write-Host "No Android device was found." -ForegroundColor Red
  Write-Host "Connect the phone with USB, enable Developer Options and USB debugging, then allow USB debugging on the phone."
  exit 1
}

$unauthorized = $deviceLines | Where-Object { $_ -match "\sunauthorized$" }
if ($unauthorized) {
  Write-Host "Device is unauthorized. Tap Allow USB debugging on the phone, then run this script again." -ForegroundColor Yellow
  exit 1
}

$offline = $deviceLines | Where-Object { $_ -match "\soffline$" }
if ($offline) {
  Write-Host "Device is offline. Reconnect USB or restart adb server." -ForegroundColor Yellow
  exit 1
}

Write-Step "Read device info"
$brand = Run-Adb -Adb $adb -Args @("shell", "getprop", "ro.product.brand")
$model = Run-Adb -Adb $adb -Args @("shell", "getprop", "ro.product.model")
$android = Run-Adb -Adb $adb -Args @("shell", "getprop", "ro.build.version.release")
$size = Run-Adb -Adb $adb -Args @("shell", "wm", "size")
$density = Run-Adb -Adb $adb -Args @("shell", "wm", "density")
Write-Host "Brand: $brand"
Write-Host "Model: $model"
Write-Host "Android: $android"
Write-Host "Screen: $size"
Write-Host "Density: $density"

Write-Step "Check WeChat installation"
$wechatPackage = Run-Adb -Adb $adb -Args @("shell", "pm", "path", "com.tencent.mm")
if ($LASTEXITCODE -ne 0 -or -not $wechatPackage) {
  Write-Host "WeChat package com.tencent.mm was not found. Install and log in to WeChat on the test device." -ForegroundColor Red
  exit 1
}
Write-Host $wechatPackage -ForegroundColor Green

Write-Step "Test screenshot"
$screenshotDir = Join-Path (Get-Location) "automation"
$screenshotPath = Join-Path $screenshotDir "device-screen.png"
Run-Adb -Adb $adb -Args @("exec-out", "screencap", "-p") | Set-Content -Encoding Byte -Path $screenshotPath
if ((Test-Path -LiteralPath $screenshotPath) -and ((Get-Item -LiteralPath $screenshotPath).Length -gt 0)) {
  Write-Host "Screenshot saved: $screenshotPath" -ForegroundColor Green
} else {
  Write-Host "Screenshot failed." -ForegroundColor Red
  exit 1
}

Write-Step "Launch WeChat"
Run-Adb -Adb $adb -Args @(
  "shell",
  "monkey",
  "-p",
  "com.tencent.mm",
  "-c",
  "android.intent.category.LAUNCHER",
  "1"
) | Out-Host

Write-Host ""
Write-Host "Connection test passed. The computer can control the Android device. Next step: Appium automation." -ForegroundColor Green
