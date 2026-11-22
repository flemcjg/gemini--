#Requires -Version 5.1
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$WidgetDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $WidgetDir
$AssetsDir = Join-Path $PluginRoot "assets"
$SharedDir = Join-Path $PluginRoot "data"
New-Item -ItemType Directory -Force -Path $SharedDir | Out-Null

$PidFile = Join-Path $SharedDir "widget.pid"
$ConfigPath = Join-Path $SharedDir "config.json"
$QuotesPath = Join-Path $SharedDir "quotes.json"
$LiveQuotaPath = Join-Path $SharedDir "live_quota.json"

# Single instance guard
if (Test-Path $PidFile) {
    try {
        $oldPid = [int](Get-Content $PidFile -ErrorAction Stop | Select-Object -First 1)
        if ($oldPid -gt 0 -and $oldPid -ne $PID) {
            $oldProc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($oldProc) { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue }
        }
    } catch {}
}
Set-Content -Path $PidFile -Value $PID -Encoding ASCII

# Win32 Helpers: Antigravity Window Finder + Physical Cursor Position (DPI-safe dragging)
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class AgyWin32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }

    public static IntPtr FindAntigravityWindow() {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            if (!IsWindowVisible(hWnd)) return true;
            var sb = new StringBuilder(256);
            GetWindowText(hWnd, sb, sb.Capacity);
            string title = sb.ToString();
            if (!string.IsNullOrEmpty(title) &&
                title.IndexOf("Antigravity", StringComparison.OrdinalIgnoreCase) >= 0 &&
                title.IndexOf("GPT-喵", StringComparison.OrdinalIgnoreCase) < 0) {
                found = hWnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}

public class AgyAudioMeter {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumerator {}

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator {
        int NotImpl1();
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    }

    [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioMeterInformation {
        [PreserveSig] int GetPeakValue(out float pfPeak);
    }

    private static IAudioMeterInformation _meter;
    private static DateTime _lastInit = DateTime.MinValue;

    public static float GetSystemPeak() {
        try {
            if (_meter == null || (DateTime.UtcNow - _lastInit).TotalSeconds > 15) {
                var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
                IMMDevice dev;
                if (enumerator.GetDefaultAudioEndpoint(0, 1, out dev) != 0 || dev == null) return 0f;
                Guid iid = typeof(IAudioMeterInformation).GUID;
                object obj;
                if (dev.Activate(ref iid, 23, IntPtr.Zero, out obj) != 0 || obj == null) return 0f;
                _meter = (IAudioMeterInformation)obj;
                _lastInit = DateTime.UtcNow;
            }
            float peak = 0f;
            if (_meter.GetPeakValue(out peak) == 0) return peak;
        } catch {
            _meter = null;
        }
        return 0f;
    }
}
"@

# Load XAML
[xml]$xaml = Get-Content (Join-Path $WidgetDir "widget.xaml") -Raw -Encoding UTF8
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$Girl = $window.FindName("Girl")
$Bubble = $window.FindName("Bubble")
$TailFar = $window.FindName("TailFar")
$TailNear = $window.FindName("TailNear")
$QuoteText = $window.FindName("QuoteText")
$QuotaText = $window.FindName("QuotaText")
$Header = $window.FindName("Header")
$RefreshBtn = $window.FindName("Refresh")
$ShortLabel = $window.FindName("ShortLabel")
$ShortLeft = $window.FindName("ShortLeft")
$ShortBar = $window.FindName("ShortBar")
$ShortReset = $window.FindName("ShortReset")
$WeekRow = $window.FindName("WeekRow")
$WeekLabel = $window.FindName("WeekLabel")
$WeekLeft = $window.FindName("WeekLeft")
$WeekBar = $window.FindName("WeekBar")
$WeekReset = $window.FindName("WeekReset")
$PressScale = $window.FindName("PressScale")
$GirlDanceScale = $window.FindName("GirlDanceScale")
$FacingScale = $window.FindName("FacingScale")
$TextFacingScale = $window.FindName("TextFacingScale")

# Load Catgirl Image
$imgPath = Join-Path $AssetsDir "catgirl-bust.png"
if (Test-Path $imgPath) {
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.UriSource = New-Object System.Uri($imgPath)
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.EndInit()
    $Girl.Source = $bmp
}

$pressWav = Join-Path $AssetsDir "press.wav"
$releaseWav = Join-Path $AssetsDir "release.wav"
$script:pressPlayer = New-Object System.Media.SoundPlayer $pressWav
$script:releasePlayer = New-Object System.Media.SoundPlayer $releaseWav

# State
$script:config = @{
    planName = "Gemini Models · 估算"
    shortLabel = "5 小时"
    shortBudget = 160
    weekLabel = "每周"
    weekBudget = 650
    showWeekRow = $true
    displayMode = "follow"
    keepInsideScreen = $true
    topmost = $true
    scale = 100
    muted = $false
    musicRhythm = $false
    autoHideSeconds = 5
    autoHideEnabled = $true
    autoQuoteEnabled = $false
    autoQuoteMinutes = 5
    replyNotifyEnabled = $true
    calibratedAtUtc = ""
    calibratedShortPct = $null
    calibratedWeekPct = $null
    shortResetAtUtc = ""
    weekResetAtUtc = ""
}
$script:quotes = @(@{ text = "我是啥喵？"; weight = 3.0 })
$script:bubbleState = "quote"
$script:offsetRight = 24.0
$script:offsetBottom = 20.0
$script:isDragging = $false
$script:dragMoved = $false
$script:dragStartCursorX = 0
$script:dragStartCursorY = 0
$script:dragStartLeft = 0.0
$script:dragStartTop = 0.0
$script:dragDpiX = 1.0
$script:dragDpiY = 1.0
$script:lastConfigWrite = [DateTime]::MinValue
$script:lastLiveQuotaWrite = [DateTime]::MinValue
$script:replyBaselineReady = $false
$script:knownReplyLengths = @{}

function Get-WindowDpiScale {
    try {
        $dpi = [Windows.Media.VisualTreeHelper]::GetDpi($window)
        $sx = if ($dpi.DpiScaleX -gt 0.1) { $dpi.DpiScaleX } else { 1.0 }
        $sy = if ($dpi.DpiScaleY -gt 0.1) { $dpi.DpiScaleY } else { 1.0 }
        return @($sx, $sy)
    } catch {
        return @(1.0, 1.0)
    }
}

function Get-VisibleInsets {
    # Exact visible bounds inside 378x378 AnimationStage (removes invisible transparent padding)
    $unit = $window.Width / 378.0
    $flipped = ($FacingScale.ScaleX -lt 0)
    $bubbleVisible = ($script:bubbleState -ne "hidden")

    if ($bubbleVisible) {
        if ($flipped) {
            $padL = 18.0 * $unit
            $padR = 40.0 * $unit
        } else {
            $padL = 40.0 * $unit
            $padR = 18.0 * $unit
        }
        $padT = 18.0 * $unit
        $padB = 18.0 * $unit
    } else {
        if ($flipped) {
            $padL = 18.0 * $unit
            $padR = 160.0 * $unit
        } else {
            $padL = 160.0 * $unit
            $padR = 18.0 * $unit
        }
        $padT = 166.0 * $unit
        $padB = 18.0 * $unit
    }
    return @($padL, $padT, $padR, $padB)
}

function Clamp-ToScreen([double]$left, [double]$top) {
    if ([double]::IsNaN($left) -or [double]::IsInfinity($left)) { $left = 0.0 }
    if ([double]::IsNaN($top) -or [double]::IsInfinity($top)) { $top = 0.0 }
    if (-not [bool]$script:config.keepInsideScreen) {
        return @($left, $top)
    }
    $dpi = Get-WindowDpiScale
    $sx = $dpi[0]; $sy = $dpi[1]

    # Pick the screen containing the center of the widget
    $cxPx = [int][Math]::Round(($left + $window.Width / 2.0) * $sx)
    $cyPx = [int][Math]::Round(($top + $window.Height / 2.0) * $sy)
    $scr = [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new($cxPx, $cyPx))
    $wa = $scr.WorkingArea

    $insets = Get-VisibleInsets
    $padL = $insets[0]; $padT = $insets[1]; $padR = $insets[2]; $padB = $insets[3]

    # Clamp visible artwork bounds flush to the 4 edges of the desktop work area
    $minL = ($wa.Left / $sx) - $padL
    $minT = ($wa.Top / $sy) - $padT
    $maxL = ($wa.Right / $sx) - ($window.Width - $padR)
    $maxT = ($wa.Bottom / $sy) - ($window.Height - $padB)

    if ($maxL -lt $minL) { $maxL = $minL }
    if ($maxT -lt $minT) { $maxT = $minT }

    $clampedL = [Math]::Max($minL, [Math]::Min($maxL, $left))
    $clampedT = [Math]::Max($minT, [Math]::Min($maxT, $top))
    return @($clampedL, $clampedT)
}

function Load-Config {
    if (Test-Path $ConfigPath) {
        try {
            $fi = Get-Item $ConfigPath
            if ($fi.LastWriteTimeUtc -ne $script:lastConfigWrite) {
                $script:lastConfigWrite = $fi.LastWriteTimeUtc
                $raw = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($p in $raw.PSObject.Properties) {
                    $script:config[$p.Name] = $p.Value
                }
                Apply-Scale
                $window.Topmost = [bool]$script:config.topmost
                if (Get-Command Sync-AutoQuoteTimer -ErrorAction SilentlyContinue) { Sync-AutoQuoteTimer }
                Refresh-LocalStats
            }
        } catch {}
    }
    # Auto-detect fresh agy live_quota.json without manual refresh
    if (Test-Path $LiveQuotaPath) {
        try {
            $lfi = Get-Item $LiveQuotaPath
            if ($lfi.LastWriteTimeUtc -ne $script:lastLiveQuotaWrite) {
                $script:lastLiveQuotaWrite = $lfi.LastWriteTimeUtc
                Refresh-LocalStats
            }
        } catch {}
    }
    if (Test-Path $QuotesPath) {
        try {
            $qraw = Get-Content $QuotesPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($qraw.quotes -and $qraw.quotes.Count -gt 0) {
                $script:quotes = @($qraw.quotes)
            }
        } catch {}
    } elseif (Test-Path (Join-Path $AssetsDir "quotes.json")) {
        try {
            $qraw = Get-Content (Join-Path $AssetsDir "quotes.json") -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($qraw.quotes) { $script:quotes = @($qraw.quotes) }
        } catch {}
    }
}

function Save-Config {
    try {
        ($script:config | ConvertTo-Json -Depth 4) | Set-Content -Path $ConfigPath -Encoding UTF8
        $script:lastConfigWrite = (Get-Item $ConfigPath).LastWriteTimeUtc
    } catch {}
}

function Apply-Scale {
    $pct = [Math]::Max(60, [Math]::Min(250, [int]$script:config.scale))
    $oldW = $window.Width
    $oldH = $window.Height
    $size = [Math]::Round(320 * ($pct / 100.0))
    $window.Width = $size
    $window.Height = $size
    # Only adjust window position if Left/Top are valid numbers (not NaN during startup)
    if (-not [double]::IsNaN($window.Left) -and -not [double]::IsNaN($window.Top)) {
        if (-not [double]::IsNaN($oldW) -and -not [double]::IsNaN($oldH) -and $oldW -gt 0 -and $oldH -gt 0) {
            if ($FacingScale.ScaleX -lt 0) {
                $newLeft = $window.Left
            } else {
                $newLeft = $window.Left + ($oldW - $size)
            }
            $newTop = $window.Top + ($oldH - $size)
            $pos = Clamp-ToScreen $newLeft $newTop
            $window.Left = $pos[0]
            $window.Top = $pos[1]
        } else {
            $pos = Clamp-ToScreen $window.Left $window.Top
            $window.Left = $pos[0]
            $window.Top = $pos[1]
        }
    }
}

function Open-SizeDialog {
    if ($null -ne $script:sizeDlg -and $script:sizeDlg.IsVisible) {
        $script:sizeDlg.Activate() | Out-Null
        return
    }
    $script:sizeDlg = New-Object System.Windows.Window
    $script:sizeDlg.Title = "GPT-喵 · 自定义大小"
    $script:sizeDlg.Width = 315
    $script:sizeDlg.Height = 180
    $script:sizeDlg.ResizeMode = "NoResize"
    $script:sizeDlg.WindowStartupLocation = "CenterScreen"
    $script:sizeDlg.Topmost = $true
    $script:sizeDlg.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#FAF8FE")
    $script:sizeDlg.FontFamily = New-Object System.Windows.Media.FontFamily("Microsoft YaHei UI")

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness(16, 14, 16, 14)

    $hdr = New-Object System.Windows.Controls.DockPanel
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = "挂件缩放比例（60% - 250%）"
    $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#4A3B63")
    $lbl.FontWeight = "SemiBold"

    $script:sizeValLbl = New-Object System.Windows.Controls.TextBlock
    $script:sizeValLbl.Text = "$([int]$script:config.scale)%"
    $script:sizeValLbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#745A98")
    $script:sizeValLbl.FontWeight = "Bold"
    $script:sizeValLbl.HorizontalAlignment = "Right"
    [System.Windows.Controls.DockPanel]::SetDock($script:sizeValLbl, "Right")
    $hdr.Children.Add($script:sizeValLbl) | Out-Null
    $hdr.Children.Add($lbl) | Out-Null
    $panel.Children.Add($hdr) | Out-Null

    $script:sizeSlider = New-Object System.Windows.Controls.Slider
    $script:sizeSlider.Minimum = 60
    $script:sizeSlider.Maximum = 250
    $script:sizeSlider.TickFrequency = 5
    $script:sizeSlider.IsSnapToTickEnabled = $true
    $script:sizeSlider.Value = [Math]::Max(60, [Math]::Min(250, [int]$script:config.scale))
    $script:sizeSlider.Margin = New-Object System.Windows.Thickness(0, 10, 0, 10)
    $script:sizeSlider.Add_ValueChanged({
        param($s, $e)
        $v = [int][Math]::Round($s.Value)
        if ($null -ne $script:sizeValLbl) { $script:sizeValLbl.Text = "$v%" }
        $script:config.scale = $v
        Apply-Scale
    })
    $panel.Children.Add($script:sizeSlider) | Out-Null

    $presetRow = New-Object System.Windows.Controls.UniformGrid
    $presetRow.Columns = 5
    $presetRow.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    foreach ($p in @(70, 85, 100, 140, 180)) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = "$p%"
        $btn.Tag = $p
        $btn.Margin = New-Object System.Windows.Thickness(2, 0, 2, 0)
        $btn.Padding = New-Object System.Windows.Thickness(4, 3, 4, 3)
        $btn.Add_Click({
            param($s, $e)
            if ($null -ne $script:sizeSlider) { $script:sizeSlider.Value = [int]$s.Tag }
        })
        $presetRow.Children.Add($btn) | Out-Null
    }
    $panel.Children.Add($presetRow) | Out-Null

    $okBtn = New-Object System.Windows.Controls.Button
    $okBtn.Content = "保存大小"
    $okBtn.HorizontalAlignment = "Right"
    $okBtn.Padding = New-Object System.Windows.Thickness(14, 4, 14, 4)
    $okBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#745A98")
    $okBtn.Foreground = [Windows.Media.Brushes]::White
    $okBtn.BorderThickness = New-Object System.Windows.Thickness(0)
    $okBtn.Add_Click({
        Save-Config
        if ($null -ne $script:sizeDlg) { $script:sizeDlg.Close() }
    })
    $panel.Children.Add($okBtn) | Out-Null

    $script:sizeDlg.Content = $panel
    $script:sizeDlg.Add_Closed({
        Save-Config
        $script:sizeDlg = $null
    })
    $script:sizeDlg.Show() | Out-Null
}

function Play-Sfx([string]$kind) {
    if ($script:config.muted) { return }
    try {
        if ($kind -eq "press" -and (Test-Path $pressWav)) { $script:pressPlayer.Play() }
        elseif ($kind -eq "release" -and (Test-Path $releaseWav)) { $script:releasePlayer.Play() }
    } catch {}
}

function Format-Remaining([TimeSpan]$ts) {
    if ($ts.TotalMinutes -le 0) { return "即将刷新" }
    if ($ts.Days -gt 0) { return "$($ts.Days) 天 $($ts.Hours) 小时后刷新" }
    if ($ts.Hours -gt 0) { return "$($ts.Hours) 小时 $($ts.Minutes) 分后刷新" }
    return "$($ts.Minutes) 分钟后刷新"
}

function Parse-UtcOrNull([object]$val) {
    if ($null -eq $val -or [string]::IsNullOrWhiteSpace([string]$val)) { return $null }
    $dt = [DateTime]::MinValue
    if ([DateTime]::TryParse([string]$val, [ref]$dt)) { return $dt.ToUniversalTime() }
    return $null
}

function Refresh-LocalStats {
    $now = [DateTime]::UtcNow

    # 1. Prefer official agy CLI statusLine real-time quota if available
    if (Test-Path $LiveQuotaPath) {
        try {
            $live = Get-Content $LiveQuotaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($live -and $live.windows -and $live.windows.Count -gt 0) {
                $upd = Parse-UtcOrNull $live.updatedAtUtc
                $stale = ($null -eq $upd) -or (($now - $upd).TotalMinutes -gt 15)
                $tier = if ($live.planTier) { [string]$live.planTier } else { "Antigravity" }
                $Header.Text = if ($stale) { "$tier · agy 缓存" } else { "$tier · agy 实时" }

                $w0 = $live.windows[0]
                $p0 = [Math]::Max(0, [Math]::Min(100, [int]$w0.leftPct))
                $rt0 = Parse-UtcOrNull $w0.resetTime
                $rtxt0 = if ($null -ne $rt0) { Format-Remaining ($rt0 - $now) } elseif ($null -ne $w0.resetInSeconds) { Format-Remaining ([TimeSpan]::FromSeconds([double]$w0.resetInSeconds)) } else { "官方实时额度" }
                $ShortLabel.Text = [string]$w0.label
                $ShortLeft.Text = "$p0%"
                $ShortBar.Width = [Math]::Round(178.0 * ($p0 / 100.0))
                $ShortReset.Text = $rtxt0

                if ($live.windows.Count -ge 2) {
                    $w1 = $live.windows[1]
                    $p1 = [Math]::Max(0, [Math]::Min(100, [int]$w1.leftPct))
                    $rt1 = Parse-UtcOrNull $w1.resetTime
                    $rtxt1 = if ($null -ne $rt1) { Format-Remaining ($rt1 - $now) } elseif ($null -ne $w1.resetInSeconds) { Format-Remaining ([TimeSpan]::FromSeconds([double]$w1.resetInSeconds)) } else { "官方实时额度" }
                    $WeekRow.Visibility = "Visible"
                    $WeekLabel.Text = [string]$w1.label
                    $WeekLeft.Text = "$p1%"
                    $WeekBar.Width = [Math]::Round(178.0 * ($p1 / 100.0))
                    $WeekReset.Text = $rtxt1
                } else {
                    $WeekRow.Visibility = "Collapsed"
                }
                return
            }
        } catch {}
    }

    # 2. Fallback: local USER_INPUT counter + calibration anchor
    $shortCut = $now.AddHours(-5)
    $weekCut = $now.AddDays(-7)
    $calTime = Parse-UtcOrNull $script:config.calibratedAtUtc
    $shortResetAt = Parse-UtcOrNull $script:config.shortResetAtUtc
    $weekResetAt = Parse-UtcOrNull $script:config.weekResetAtUtc

    $brainDir = Join-Path $env:USERPROFILE ".gemini\antigravity\brain"
    $shortTurns = New-Object System.Collections.Generic.List[DateTime]
    $weekTurns = 0
    $deltaAfterCal = 0
    $conv7d = 0

    if (Test-Path $brainDir) {
        foreach ($dir in Get-ChildItem -Path $brainDir -Directory -ErrorAction SilentlyContinue) {
            $log = Join-Path $dir.FullName ".system_generated\logs\transcript.jsonl"
            if (-not (Test-Path $log)) { continue }
            $fi = Get-Item $log -ErrorAction SilentlyContinue
            if (-not $fi -or $fi.LastWriteTimeUtc -lt $weekCut) { continue }
            $conv7d++
            try {
                foreach ($line in [System.IO.File]::ReadLines($log)) {
                    if ($line.IndexOf('"USER_INPUT"') -lt 0) { continue }
                    $m = [regex]::Match($line, '"created_at"\s*:\s*"([^"]+)"')
                    if (-not $m.Success) { continue }
                    $dt = [DateTime]::MinValue
                    if ([DateTime]::TryParse($m.Groups[1].Value, [ref]$dt)) {
                        $utc = $dt.ToUniversalTime()
                        if ($utc -ge $weekCut) {
                            $weekTurns++
                            if ($utc -ge $shortCut) { $shortTurns.Add($utc) }
                            if ($null -ne $calTime -and $utc -gt $calTime) { $deltaAfterCal++ }
                        }
                    }
                }
            } catch {}
        }
    }

    $sBudget = [Math]::Max(10, [int]$script:config.shortBudget)
    $wBudget = [Math]::Max(20, [int]$script:config.weekBudget)

    if ($null -ne $calTime -and $null -ne $script:config.calibratedShortPct -and ($null -eq $shortResetAt -or $now -lt $shortResetAt)) {
        $baseS = [double]$script:config.calibratedShortPct
        $sLeft = [Math]::Max(0, [Math]::Min(100, [Math]::Round($baseS - ($deltaAfterCal / [double]$sBudget) * 100.0)))
        $sReset = if ($null -ne $shortResetAt) { Format-Remaining ($shortResetAt - $now) } else { "已校准 · 5 小时窗口" }
    } else {
        $sLeft = [Math]::Max(0, [Math]::Min(100, [Math]::Round((1.0 - $shortTurns.Count / [double]$sBudget) * 100.0)))
        if ($shortTurns.Count -gt 0) {
            $oldest = ($shortTurns | Sort-Object | Select-Object -First 1)
            $sReset = Format-Remaining ($oldest.AddHours(5) - $now)
        } else {
            $sReset = "当前 5 小时窗口满额"
        }
    }

    if ($null -ne $calTime -and $null -ne $script:config.calibratedWeekPct -and ($null -eq $weekResetAt -or $now -lt $weekResetAt)) {
        $baseW = [double]$script:config.calibratedWeekPct
        $wLeft = [Math]::Max(0, [Math]::Min(100, [Math]::Round($baseW - ($deltaAfterCal / [double]$wBudget) * 100.0)))
        $wReset = if ($null -ne $weekResetAt) { Format-Remaining ($weekResetAt - $now) } else { "已校准 · 每周窗口" }
    } else {
        $wLeft = [Math]::Max(0, [Math]::Min(100, [Math]::Round((1.0 - $weekTurns / [double]$wBudget) * 100.0)))
        $wReset = "近 7 天 $conv7d 会话 · $weekTurns 轮"
    }

    $Header.Text = [string]$script:config.planName
    $ShortLabel.Text = [string]$script:config.shortLabel
    $ShortLeft.Text = "$sLeft%"
    $ShortBar.Width = [Math]::Round(178.0 * ($sLeft / 100.0))
    $ShortReset.Text = $sReset

    $WeekRow.Visibility = if ($script:config.showWeekRow) { "Visible" } else { "Collapsed" }
    $WeekLabel.Text = [string]$script:config.weekLabel
    $WeekLeft.Text = "$wLeft%"
    $WeekBar.Width = [Math]::Round(178.0 * ($wLeft / 100.0))
    $WeekReset.Text = $wReset
}

function Set-BubbleMode([string]$mode) {
    $script:bubbleState = $mode
    if ($mode -eq "hidden") {
        $Bubble.Visibility = "Collapsed"
        $TailFar.Visibility = "Collapsed"
        $TailNear.Visibility = "Collapsed"
    } else {
        $Bubble.Visibility = "Visible"
        $TailFar.Visibility = "Visible"
        $TailNear.Visibility = "Visible"
        if ($mode -eq "quota") {
            $QuoteText.Visibility = "Collapsed"
            $QuotaText.Visibility = "Visible"
            Refresh-LocalStats
        } else {
            $QuotaText.Visibility = "Collapsed"
            $QuoteText.Visibility = "Visible"
        }
    }
    if ($mode -ne "hidden") {
        # Ensure newly opened bubble stays cleanly inside screen edges
        $pos = Clamp-ToScreen $window.Left $window.Top
        $window.Left = $pos[0]
        $window.Top = $pos[1]
    }
    Reset-AutoHide
}

function Show-Quote([string]$txt) {
    $QuoteText.Text = $txt
    $QuoteText.LineHeight = [Double]::NaN
    # Dynamically pick the largest font size that fits cleanly inside the oval bubble (174x102)
    $bestSize = 15
    $measureBox = New-Object System.Windows.Size(174, [Double]::PositiveInfinity)
    foreach ($sz in @(30, 28, 26, 24, 22, 20, 19, 18, 17, 16, 15)) {
        $QuoteText.FontSize = $sz
        $QuoteText.Measure($measureBox)
        if ($QuoteText.DesiredSize.Height -le 102 -and $QuoteText.DesiredSize.Width -le 174) {
            $bestSize = $sz
            break
        }
    }
    $QuoteText.FontSize = $bestSize

    if ((Get-Random -Minimum 0 -Maximum 100) -lt 3) {
        $QuoteText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#D946EF")
    } else {
        $QuoteText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#745A98")
    }
    Set-BubbleMode "quote"
}

function Pick-RandomQuote {
    $total = 0.0
    foreach ($q in $script:quotes) { $total += [Math]::Max(0.1, [double]$q.weight) }
    $r = (Get-Random -Minimum 0.0 -Maximum $total)
    $acc = 0.0
    foreach ($q in $script:quotes) {
        $acc += [Math]::Max(0.1, [double]$q.weight)
        if ($r -le $acc) { return [string]$q.text }
    }
    return "我是啥喵？"
}

# Auto-hide timer
$script:hideTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:hideTimer.Interval = [TimeSpan]::FromSeconds(6)
$script:hideTimer.Add_Tick({
    $script:hideTimer.Stop()
    if ($script:config.autoHideEnabled -and $script:bubbleState -ne "hidden") {
        Set-BubbleMode "hidden"
    }
})
function Reset-AutoHide {
    $script:hideTimer.Stop()
    if ($script:config.autoHideEnabled -and $script:bubbleState -ne "hidden") {
        $script:hideTimer.Interval = [TimeSpan]::FromSeconds([Math]::Max(3, [int]$script:config.autoHideSeconds))
        $script:hideTimer.Start()
    }
}

# Initial placement (bottom-right of primary screen, clamped)
$workArea = [System.Windows.SystemParameters]::WorkArea
Load-Config
Apply-Scale
$initPos = Clamp-ToScreen ($workArea.Right - $window.Width - 20) ($workArea.Bottom - $window.Height - 10)
$window.Left = $initPos[0]
$window.Top = $initPos[1]

# DPI-Safe Dragging (1:1 locked to cursor, clamped inside screen, flip only on drop)
$Girl.Add_MouseLeftButtonDown({
    param($s, $e)
    $script:isDragging = $true
    $script:dragMoved = $false

    $pt = New-Object AgyWin32+POINT
    [AgyWin32]::GetCursorPos([ref]$pt) | Out-Null
    $dpi = Get-WindowDpiScale
    $script:dragDpiX = $dpi[0]
    $script:dragDpiY = $dpi[1]
    $script:dragStartCursorX = $pt.X
    $script:dragStartCursorY = $pt.Y
    $script:dragStartLeft = $window.Left
    $script:dragStartTop = $window.Top

    $PressScale.ScaleX = 0.94
    $PressScale.ScaleY = 0.90
    Play-Sfx "press"
    $Girl.CaptureMouse() | Out-Null
})

$Girl.Add_MouseMove({
    param($s, $e)
    if (-not $script:isDragging) { return }
    $pt = New-Object AgyWin32+POINT
    [AgyWin32]::GetCursorPos([ref]$pt) | Out-Null

    $dxDip = ($pt.X - $script:dragStartCursorX) / $script:dragDpiX
    $dyDip = ($pt.Y - $script:dragStartCursorY) / $script:dragDpiY

    if (-not $script:dragMoved -and ([Math]::Sqrt($dxDip*$dxDip + $dyDip*$dyDip) -gt 4)) {
        $script:dragMoved = $true
    }
    if ($script:dragMoved) {
        $next = Clamp-ToScreen ($script:dragStartLeft + $dxDip) ($script:dragStartTop + $dyDip)
        $window.Left = $next[0]
        $window.Top = $next[1]
    }
})

$Girl.Add_MouseLeftButtonUp({
    param($s, $e)
    if (-not $script:isDragging) { return }
    $script:isDragging = $false
    $Girl.ReleaseMouseCapture()
    $PressScale.ScaleX = 1.0
    $PressScale.ScaleY = 1.0
    Play-Sfx "release"

    if (-not $script:dragMoved) {
        Set-BubbleMode "quota"
    } else {
        # Evaluate facing direction on drop so cursor never separates during drag
        $dpi = Get-WindowDpiScale
        $cxPx = [int][Math]::Round(($window.Left + $window.Width / 2.0) * $dpi[0])
        $cyPx = [int][Math]::Round(($window.Top + $window.Height / 2.0) * $dpi[1])
        $scr = [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new($cxPx, $cyPx))
        $midX = ($scr.WorkingArea.Left + $scr.WorkingArea.Width / 2.0) / $dpi[0]
        if (($window.Left + $window.Width / 2.0) -lt $midX) {
            $FacingScale.ScaleX = -1
            $TextFacingScale.ScaleX = -1
        } else {
            $FacingScale.ScaleX = 1
            $TextFacingScale.ScaleX = 1
        }
        $afterFlip = Clamp-ToScreen $window.Left $window.Top
        $window.Left = $afterFlip[0]
        $window.Top = $afterFlip[1]

        # Update Antigravity follow offsets if currently in follow mode
        if ($script:config.displayMode -eq "follow") {
            $hwnd = [AgyWin32]::FindAntigravityWindow()
            if ($hwnd -ne [IntPtr]::Zero) {
                $rect = New-Object AgyWin32+RECT
                if ([AgyWin32]::GetWindowRect($hwnd, [ref]$rect)) {
                    $script:offsetRight = ($rect.Right / $dpi[0]) - $window.Width - $window.Left
                    $script:offsetBottom = ($rect.Bottom / $dpi[1]) - $window.Height - $window.Top
                }
            }
        }
    }
})

# Bubble Click: Quota -> Quote -> Hidden
$Bubble.Add_MouseLeftButtonUp({
    param($s, $e)
    if ($e.OriginalSource -is [System.Windows.Controls.Button]) { return }
    Play-Sfx "release"
    if ($script:bubbleState -eq "quota") {
        Show-Quote (Pick-RandomQuote)
    } elseif ($script:bubbleState -eq "quote") {
        Set-BubbleMode "hidden"
    }
})

$RefreshBtn.Add_Click({
    Play-Sfx "release"
    Refresh-LocalStats
    Reset-AutoHide
})

# Ctrl + MouseWheel quick zoom on catgirl (60% - 250%)
$window.Add_MouseWheel({
    param($s, $e)
    if (([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0) {
        $step = if ($e.Delta -gt 0) { 5 } else { -5 }
        $script:config.scale = [Math]::Max(60, [Math]::Min(250, [int]$script:config.scale + $step))
        Apply-Scale
        Save-Config
        $e.Handled = $true
    }
})

# Right-Click Native Context Menu
$menu = New-Object System.Windows.Controls.ContextMenu

function Add-MenuItem([string]$header, [scriptblock]$action) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $header
    $mi.Add_Click($action)
    $menu.Items.Add($mi) | Out-Null
    return $mi
}

Add-MenuItem "🐱 我是啥喵？" { Show-Quote "我是啥喵？" } | Out-Null
Add-MenuItem "📊 查看剩余额度" { Set-BubbleMode "quota" } | Out-Null
Add-MenuItem "💬 换一句猫娘语录" { Show-Quote (Pick-RandomQuote) } | Out-Null
Add-MenuItem "↻ 刷新额度估算" { Refresh-LocalStats } | Out-Null
$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
Add-MenuItem "🪟 跟随 Antigravity 窗口" { $script:config.displayMode = "follow"; Save-Config } | Out-Null
Add-MenuItem "🖥️ 桌面自由拖动模式" { $script:config.displayMode = "desktop"; Save-Config } | Out-Null
Add-MenuItem "🧱 开关屏幕边界碰撞限制" {
    $script:config.keepInsideScreen = -not [bool]$script:config.keepInsideScreen
    $pos = Clamp-ToScreen $window.Left $window.Top
    $window.Left = $pos[0]; $window.Top = $pos[1]
    Save-Config
} | Out-Null
Add-MenuItem "📌 切换始终置顶" { $script:config.topmost = -not [bool]$script:config.topmost; $window.Topmost = [bool]$script:config.topmost; Save-Config } | Out-Null
$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
Add-MenuItem "📐 自定义大小（滑块 60%-250%）..." { Open-SizeDialog } | Out-Null
Add-MenuItem "🔍 快捷缩放 80%" { $script:config.scale = 80; Apply-Scale; Save-Config } | Out-Null
Add-MenuItem "🔍 快捷缩放 100%" { $script:config.scale = 100; Apply-Scale; Save-Config } | Out-Null
Add-MenuItem "🔍 快捷缩放 140%" { $script:config.scale = 140; Apply-Scale; Save-Config } | Out-Null
Add-MenuItem "🔊 开关提示音" { $script:config.muted = -not [bool]$script:config.muted; Save-Config } | Out-Null
Add-MenuItem "🎵 开关音乐律动（自动检测电脑音频）" {
    $script:config.musicRhythm = -not [bool]$script:config.musicRhythm
    Save-Config
    if (-not [bool]$script:config.musicRhythm -and $null -ne $GirlDanceScale) {
        $GirlDanceScale.ScaleX = 1.0
        $GirlDanceScale.ScaleY = 1.0
    }
    Show-Quote ($(if ($script:config.musicRhythm) { "音乐律动已开启！放首歌听听喵♪" } else { "已关闭音乐律动喵。" }))
} | Out-Null
Add-MenuItem "🔔 开关回答结束提醒" {
    $script:config.replyNotifyEnabled = -not [bool]$script:config.replyNotifyEnabled
    Save-Config
    Show-Quote ($(if ($script:config.replyNotifyEnabled) { "已开启回答结束提醒喵！" } else { "已关闭回答结束提醒喵。" }))
} | Out-Null
$aqMenu = New-Object System.Windows.Controls.MenuItem
$aqMenu.Header = "💬 自动语录间隔"
foreach ($opt in @(
    @{ label = "关闭自动语录"; mins = 0 },
    @{ label = "每 5 分钟"; mins = 5 },
    @{ label = "每 10 分钟"; mins = 10 },
    @{ label = "每 30 分钟（半小时）"; mins = 30 }
)) {
    $sub = New-Object System.Windows.Controls.MenuItem
    $sub.Header = $opt.label
    $sub.Tag = $opt.mins
    $sub.Add_Click({
        param($s, $e)
        $m = [int]$s.Tag
        $script:config.autoQuoteEnabled = ($m -gt 0)
        if ($m -gt 0) { $script:config.autoQuoteMinutes = $m }
        Save-Config
        Sync-AutoQuoteTimer
        Show-Quote ($(if ($m -gt 0) { "已开启每 $m 分钟自动语录喵～" } else { "已关闭自动语录喵。" }))
    })
    $aqMenu.Items.Add($sub) | Out-Null
}
$menu.Items.Add($aqMenu) | Out-Null
$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
Add-MenuItem "📂 打开语录与配置目录" { Start-Process explorer.exe $SharedDir } | Out-Null
Add-MenuItem "❌ 退出 GPT-喵 悬浮挂件" { $window.Close() } | Out-Null

$Girl.ContextMenu = $menu

# Follow Antigravity Window & Config Hot-Reload Timer (300ms)
$followTimer = New-Object System.Windows.Threading.DispatcherTimer
$followTimer.Interval = [TimeSpan]::FromMilliseconds(350)
$followTimer.Add_Tick({
    Load-Config
    if ($script:isDragging) { return }
    if ($script:config.displayMode -eq "follow") {
        $hwnd = [AgyWin32]::FindAntigravityWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            if ([AgyWin32]::IsIconic($hwnd)) {
                if ($window.Visibility -eq "Visible") { $window.Visibility = "Hidden" }
            } else {
                if ($window.Visibility -ne "Visible") { $window.Visibility = "Visible" }
                $rect = New-Object AgyWin32+RECT
                if ([AgyWin32]::GetWindowRect($hwnd, [ref]$rect)) {
                    $dpi = Get-WindowDpiScale
                    $rawLeft = ($rect.Right / $dpi[0]) - $window.Width - $script:offsetRight
                    $rawTop = ($rect.Bottom / $dpi[1]) - $window.Height - $script:offsetBottom
                    $clamped = Clamp-ToScreen $rawLeft $rawTop
                    if ([Math]::Abs($window.Left - $clamped[0]) -gt 2) { $window.Left = $clamped[0] }
                    if ([Math]::Abs($window.Top - $clamped[1]) -gt 2) { $window.Top = $clamped[1] }
                }
            }
        } else {
            if ($window.Visibility -ne "Visible") { $window.Visibility = "Visible" }
        }
    } else {
        if ($window.Visibility -ne "Visible") { $window.Visibility = "Visible" }
    }
})
$followTimer.Start()

# Auto-Quote Timer (Optional: 5 / 10 / 30 min)
$script:autoQuoteTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:autoQuoteTimer.Add_Tick({
    if (-not [bool]$script:config.autoQuoteEnabled) { return }
    if ($script:isDragging -or $script:bubbleState -eq "quota") { return }
    Play-Sfx "release"
    Show-Quote (Pick-RandomQuote)
})
function Sync-AutoQuoteTimer {
    if ($null -eq $script:autoQuoteTimer) { return }
    $script:autoQuoteTimer.Stop()
    if ([bool]$script:config.autoQuoteEnabled) {
        $mins = [int]$script:config.autoQuoteMinutes
        if ($mins -notin @(5, 10, 30)) { $mins = 5 }
        $script:autoQuoteTimer.Interval = [TimeSpan]::FromMinutes($mins)
        $script:autoQuoteTimer.Start()
    }
}
Sync-AutoQuoteTimer

# Reply-Finished Reminder Watcher (checks ONLY the very last JSONL entry, deduplicated by step_index)
$script:notifiedStepByConv = @{}
function Check-ReplyCompletion {
    $brainDir = Join-Path $env:USERPROFILE ".gemini\antigravity\brain"
    if (-not (Test-Path $brainDir)) { return }
    $cutoff = [DateTime]::UtcNow.AddMinutes(-15)
    $triggered = $false
    foreach ($dir in Get-ChildItem -Path $brainDir -Directory -ErrorAction SilentlyContinue) {
        $log = Join-Path $dir.FullName ".system_generated\logs\transcript.jsonl"
        if (-not (Test-Path $log)) { continue }
        $fi = Get-Item $log -ErrorAction SilentlyContinue
        if (-not $fi -or $fi.LastWriteTimeUtc -lt $cutoff) { continue }
        $key = $dir.Name
        $len = $fi.Length
        $prevLen = if ($script:knownReplyLengths.ContainsKey($key)) { [long]$script:knownReplyLengths[$key] } else { -1L }
        if ($len -eq $prevLen) { continue }
        $script:knownReplyLengths[$key] = $len

        try {
            $lastLine = Get-Content -Path $log -Tail 1 -Encoding UTF8 -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($lastLine)) { continue }
            $o = $lastLine | ConvertFrom-Json
            if (-not $script:replyBaselineReady) {
                $script:notifiedStepByConv[$key] = [int]$o.step_index
                continue
            }
            $hasTools = ($null -ne $o.tool_calls -and $o.tool_calls.Count -gt 0)
            $hasText = (-not [string]::IsNullOrWhiteSpace([string]$o.content))
            $stepIdx = [int]$o.step_index
            $lastNotified = if ($script:notifiedStepByConv.ContainsKey($key)) { [int]$script:notifiedStepByConv[$key] } else { -1 }

            if ($o.type -eq "PLANNER_RESPONSE" -and $o.status -eq "DONE" -and (-not $hasTools) -and $hasText -and $stepIdx -gt $lastNotified) {
                $script:notifiedStepByConv[$key] = $stepIdx
                $triggered = $true
            }
        } catch {}
    }
    if (-not $script:replyBaselineReady) {
        $script:replyBaselineReady = $true
        return
    }
    if ($triggered) {
        Refresh-LocalStats
        if ([bool]$script:config.replyNotifyEnabled -and -not $script:isDragging) {
            Play-Sfx "release"
            Show-Quote "回答完啦喵～快来看看！"
        }
    }
}
Check-ReplyCompletion

