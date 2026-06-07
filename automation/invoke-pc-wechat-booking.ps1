param(
  [ValidateSet("now", "midnight")]
  [string]$Mode = "now",
  [string]$CalibrationPath = ".\automation\pc-wechat-calibration.json",
  [string]$StartTime = "15:00",
  [string]$EndTime = "18:00",
  [string]$PreferredCourts = "3,4,2,5,1",
  [int]$TargetDateIndex = 0,
  [int]$DatePageSwipes = 0,
  [switch]$UseMouseWindow,
  [switch]$UseForeground,
  [int]$DelaySeconds = 0,
  [string]$StartAt = "",
  [int]$RetryIntervalMs = 500,
  [int]$MaxRetrySeconds = 180,
  [switch]$ClickSlots,
  [switch]$SubmitOrder
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class BookingWinApi {
  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern bool GetCursorPos(out Point point);

  [DllImport("user32.dll")]
  public static extern IntPtr WindowFromPoint(Point point);

  [DllImport("user32.dll")]
  public static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int x, int y);

  [DllImport("user32.dll")]
  public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

  [StructLayout(LayoutKind.Sequential)]
  public struct Point {
    public int X;
    public int Y;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct Rect {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }
}
"@

[void][BookingWinApi]::SetProcessDPIAware()

function Get-TimeMinutes {
  param([string]$Time)
  $parts = $Time.Split(":")
  return ([int]$parts[0] * 60) + [int]$parts[1]
}

function Get-TargetWindow {
  if ($UseMouseWindow) {
    $point = New-Object BookingWinApi+Point
    [void][BookingWinApi]::GetCursorPos([ref]$point)
    $handle = [BookingWinApi]::WindowFromPoint($point)
    $rootHandle = [BookingWinApi]::GetAncestor($handle, 2)
    if ($rootHandle -ne [IntPtr]::Zero) {
      $handle = $rootHandle
    }
  } else {
    $handle = [BookingWinApi]::GetForegroundWindow()
  }

  $titleBuilder = New-Object System.Text.StringBuilder 512
  [void][BookingWinApi]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)

  $rect = New-Object BookingWinApi+Rect
  [void][BookingWinApi]::GetWindowRect($handle, [ref]$rect)

  [pscustomobject]@{
    Handle = $handle
    Title = $titleBuilder.ToString()
    Left = $rect.Left
    Top = $rect.Top
    Width = $rect.Right - $rect.Left
    Height = $rect.Bottom - $rect.Top
  }
}

function Save-WindowScreenshot {
  param(
    [object]$Window,
    [string]$Path
  )

  $bitmap = New-Object System.Drawing.Bitmap $Window.Width, $Window.Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($Window.Left, $Window.Top, 0, 0, $bitmap.Size)
  $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose()
  $bitmap.Dispose()
}

function Get-CellStatus {
  param(
    [System.Drawing.Bitmap]$Bitmap,
    [int]$CenterX,
    [int]$CenterY
  )

  $left = [Math]::Max(0, $CenterX - 34)
  $top = [Math]::Max(0, $CenterY - 18)
  $right = [Math]::Min($Bitmap.Width - 1, $CenterX + 34)
  $bottom = [Math]::Min($Bitmap.Height - 1, $CenterY + 18)

  $dark = 0
  $blue = 0

  for ($y = $top; $y -le $bottom; $y += 2) {
    for ($x = $left; $x -le $right; $x += 2) {
      $pixel = $Bitmap.GetPixel($x, $y)

      if ($pixel.R -lt 90 -and $pixel.G -lt 90 -and $pixel.B -lt 90) {
        $dark += 1
      }

      if ($pixel.B -gt 170 -and $pixel.R -lt 120 -and $pixel.G -lt 160) {
        $blue += 1
      }
    }
  }

  if ($blue -gt 20) {
    return "selected"
  }

  if ($dark -gt 8) {
    return "available"
  }

  return "unavailable"
}

