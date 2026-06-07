param(
  [Parameter(Mandatory = $true)]
  [string]$BookingDate,
  [string]$StartTime = "10:00",
  [string]$EndTime = "12:00",
  [string]$PreferredCourts = "3,4,2,5,1",
  [int]$TargetDateIndex = 5,
  [int]$DatePageSwipes = 1,
  [switch]$SubmitOrder
)

$ErrorActionPreference = "Stop"

$targetDate = [DateTime]::Parse($BookingDate).Date
$releaseAt = $targetDate.AddDays(-6)
$now = Get-Date

if ($releaseAt -le $now) {
  Write-Host "Booking date is already released. Running now mode." -ForegroundColor Cyan
  $argsList = @(
    "-ExecutionPolicy", "Bypass",
    "-File", ".\automation\run-now-booking.ps1",
    "-StartTime", $StartTime,
    "-EndTime", $EndTime,
    "-PreferredCourts", $PreferredCourts,
    "-TargetDateIndex", "$TargetDateIndex",
    "-DatePageSwipes", "$DatePageSwipes"
  )
} else {
  Write-Host "Booking date is not released yet. Running midnight wait mode." -ForegroundColor Cyan
  Write-Host "Release time: $($releaseAt.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
  $argsList = @(
    "-ExecutionPolicy", "Bypass",
    "-File", ".\automation\run-midnight-booking.ps1",
    "-StartAt", $releaseAt.ToString("yyyy-MM-dd HH:mm:ss"),
    "-StartTime", $StartTime,
    "-EndTime", $EndTime,
    "-PreferredCourts", $PreferredCourts,
    "-TargetDateIndex", "$TargetDateIndex",
    "-DatePageSwipes", "$DatePageSwipes"
  )
}

if ($SubmitOrder) {
  $argsList += "-SubmitOrder"
}

& powershell @argsList
