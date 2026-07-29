param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$PreviewFile,

    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$Workspace = (Get-Location).Path,

    [string]$OutputDir = (Join-Path (Get-Location).Path "extensions"),

    [ValidateRange(1, 1000000)]
    [int]$PreviewLine = 1,

    [ValidateRange(800, 3840)]
    [int]$Width = 1440,

    [ValidateRange(600, 2160)]
    [int]$Height = 900,

    [ValidateRange(1, 30)]
    [int]$RenderWaitSeconds = 5,

    [string]$CaptureCommand = "CaptureGraphicsWin2D"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class ThemeShotNative
{
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags
    );

    [DllImport("user32.dll")]
    public static extern bool PostMessage(
        IntPtr hWnd,
        uint Msg,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(
        IntPtr hWnd,
        StringBuilder lpString,
        int nMaxCount
    );

    public static string ReadWindowTitle(IntPtr hWnd)
    {
        var text = new StringBuilder(1024);
        GetWindowText(hWnd, text, text.Capacity);
        return text.ToString();
    }
}
"@

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + $Value.Replace('"', '\"') + '"'
}

function Get-VisibleCodeWindows {
    @(Get-Process -Name "Code" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 })
}

function Wait-NewCodeWindow {
    param(
        [long[]]$ExistingHandles,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        foreach ($process in Get-VisibleCodeWindows) {
            $handle = [long]$process.MainWindowHandle

            if ($ExistingHandles -notcontains $handle) {
                return $process
            }
        }

        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for the isolated VS Code window."
}

function Wait-WindowTitle {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$Handle,
        [Parameter(Mandatory = $true)][string]$ExpectedTitle,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastTitle = ""

    do {
        $lastTitle = [ThemeShotNative]::ReadWindowTitle($Handle)

        if ($lastTitle -eq $ExpectedTitle) {
            return
        }

        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    throw "VS Code did not adopt the capture title '$ExpectedTitle'. Current title: '$lastTitle'"
}

$themes = @(
    [pscustomobject]@{
        Name        = "Blueprint Carbon"
        Family      = "blueprint"
        OutputPath  = "images/previews/carbon.png"
    },
    [pscustomobject]@{
        Name        = "Blueprint Graphite"
        Family      = "blueprint"
        OutputPath  = "images/previews/graphite.png"
    },
    [pscustomobject]@{
        Name        = "Blueprint Paper"
        Family      = "blueprint"
        OutputPath  = "images/previews/paper.png"
    },
    [pscustomobject]@{
        Name        = "Mindful Curiosity"
        Family      = "mindful"
        OutputPath  = "images/previews/curiosity.png"
    },
    [pscustomobject]@{
        Name        = "Mindful Insight"
        Family      = "mindful"
        OutputPath  = "images/previews/insight.png"
    }
)



$codeCommand = Get-Command "code" -ErrorAction Stop
$codeExecutable = $codeCommand.Source

$captureCommandInfo = Get-Command $CaptureCommand -ErrorAction SilentlyContinue
if (-not $captureCommandInfo) {
    throw @"
CaptureGraphicsWin2D was not found on PATH.

Confirm the Microsoft Store app execution alias is enabled, then test:
    Get-Command CaptureGraphicsWin2D

You can also pass an explicit executable or alias with:
    -CaptureCommand "C:\path\to\CaptureGraphicsWin2D.exe"
"@
}
$captureExecutable = $captureCommandInfo.Source
if ([string]::IsNullOrWhiteSpace($captureExecutable)) {
    $captureExecutable = $captureCommandInfo.Name
}

$PreviewFile = (Resolve-Path $PreviewFile).Path
$Workspace = (Resolve-Path $Workspace).Path
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

# Accept either the repository root or the extensions folder.
if (Test-Path (Join-Path $OutputDir "blueprint") -PathType Container) {
    $extensionsRoot = $OutputDir
}
elseif (Test-Path (Join-Path $OutputDir "extensions") -PathType Container) {
    $extensionsRoot = Join-Path $OutputDir "extensions"
}
else {
    throw "Could not locate the extensions root from OutputDir: $OutputDir"
}

$dataDir = Join-Path $env:TEMP "xiomesh-vscode-theme-capture"
if (Test-Path $dataDir) {
    Remove-Item $dataDir -Recurse -Force
}

$settingsDir = Join-Path $dataDir "User"
$extensionsDir = Join-Path $dataDir "extensions"
$captureTempDir = Join-Path $dataDir "captures"

New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
New-Item -ItemType Directory -Force -Path $extensionsDir | Out-Null
New-Item -ItemType Directory -Force -Path $captureTempDir | Out-Null

$settingsPath = Join-Path $settingsDir "settings.json"

# Load the theme extensions directly from this repository.
$extensionSources = @(
    (Join-Path $Workspace "extensions\blueprint"),
    (Join-Path $Workspace "extensions\mindful")
)

foreach ($sourceDir in $extensionSources) {
    $manifestPath = Join-Path $sourceDir "package.json"

    if (-not (Test-Path $manifestPath -PathType Leaf)) {
        throw "Theme extension manifest not found: $manifestPath"
    }

    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $folderName = "$($manifest.publisher).$($manifest.name)-$($manifest.version)"
    $destinationDir = Join-Path $extensionsDir $folderName

    Copy-Item -Path $sourceDir -Destination $destinationDir -Recurse -Force

    Remove-Item (Join-Path $destinationDir ".vscode") `
        -Recurse -Force -ErrorAction SilentlyContinue

    Get-ChildItem $destinationDir -Filter "*.vsix" -File `
        -ErrorAction SilentlyContinue |
    Remove-Item -Force
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$windowWidth = [Math]::Min($Width, $screen.Width - 40)
$windowHeight = [Math]::Min($Height, $screen.Height - 40)
$windowX = $screen.Left + [Math]::Max(
    0,
    [int](($screen.Width - $windowWidth) / 2)
)
$windowY = $screen.Top + [Math]::Max(
    0,
    [int](($screen.Height - $windowHeight) / 2)
)

$captureWindowTitle = "Theme Preview"

foreach ($theme in $themes) {
    Write-Host "Capturing $($theme.Name)..." -ForegroundColor Cyan

    $settings = [ordered]@{
        "workbench.colorTheme"                         = $theme.Name
        "window.title"                                 = $captureWindowTitle
        "workbench.startupEditor"                      = "none"
        "workbench.editor.enablePreview"               = $false
        "workbench.commandCenter"                      = $false
        "workbench.layoutControl.enabled"              = $false
        "workbench.secondarySideBar.defaultVisibility" = "hidden"
        "chat.disableAIFeatures"                       = $true
        "window.titleBarStyle"                         = "custom"
        "window.restoreWindows"                        = "none"
        "editor.fontSize"                              = 16
        "editor.lineHeight"                            = 24
        "editor.minimap.enabled"                       = $false
        "editor.scrollBeyondLastLine"                  = $false
        "editor.renderWhitespace"                      = "selection"
        "breadcrumbs.enabled"                          = $false
        "explorer.openEditors.visible"                 = 0
        "extensions.ignoreRecommendations"             = $true
        "extensions.autoCheckUpdates"                  = $false
        "extensions.autoUpdate"                        = $false
        "security.workspace.trust.enabled"             = $false
        "telemetry.telemetryLevel"                     = "off"
        "update.mode"                                  = "none"
        "update.showReleaseNotes"                      = $false
        "workbench.tips.enabled"                       = $false
    }

    $settings |
    ConvertTo-Json -Depth 10 |
    Set-Content -Path $settingsPath -Encoding UTF8

    $existingHandles = @(
        Get-VisibleCodeWindows |
        ForEach-Object { [long]$_.MainWindowHandle }
    )

    $gotoTarget = "${PreviewFile}:$PreviewLine:1"

    $arguments = @(
        "--user-data-dir", $dataDir,
        "--extensions-dir", $extensionsDir,
        "--new-window",
        "--skip-add-to-recently-opened",
        $Workspace,
        "--goto", $gotoTarget
    )

    $argumentLine = ($arguments |
        ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "

    Start-Process -FilePath $codeExecutable `
        -ArgumentList $argumentLine |
    Out-Null

    $windowProcess = Wait-NewCodeWindow -ExistingHandles $existingHandles
    $handle = [IntPtr]$windowProcess.MainWindowHandle

    # Restore, size, center, and foreground the target window.
    [void][ThemeShotNative]::ShowWindowAsync($handle, 9)
    [void][ThemeShotNative]::SetWindowPos(
        $handle,
        [IntPtr]::Zero,
        $windowX,
        $windowY,
        $windowWidth,
        $windowHeight,
        0x0040
    )
    [void][ThemeShotNative]::SetForegroundWindow($handle)

    Start-Sleep -Milliseconds 1200

    # Suppress/dismiss unexpected first-run UI.
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
    Start-Sleep -Milliseconds 350

    # Ensure Explorer is visible, then focus the editor.
    [System.Windows.Forms.SendKeys]::SendWait("^+e")
    Start-Sleep -Milliseconds 400
    [System.Windows.Forms.SendKeys]::SendWait("^1")

    Wait-WindowTitle -Handle $handle -ExpectedTitle $captureWindowTitle
    Start-Sleep -Seconds $RenderWaitSeconds

    # CaptureGraphicsWin2D targets the exact VS Code window title and emits a
    # transparent PNG of that window only.
    Get-ChildItem $captureTempDir -Filter "*.png" -File `
        -ErrorAction SilentlyContinue |
    Remove-Item -Force

    & $captureExecutable $captureTempDir $captureWindowTitle

    $captured = Get-ChildItem $captureTempDir -Filter "*.png" -File |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

    if (-not $captured) {
        throw "CaptureGraphicsWin2D did not create a PNG for '$($theme.Name)'."
    }

    $familyRoot = Join-Path $extensionsRoot $theme.Family
    if (-not (Test-Path $familyRoot -PathType Container)) {
        throw "Extension folder not found for family '$($theme.Family)': $familyRoot"
    }

    $destination = Join-Path $familyRoot $theme.OutputPath
    $destinationDir = Split-Path $destination -Parent
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null

    Copy-Item $captured.FullName $destination -Force

    Write-Host "  Saved $destination" -ForegroundColor Green

    # Close only the isolated screenshot window.
    [void][ThemeShotNative]::PostMessage(
        $handle,
        0x0010,
        [IntPtr]::Zero,
        [IntPtr]::Zero
    )

    $closeDeadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 250
        $stillOpen = Get-VisibleCodeWindows |
        Where-Object {
            [long]$_.MainWindowHandle -eq [long]$handle
        }
    } while ($stillOpen -and (Get-Date) -lt $closeDeadline)

    if ($stillOpen) {
        Write-Warning "The VS Code capture window did not close promptly."
        break
    }
}

Write-Host ""
Write-Host "Finished. Theme previews were written under: $extensionsRoot" `
    -ForegroundColor Green
