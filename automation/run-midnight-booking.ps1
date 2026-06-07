param(
  [string]$StartAt = "",
  [string]$StartTime = "10:00",
  [string]$EndTime = "12:00",
  [string]$PreferredCourts = "3,4,2,5,1",
  [int]$TargetDateIndex = 5,
  [int]$DatePageSwipes = 1,
  [switch]$SubmitOrder
)

$argsList = @(
  "-ExecutionPolicy", "Bypass",
  "-File", ".\automation\invoke-pc-wechat-booking.ps1",
  "-Mode", "midnight",
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

if ($StartAt) {
  $argsList += @("-StartAt", $StartAt)
}

if ($SubmitOrder) {
  $argsList += "-SubmitOrder"
}

& powershell @argsList
