param(
  [string]$StartTime = "15:00",
  [string]$EndTime = "18:00",
  [string]$PreferredCourts = "3,4,2,5,1",
  [int]$TargetDateIndex = 0,
  [int]$DatePageSwipes = 0,
  [switch]$SubmitOrder
)

$argsList = @(
  "-ExecutionPolicy", "Bypass",
  "-File", ".\automation\invoke-pc-wechat-booking.ps1",
  "-Mode", "now",
  "-UseMouseWindow",
  "-DelaySeconds", "5",
  "-StartTime", $StartTime,
  "-EndTime", $EndTime,
  "-PreferredCourts", $PreferredCourts,
  "-TargetDateIndex", "$TargetDateIndex",
  "-DatePageSwipes", "$DatePageSwipes",
  "-ClickSlots",
  "-RetryIntervalMs", "500",
  "-MaxRetrySeconds", "180"
)

if ($SubmitOrder) {
  $argsList += "-SubmitOrder"
}

& powershell @argsList
