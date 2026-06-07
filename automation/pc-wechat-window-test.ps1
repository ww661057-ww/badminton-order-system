param(
  [string]$TitleKeyword = "",
  [switch]$UseForeground,
  [switch]$UseMouseWindow,
  [int]$DelaySeconds = 0
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinApi {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern bool GetCursorPos(out Point point);

  [DllImport("user32.dll")]
  public static extern IntPtr WindowFromPoint(Point point);

  [DllImport("user32.dll")]
  public static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);

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

[void][WinApi]::SetProcessDPIAware()

function Get-WindowInfo {
  param([IntPtr]$Handle)

  $titleBuilder = New-Object System.Text.StringBuilder 512
  $classBuilder = New-Object System.Text.StringBuilder 256
  [void][WinApi]::GetWindowText($Handle, $titleBuilder, $titleBuilder.Capacity)
  [void][WinApi]::GetClassName($Handle, $classBuilder, $classBuilder.Capacity)

  $rect = New-Object WinApi+Rect
  [void][WinApi]::GetWindowRect($Handle, [ref]$rect)

  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top

  [pscustomobject]@{
    Handle = $Handle
    HexHandle = ("0x{0:X}" -f $Handle.ToInt64())
    Title = $titleBuilder.ToString()
    ClassName = $classBuilder.ToString()
    Left = $rect.Left
    Top = $rect.Top
    Width = $width
    Height = $height
  }
}

function Get-VisibleWindows {
  $items = New-Object System.Collections.Generic.List[object]
  $callback = {
    param([IntPtr]$hWnd, [IntPtr]$lParam)
    if ([WinApi]::IsWindowVisible($hWnd)) {
      $info = Get-WindowInfo -Handle $hWnd
      if ($info.Title -and $info.Width -gt 100 -and $info.Height -gt 100) {
        $items.Add($info)
      }
    }
    return $true
  }
  [void][WinApi]::EnumWindows($callback, [IntPtr]::Zero)
  return $items
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

Write-Host ""
Write-Host "== PC WeChat window test ==" -ForegroundColor Cyan

if ($DelaySeconds -gt 0) {
  Write-Host "Waiting $DelaySeconds seconds. Click the mini program window now..." -ForegroundColor Yellow
  Start-Sleep -Seconds $DelaySeconds
}

$windows = Get-VisibleWindows

if ($UseMouseWindow) {
  $point = New-Object WinApi+Point
  [void][WinApi]::GetCursorPos([ref]$point)
  $handle = [WinApi]::WindowFromPoint($point)
  $rootHandle = [WinApi]::GetAncestor($handle, 2)
  if ($rootHandle -ne [IntPtr]::Zero) {
    $handle = $rootHandle
  }
  $target = Get-WindowInfo -Handle $handle
} elseif ($UseForeground) {
  $handle = [WinApi]::GetForegroundWindow()
  $target = Get-WindowInfo -Handle $handle
} elseif ($TitleKeyword) {
  $target = $windows |
    Where-Object { $_.Title -like "*$TitleKeyword*" } |
    Sort-Object Width, Height -Descending |
    Select-Object -First 1
} else {
  Write-Host ""
  Write-Host "Visible windows:"
  $windows |
    Sort-Object Title |
    Select-Object Title, ClassName, Left, Top, Width, Height, HexHandle |
    Format-Table -AutoSize

  Write-Host ""
  Write-Host "Run again with one of these options:"
  Write-Host "  .\automation\pc-wechat-window-test.ps1 -UseForeground"
  Write-Host "  .\automation\pc-wechat-window-test.ps1 -UseForeground -DelaySeconds 5"
  Write-Host "  .\automation\pc-wechat-window-test.ps1 -UseMouseWindow -DelaySeconds 5"
  Write-Host "  .\automation\pc-wechat-window-test.ps1 -TitleKeyword `"keyword from window title`""
  exit 0
}

if (-not $target) {
  Write-Host "No matching window was found." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "Target window:" -ForegroundColor Green
$target | Select-Object Title, ClassName, Left, Top, Width, Height, HexHandle | Format-List

if ($target.Width -le 0 -or $target.Height -le 0) {
  Write-Host "Target window has invalid bounds." -ForegroundColor Red
  exit 1
}

$outDir = Join-Path (Get-Location) "automation"
$outPath = Join-Path $outDir "pc-wechat-window.png"
Save-WindowScreenshot -Window $target -Path $outPath

if ((Test-Path -LiteralPath $outPath) -and ((Get-Item -LiteralPath $outPath).Length -gt 0)) {
  Write-Host "Screenshot saved: $outPath" -ForegroundColor Green
  Write-Host "Window connection test passed. Next step: coordinate calibration and click automation." -ForegroundColor Green
} else {
  Write-Host "Screenshot failed." -ForegroundColor Red
  exit 1
}