function Click-Point {
  param(
    [int]$X,
    [int]$Y
  )

  [void][BookingWinApi]::SetCursorPos($X, $Y)
  Start-Sleep -Milliseconds 80
  [BookingWinApi]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 50
  [BookingWinApi]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

function Drag-Point {
  param(
    [int]$FromX,
    [int]$FromY,
    [int]$ToX,
    [int]$ToY
  )

  [void][BookingWinApi]::SetCursorPos($FromX, $FromY)
  Start-Sleep -Milliseconds 80
  [BookingWinApi]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80

  $steps = 12
  for ($index = 1; $index -le $steps; $index += 1) {
    $x = [int]($FromX + (($ToX - $FromX) * $index / $steps))
    $y = [int]($FromY + (($ToY - $FromY) * $index / $steps))
    [void][BookingWinApi]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 18
  }

  [BookingWinApi]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 180
}

function Press-Key {
  param([string]$Key)

  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.SendKeys]::SendWait($Key)
}

function Select-TargetDate {
  param(
    [object]$Window,
    [object]$Calibration,
    [int]$TargetDateIndex,
    [int]$DatePageSwipes
  )

  for ($index = 0; $index -lt $DatePageSwipes; $index += 1) {
    $swipe = $Calibration.actions.dateSwipeLeft
    $fromX = $Window.Left + [int]$swipe.fromX
    $fromY = $Window.Top + [int]$swipe.fromY
    $toX = $Window.Left + [int]$swipe.toX
    $toY = $Window.Top + [int]$swipe.toY
    Write-Host "Swiping date row left $($index + 1)/$DatePageSwipes" -ForegroundColor Cyan
    Drag-Point -FromX $fromX -FromY $fromY -ToX $toX -ToY $toY
  }

  if ($TargetDateIndex -le 0) {
    return
  }

  if ($TargetDateIndex -gt $Calibration.dateTabs.Count) {
    throw "TargetDateIndex $TargetDateIndex is out of range. Current calibration has $($Calibration.dateTabs.Count) date tabs."
  }

  $dateTab = $Calibration.dateTabs[$TargetDateIndex - 1]
  $x = $Window.Left + [int]$dateTab.x
  $y = $Window.Top + [int]$dateTab.y
  Write-Host "Selecting target date tab index $TargetDateIndex at $x,$y" -ForegroundColor Cyan
  Click-Point -X $x -Y $y
  Start-Sleep -Milliseconds 300
}

function Get-Recommendations {
  param(
    [System.Drawing.Bitmap]$Bitmap,
    [object]$Calibration,
    [string]$StartTime,
    [string]$EndTime,
    [string]$PreferredCourts
  )

  $startLimit = Get-TimeMinutes -Time $StartTime
  $endLimit = Get-TimeMinutes -Time $EndTime
  $preferredCourtNumbers = $PreferredCourts.Split(",") |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ } |
    ForEach-Object { [int]$_ }
  $preferredCourtLabels = $preferredCourtNumbers | ForEach-Object { "court-$_" }

  $cells = @()

  foreach ($slot in $Calibration.timeSlots) {
    $slotStart = Get-TimeMinutes -Time $slot.start
    $slotEnd = Get-TimeMinutes -Time $slot.end
    if ($slotStart -lt $startLimit -or $slotEnd -gt $endLimit) {
      continue
    }

    foreach ($court in $Calibration.courts) {
      if ($preferredCourtLabels -notcontains $court.label) {
        continue
      }

      $cells += [pscustomobject]@{
        Time = $slot.label
        Start = $slot.start
        End = $slot.end
        Court = $court.label
        X = [int]$court.x
        Y = [int]$slot.y
        Status = Get-CellStatus -Bitmap $Bitmap -CenterX ([int]$court.x) -CenterY ([int]$slot.y)
      }
    }
  }

  $sameCourtPairs = @()
  $mixedCourtPairs = @()

  for ($index = 0; $index -lt $Calibration.timeSlots.Count - 1; $index += 1) {
    $firstSlot = $Calibration.timeSlots[$index]
    $secondSlot = $Calibration.timeSlots[$index + 1]
    $firstStart = Get-TimeMinutes -Time $firstSlot.start
    $secondEnd = Get-TimeMinutes -Time $secondSlot.end

    if ($firstStart -lt $startLimit -or $secondEnd -gt $endLimit) {
      continue
    }

    foreach ($courtNumber in $preferredCourtNumbers) {
      $courtLabel = "court-$courtNumber"
      $firstCell = $cells | Where-Object { $_.Start -eq $firstSlot.start -and $_.Court -eq $courtLabel } | Select-Object -First 1
      $secondCell = $cells | Where-Object { $_.Start -eq $secondSlot.start -and $_.Court -eq $courtLabel } | Select-Object -First 1

      if ($firstCell -and $secondCell -and $firstCell.Status -eq "available" -and $secondCell.Status -eq "available") {
        $sameCourtPairs += [pscustomobject]@{
          Type = "same-court"
          Start = $firstSlot.start
          End = $secondSlot.end
          Court1 = $courtLabel
          Time1 = $firstSlot.label
          X1 = $firstCell.X
          Y1 = $firstCell.Y
          Court2 = $courtLabel
          Time2 = $secondSlot.label
          X2 = $secondCell.X
          Y2 = $secondCell.Y
        }
      }
    }

    $firstAvailable = $cells | Where-Object { $_.Start -eq $firstSlot.start -and $_.Status -eq "available" }
    $secondAvailable = $cells | Where-Object { $_.Start -eq $secondSlot.start -and $_.Status -eq "available" }

    foreach ($firstCell in $firstAvailable) {
      foreach ($secondCell in $secondAvailable) {
        if ($firstCell.Court -eq $secondCell.Court) {
          continue
        }

        $mixedCourtPairs += [pscustomobject]@{
          Type = "mixed-court"
          Start = $firstSlot.start
          End = $secondSlot.end
          Court1 = $firstCell.Court
          Time1 = $firstSlot.label
          X1 = $firstCell.X
          Y1 = $firstCell.Y
          Court2 = $secondCell.Court
          Time2 = $secondSlot.label
          X2 = $secondCell.X
          Y2 = $secondCell.Y
        }
      }
    }
  }

  return @($sameCourtPairs + $mixedCourtPairs)
}

