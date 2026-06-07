param(
  [string]$ImagePath = ".\automation\pc-wechat-window.png",
  [string]$CalibrationPath = ".\automation\pc-wechat-calibration.json",
  [string]$OutPath = ".\automation\pc-wechat-calibration-preview.png"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$imageFullPath = Resolve-Path -LiteralPath $ImagePath
$calibration = Get-Content -LiteralPath $CalibrationPath -Raw | ConvertFrom-Json

$bitmap = [System.Drawing.Bitmap]::FromFile($imageFullPath)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$font = New-Object System.Drawing.Font "Arial", 10, ([System.Drawing.FontStyle]::Bold)
$smallFont = New-Object System.Drawing.Font "Arial", 8, ([System.Drawing.FontStyle]::Bold)
$redPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(230, 225, 61, 87)), 2
$bluePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(230, 47, 104, 255)), 2
$greenPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(230, 33, 166, 122)), 3
$redBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(225, 61, 87))
$blueBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(47, 104, 255))
$greenBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(33, 166, 122))
$whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)

function Draw-Point {
  param(
    [System.Drawing.Graphics]$Graphics,
    [int]$X,
    [int]$Y,
    [string]$Text,
    [System.Drawing.Pen]$Pen,
    [System.Drawing.Brush]$Brush
  )

  $radius = 7
  $Graphics.DrawEllipse($Pen, $X - $radius, $Y - $radius, $radius * 2, $radius * 2)
  $Graphics.DrawLine($Pen, $X - 11, $Y, $X + 11, $Y)
  $Graphics.DrawLine($Pen, $X, $Y - 11, $X, $Y + 11)
  $Graphics.FillRectangle($Brush, $X + 9, $Y - 10, 72, 18)
  $Graphics.DrawString($Text, $smallFont, $whiteBrush, $X + 12, $Y - 9)
}

$grid = $calibration.grid
$graphics.DrawRectangle(
  $greenPen,
  [int]$grid.left,
  [int]$grid.top,
  [int]($grid.right - $grid.left),
  [int]($grid.bottom - $grid.top)
)
$graphics.DrawString("booking grid", $font, $greenBrush, [int]$grid.left + 6, [int]$grid.top + 6)

foreach ($date in $calibration.dateTabs) {
  Draw-Point -Graphics $graphics -X ([int]$date.x) -Y ([int]$date.y) -Text $date.label -Pen $bluePen -Brush $blueBrush
}

foreach ($court in $calibration.courts) {
  Draw-Point -Graphics $graphics -X ([int]$court.x) -Y 278 -Text $court.label -Pen $redPen -Brush $redBrush
}

foreach ($slot in $calibration.timeSlots) {
  $graphics.DrawLine($bluePen, [int]$grid.left, [int]$slot.y, [int]$grid.right, [int]$slot.y)
  $graphics.DrawString($slot.start, $smallFont, $blueBrush, 8, [int]$slot.y - 8)
}

$submit = $calibration.actions.submitOrder
Draw-Point -Graphics $graphics -X ([int]$submit.x) -Y ([int]$submit.y) -Text "submit" -Pen $greenPen -Brush $greenBrush

$outFullPath = Join-Path (Get-Location) $OutPath
$bitmap.Save($outFullPath, [System.Drawing.Imaging.ImageFormat]::Png)

$graphics.Dispose()
$bitmap.Dispose()
$font.Dispose()
$smallFont.Dispose()
$redPen.Dispose()
$bluePen.Dispose()
$greenPen.Dispose()
$redBrush.Dispose()
$blueBrush.Dispose()
$greenBrush.Dispose()
$whiteBrush.Dispose()

Write-Host "Calibration preview saved: $outFullPath" -ForegroundColor Green
