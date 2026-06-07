param(
  [string]$ImagePath = ".\automation\pc-wechat-window.png",
  [string]$CalibrationPath = ".\automation\pc-wechat-calibration.json",
  [string]$StartTime = "08:00",
  [string]$EndTime = "22:00",
  [string]$PreferredCourts = "1,2,3,4,5"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function Get-TimeMinutes {
  param([string]$Time)
  $parts = $Time.Split(":")
  return ([int]$parts[0] * 60) + [int]$parts[1]
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
  $lightGray = 0
  $samples = 0

  for ($y = $top; $y -le $bottom; $y += 2) {
    for ($x = $left; $x -le $right; $x += 2) {
      $pixel = $Bitmap.GetPixel($x, $y)
      $samples += 1

      if ($pixel.R -lt 90 -and $pixel.G -lt 90 -and $pixel.B -lt 90) {
        $dark += 1
      }

      if ($pixel.B -gt 170 -and $pixel.R -lt 120 -and $pixel.G -lt 160) {
        $blue += 1
      }

      if (
        $pixel.R -gt 205 -and $pixel.R -lt 245 -and
        $pixel.G -gt 205 -and $pixel.G -lt 245 -and
        $pixel.B -gt 205 -and $pixel.B -lt 245
      ) {
        $lightGray += 1
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

function Find-Court {
  param(
    [object[]]$Courts,
    [int]$CourtNumber
  )

  $label = "court-$CourtNumber"
  return $Courts | Where-Object { $_.label -eq $label } | Select-Object -First 1
}

$imageFullPath = Resolve-Path -LiteralPath $ImagePath
$calibration = Get-Content -LiteralPath $CalibrationPath -Raw | ConvertFrom-Json
$bitmap = [System.Drawing.Bitmap]::FromFile($imageFullPath)

try {
  $startLimit = Get-TimeMinutes -Time $StartTime
  $endLimit = Get-TimeMinutes -Time $EndTime
  $preferredCourtNumbers = $PreferredCourts.Split(",") |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ } |
    ForEach-Object { [int]$_ }
  $preferredCourtLabels = $preferredCourtNumbers | ForEach-Object { "court-$_" }

  $cells = @()

  foreach ($slot in $calibration.timeSlots) {
    $slotStart = Get-TimeMinutes -Time $slot.start
    $slotEnd = Get-TimeMinutes -Time $slot.end
    if ($slotStart -lt $startLimit -or $slotEnd -gt $endLimit) {
      continue
    }

    foreach ($court in $calibration.courts) {
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
        Status = Get-CellStatus -Bitmap $bitmap -CenterX ([int]$court.x) -CenterY ([int]$slot.y)
      }
    }
  }

  Write-Host ""
  Write-Host "== Grid status ==" -ForegroundColor Cyan
  $cells | Select-Object Time, Court, Status, X, Y | Format-Table -AutoSize

  $sameCourtPairs = @()
  $mixedCourtPairs = @()

  for ($index = 0; $index -lt $calibration.timeSlots.Count - 1; $index += 1) {
    $firstSlot = $calibration.timeSlots[$index]
    $secondSlot = $calibration.timeSlots[$index + 1]
    $firstStart = Get-TimeMinutes -Time $firstSlot.start
    $secondEnd = Get-TimeMinutes -Time $secondSlot.end

    if ($firstStart -lt $startLimit -or $secondEnd -gt $endLimit) {
      continue
    }

    foreach ($courtNumber in $preferredCourtNumbers) {
      $court = Find-Court -Courts $calibration.courts -CourtNumber $courtNumber
      if (-not $court) { continue }

      $firstCell = $cells | Where-Object { $_.Start -eq $firstSlot.start -and $_.Court -eq $court.label } | Select-Object -First 1
      $secondCell = $cells | Where-Object { $_.Start -eq $secondSlot.start -and $_.Court -eq $court.label } | Select-Object -First 1

      if ($firstCell.Status -eq "available" -and $secondCell.Status -eq "available") {
        $sameCourtPairs += [pscustomobject]@{
          Type = "same-court"
          Start = $firstSlot.start
          End = $secondSlot.end
          Court1 = $court.label
          Time1 = $firstSlot.label
          Court2 = $court.label
          Time2 = $secondSlot.label
          Clicks = "$($firstCell.X),$($firstCell.Y);$($secondCell.X),$($secondCell.Y)"
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
          Court2 = $secondCell.Court
          Time2 = $secondSlot.label
          Clicks = "$($firstCell.X),$($firstCell.Y);$($secondCell.X),$($secondCell.Y)"
        }
      }
    }
  }

  Write-Host ""
  Write-Host "== Recommended pairs: same court first ==" -ForegroundColor Cyan
  $recommendations = @($sameCourtPairs + $mixedCourtPairs)
  if ($recommendations.Count -eq 0) {
    Write-Host "No continuous two-hour candidate found." -ForegroundColor Yellow
  } else {
    $recommendations | Select-Object -First 10 | Format-Table -AutoSize
  }
} finally {
  $bitmap.Dispose()
}