if (-not $UseMouseWindow -and -not $UseForeground) {
  $UseForeground = $true
}

if ($Mode -eq "now") {
  $StartAt = ""
}

if ($Mode -eq "midnight" -and -not $StartAt) {
  $tomorrow = (Get-Date).Date.AddDays(1)
  $StartAt = $tomorrow.ToString("yyyy-MM-dd 00:00:00")
}

if ($DelaySeconds -gt 0) {
  Write-Host "Waiting $DelaySeconds seconds. Put the mini program window in target state now..." -ForegroundColor Yellow
  Start-Sleep -Seconds $DelaySeconds
}

$calibration = Get-Content -LiteralPath $CalibrationPath -Raw | ConvertFrom-Json
$window = Get-TargetWindow

Write-Host ""
Write-Host "== Target window ==" -ForegroundColor Cyan
$window | Select-Object Title, Left, Top, Width, Height | Format-List
Write-Host "Mode: $Mode"
if ($Mode -eq "now") {
  Write-Host "Starting immediately. Use this for daytime booking on an already released date." -ForegroundColor Cyan
} else {
  Write-Host "Midnight mode. The script will wait, then refresh, swipe date row if needed, select target date, and retry." -ForegroundColor Cyan
}

if ($StartAt) {
  $startAtTime = [DateTime]::Parse($StartAt)
  $waitMs = [int]([Math]::Max(0, ($startAtTime - (Get-Date)).TotalMilliseconds))
  if ($waitMs -gt 0) {
    Write-Host "Window locked. Waiting until $($startAtTime.ToString('yyyy-MM-dd HH:mm:ss')) to start booking..." -ForegroundColor Cyan
    while ((Get-Date) -lt $startAtTime) {
      $remaining = $startAtTime - (Get-Date)
      if ($remaining.TotalSeconds -le 10) {
        Write-Host ("Starting in {0:N1}s" -f $remaining.TotalSeconds) -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500
      } else {
        Write-Host ("Remaining {0:hh\:mm\:ss}" -f $remaining) -ForegroundColor DarkGray
        Start-Sleep -Seconds ([Math]::Min(30, [Math]::Max(1, [int]$remaining.TotalSeconds - 10)))
      }
    }
  } else {
    Write-Host "StartAt is in the past. Starting immediately." -ForegroundColor Yellow
  }
}

