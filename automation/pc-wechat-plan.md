# PC WeChat Automation Plan

The PC WeChat path is preferred if the mini program can open and complete booking on Windows.

## Stage 1: Window Connection Test

Open the badminton mini program window first, then run:

```powershell
.\automation\pc-wechat-window-test.ps1 -UseForeground
```

Before running it, click the mini program window so it is the foreground window.

If you want to select by title instead:

```powershell
.\automation\pc-wechat-window-test.ps1 -TitleKeyword "场地"
```

The script saves:

```text
automation/pc-wechat-window.png
```

## Stage 2: Coordinate Calibration

After the screenshot is stable, calibrate these regions:

- Mini program window bounds
- Date tab row
- Court header row
- Time axis
- Booking grid
- Selected slots area
- Submit order button

The current calibration file is:

```text
automation/pc-wechat-calibration.json
```

Render a visual preview with:

```powershell
powershell -ExecutionPolicy Bypass -File .\automation\render-calibration-preview.ps1
```

It writes:

```text
automation/pc-wechat-calibration-preview.png
```

## Stage 3: Booking Loop

At 00:00:00, or immediately during daytime if already released:

1. Refresh or reopen the booking page.
2. Read the booking grid from screenshot.
3. Find two continuous one-hour slots in the target time range.
4. Prefer the same court.
5. If same court is unavailable, accept two courts for the same continuous two-hour range.
6. Click both slots.
7. Click submit order.
8. Stop at payment and show: system booked successfully, please pay in WeChat.

Current grid analysis script:

```powershell
powershell -ExecutionPolicy Bypass -File .\automation\analyze-booking-grid.ps1 -StartTime "15:00" -EndTime "18:00" -PreferredCourts 3,4,2,5,1
```

Dry-run the live PC WeChat booking choice:

```powershell
powershell -ExecutionPolicy Bypass -File .\automation\invoke-pc-wechat-booking.ps1 -UseMouseWindow -DelaySeconds 5 -StartTime "15:00" -EndTime "18:00" -PreferredCourts "3,4,2,5,1"
```

Click only the two slots, without submitting:

```powershell
powershell -ExecutionPolicy Bypass -File .\automation\invoke-pc-wechat-booking.ps1 -UseMouseWindow -DelaySeconds 5 -StartTime "15:00" -EndTime "18:00" -PreferredCourts "3,4,2,5,1" -ClickSlots -RetryIntervalMs 500 -MaxRetrySeconds 180
```

Click slots and submit order:

```powershell
powershell -ExecutionPolicy Bypass -File .\automation\invoke-pc-wechat-booking.ps1 -UseMouseWindow -DelaySeconds 5 -StartTime "15:00" -EndTime "18:00" -PreferredCourts "3,4,2,5,1" -ClickSlots -SubmitOrder -RetryIntervalMs 500 -MaxRetrySeconds 180
```

Lock the mini program window now, then wait until midnight to run:

```powershell
powershell -ExecutionPolicy Bypass -File .\automation\invoke-pc-wechat-booking.ps1 -UseMouseWindow -DelaySeconds 5 -StartAt "2026-06-07 00:00:00" -StartTime "10:00" -EndTime "12:00" -PreferredCourts "3,4,2,5,1" -TargetDateIndex 5 -ClickSlots -SubmitOrder -RetryIntervalMs 500 -MaxRetrySeconds 180
```

`TargetDateIndex` is the date tab position after the page refreshes. For example, `5` means the fifth visible date tab from the left.

If the target date is hidden to the right, add `DatePageSwipes`. For example, swipe the date row left once, then click the fifth visible date:

```powershell
powershell -ExecutionPolicy Bypass -File .\automation\invoke-pc-wechat-booking.ps1 -UseMouseWindow -DelaySeconds 5 -StartAt "2026-06-07 00:00:00" -StartTime "10:00" -EndTime "12:00" -PreferredCourts "3,4,2,5,1" -DatePageSwipes 1 -TargetDateIndex 5 -ClickSlots -SubmitOrder -RetryIntervalMs 500 -MaxRetrySeconds 180
```

## Why Screenshot Plus Coordinates

Mini program grids are often canvas-like or custom-rendered, so normal UI automation may not expose every cell as a button. Screenshot-based detection with calibrated coordinates is usually more reliable for this kind of PC WeChat mini program.