# Automatic Quota Refresh (every 5s, no manual click needed) & Reply Watcher (every 2s)
$script:tickCounter = 0
$statsTimer = New-Object System.Windows.Threading.DispatcherTimer
$statsTimer.Interval = [TimeSpan]::FromSeconds(2)
$statsTimer.Add_Tick({
    Check-ReplyCompletion
    $script:tickCounter++
    if (($script:tickCounter % 3) -eq 0) {
        Refresh-LocalStats
    }
})
$statsTimer.Start()

# Smooth Musical Rhythm Timer (~30 FPS): detects PC audio presence, drives silky Q-bounce on Girl only
$script:rhythmIntensity = 0.0
$script:smoothLoudness = 0.0
$script:musicPhase = 0.0
$script:lastAudioSeenUtc = [DateTime]::MinValue
$musicTimer = New-Object System.Windows.Threading.DispatcherTimer
$musicTimer.Interval = [TimeSpan]::FromMilliseconds(33)
$musicTimer.Add_Tick({
    if ($null -eq $GirlDanceScale) { return }
    if ($script:isDragging -or (-not [bool]$script:config.musicRhythm)) {
        if ($script:rhythmIntensity -gt 0.002) {
            $script:rhythmIntensity = 0.0
            $GirlDanceScale.ScaleX = 1.0
            $GirlDanceScale.ScaleY = 1.0
        }
        return
    }

    $peak = [double][AgyAudioMeter]::GetSystemPeak()
    $now = [DateTime]::UtcNow
    if ($peak -ge 0.012) {
        $script:lastAudioSeenUtc = $now
        $script:smoothLoudness = ($script:smoothLoudness * 0.90) + ([Math]::Min(1.0, $peak * 2.2) * 0.10)
    }

    $isPlaying = (($now - $script:lastAudioSeenUtc).TotalMilliseconds -lt 650)
    if ($isPlaying) {
        # Smoothly ramp intensity up (0.65..1.05 based on gentle loudness envelope, never jittery!)
        $targetAmp = 0.65 + (0.40 * $script:smoothLoudness)
        $script:rhythmIntensity = ($script:rhythmIntensity * 0.88) + ($targetAmp * 0.12)
        # Silky ~122 BPM squash-and-stretch wave matching the prototype preview
        $script:musicPhase += 0.42
        if ($script:musicPhase -gt 628.318) { $script:musicPhase -= 628.318 }
        $w = [Math]::Sin($script:musicPhase)
        $GirlDanceScale.ScaleX = 1.0 + (0.045 * $script:rhythmIntensity * $w)
        $GirlDanceScale.ScaleY = 1.0 - (0.055 * $script:rhythmIntensity * $w)
    } else {
        # Smoothly settle back to rest when PC is silent
        $script:smoothLoudness *= 0.85
        if ($script:rhythmIntensity -gt 0.004) {
            $script:rhythmIntensity *= 0.86
            $script:musicPhase += 0.25
            $w = [Math]::Sin($script:musicPhase)
            $GirlDanceScale.ScaleX = 1.0 + (0.045 * $script:rhythmIntensity * $w)
            $GirlDanceScale.ScaleY = 1.0 - (0.055 * $script:rhythmIntensity * $w)
        } elseif ($GirlDanceScale.ScaleX -ne 1.0 -or $GirlDanceScale.ScaleY -ne 1.0) {
            $script:rhythmIntensity = 0.0
            $GirlDanceScale.ScaleX = 1.0
            $GirlDanceScale.ScaleY = 1.0
        }
    }
})
$musicTimer.Start()

$window.Add_Closed({
    $followTimer.Stop()
    $statsTimer.Stop()
    $musicTimer.Stop()
    $script:autoQuoteTimer.Stop()
    $script:hideTimer.Stop()
    Remove-Item -Path $PidFile -Force -ErrorAction SilentlyContinue
})

Show-Quote "我是啥喵？"
$window.ShowDialog() | Out-Null