$startedAt = Get-Date
$attempt = 0
$lastChoice = $null

while (((Get-Date) - $startedAt).TotalSeconds -le $MaxRetrySeconds) {
  $attempt += 1
  $capturePath = Join-Path (Get-Location) "automation\pc-wechat-live.png"
  Save-WindowScreenshot -Window $window -Path $capturePath
  $bitmap = [System.Drawing.Bitmap]::FromFile($capturePath)

  try {
    $recommendations = Get-Recommendations `
      -Bitmap $bitmap `
      -Calibration $calibration `
      -StartTime $StartTime `
      -EndTime $EndTime `
      -PreferredCourts $PreferredCourts

    if ($recommendations.Count -eq 0) {
      if ($attempt -le 5 -or $attempt % 20 -eq 0) {
        Write-Host "Attempt ${attempt}: no continuous two-hour candidate. Refreshing and retrying..." -ForegroundColor Yellow
      }
      Press-Key "{F5}"
      Start-Sleep -Milliseconds 350
      Select-TargetDate -Window $window -Calibration $calibration -TargetDateIndex $TargetDateIndex -DatePageSwipes $DatePageSwipes
      Start-Sleep -Milliseconds $RetryIntervalMs
      continue
    }

    $choice = $recommendations[0]
    $lastChoice = $choice
    Write-Host ""
    Write-Host "Attempt ${attempt}: candidate found." -ForegroundColor Green
    $choice | Format-List

    $absoluteX1 = $window.Left + $choice.X1
    $absoluteY1 = $window.Top + $choice.Y1
    $absoluteX2 = $window.Left + $choice.X2
    $absoluteY2 = $window.Top + $choice.Y2
    $submitX = $window.Left + [int]$calibration.actions.submitOrder.x
    $submitY = $window.Top + [int]$calibration.actions.submitOrder.y

    Write-Host "Slot click 1: $absoluteX1,$absoluteY1"
    Write-Host "Slot click 2: $absoluteX2,$absoluteY2"
    Write-Host "Submit click: $submitX,$submitY"

    if (-not $ClickSlots) {
      Write-Host ""
      Write-Host "Dry run only. Add -ClickSlots to click the two slots." -ForegroundColor Yellow
      exit 0
    }

    Write-Host "Clicking selected slots..." -ForegroundColor Green
    Click-Point -X $absoluteX1 -Y $absoluteY1
    Start-Sleep -Milliseconds 160
    Click-Point -X $absoluteX2 -Y $absoluteY2
    Start-Sleep -Milliseconds 350
  } finally {
    $bitmap.Dispose()
  }

  Save-WindowScreenshot -Window $window -Path $capturePath
  $verifyBitmap = [System.Drawing.Bitmap]::FromFile($capturePath)
  try {
    $firstStatus = Get-CellStatus -Bitmap $verifyBitmap -CenterX $lastChoice.X1 -CenterY $lastChoice.Y1
    $secondStatus = Get-CellStatus -Bitmap $verifyBitmap -CenterX $lastChoice.X2 -CenterY $lastChoice.Y2
    Write-Host "Verify selection: $firstStatus, $secondStatus"

    if ($firstStatus -eq "selected" -and $secondStatus -eq "selected") {
      if ($SubmitOrder) {
        Write-Host "Selection verified. Clicking submit order..." -ForegroundColor Green
        Click-Point -X $submitX -Y $submitY
      } else {
        Write-Host "Selection verified. Submit order was not clicked. Add -SubmitOrder after verification." -ForegroundColor Green
      }
      exit 0
    }

    Write-Host "Selection was not stable. Refreshing and retrying..." -ForegroundColor Yellow
    Press-Key "{F5}"
    Start-Sleep -Milliseconds 350
    Select-TargetDate -Window $window -Calibration $calibration -TargetDateIndex $TargetDateIndex -DatePageSwipes $DatePageSwipes
    Start-Sleep -Milliseconds $RetryIntervalMs
  } finally {
    $verifyBitmap.Dispose()
  }
}

Write-Host "Max retry time reached without a verified selection." -ForegroundColor Red
exit 3
