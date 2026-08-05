param(
    [ValidateRange(1, 1000000)]
    [int]$PreviewLine = 1,

    [ValidateRange(800, 3840)]
    [int]$Width = 1440,

    [ValidateRange(600, 2160)]
    [int]$Height = 900,

    [ValidateRange(1, 30)]
    [int]$RenderWaitSeconds = 5,

    [string]$CaptureCommand = "CaptureGraphicsWin2D",

    [switch]$DiscoverOnly,

    [switch]$All,

    [switch]$MissingOnly
)

$ErrorActionPreference = "Stop"

function Get-ThemeCaptureDefinitions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtensionsRoot
    )

    $definitions = @()

    foreach ($extensionDir in (Get-ChildItem $ExtensionsRoot -Directory | Sort-Object Name)) {
        $manifestPath = Join-Path $extensionDir.FullName "package.json"

        if (-not (Test-Path $manifestPath -PathType Leaf)) {
            continue
        }

        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

        foreach ($theme in @($manifest.contributes.themes)) {
            $themePath = Join-Path $extensionDir.FullName ($theme.path -replace '^\./', '')

            if (-not (Test-Path $themePath -PathType Leaf)) {
                throw "Theme file not found for '$($theme.label)': $themePath"
            }

            $themeJson = Get-Content $themePath -Raw | ConvertFrom-Json
            if ($themeJson.name -ne $theme.label) {
                throw "Theme name mismatch in '$themePath': manifest label '$($theme.label)' does not match JSON name '$($themeJson.name)'."
            }

            $previewName = [System.IO.Path]::GetFileNameWithoutExtension($themePath) -replace '-color-theme$', ''

            $definitions += [pscustomobject]@{
                Name       = $theme.label
                Family     = $extensionDir.Name
                SourceDir  = $extensionDir.FullName
                OutputPath = "images/previews/$previewName.png"
            }
        }
    }

    if ($definitions.Count -eq 0) {
        throw "No registered themes were found under: $ExtensionsRoot"
    }

    return $definitions
}

function Select-ThemeCaptureDefinitions {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Definitions,

        [switch]$All,

        [switch]$MissingOnly
    )

    if ($All -and $MissingOnly) {
        throw "The -All and -MissingOnly options cannot be used together."
    }

    if ($All) {
        return $Definitions
    }

    if ($MissingOnly) {
        return @($Definitions | Where-Object { -not $_.PreviewExists })
    }

    Write-Host "Select a theme to capture:" -ForegroundColor Cyan
    for ($index = 0; $index -lt $Definitions.Count; $index++) {
        Write-Host "  $($index + 1). $($Definitions[$index].Name)"
    }

    $missingIndex = $Definitions.Count + 1
    $allIndex = $Definitions.Count + 2
    Write-Host "  $missingIndex. Missing previews"
    Write-Host "  $allIndex. All"

    do {
        $selection = Read-Host "Enter a number"
        $validSelection = $selection -match '^\d+$' -and
            [int]$selection -ge 1 -and
            [int]$selection -le $allIndex

        if (-not $validSelection) {
            Write-Warning "Enter a number from 1 to $allIndex."
        }
    } while (-not $validSelection)

    $selectedIndex = [int]$selection - 1
    if ($selectedIndex -eq $Definitions.Count) {
        return @($Definitions | Where-Object { -not $_.PreviewExists })
    }

    if ($selectedIndex -eq ($Definitions.Count + 1)) {
        return $Definitions
    }

    return @($Definitions[$selectedIndex])
}

function New-CaptureWorkspace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $directories = @(
        ".github/workflows",
        ".vscode",
        "config",
        "docs",
        "public",
        "scripts",
        "src/components",
        "src/features",
        "src/hooks",
        "src/lib",
        "src/services",
        "src/styles",
        "src/types",
        "tests"
    )

    foreach ($directory in $directories) {
        New-Item -ItemType Directory -Force -Path (Join-Path $DestinationPath $directory) |
            Out-Null
    }

    $emptyFiles = @(
        ".editorconfig",
        ".gitignore",
        ".vscode/extensions.json",
        ".vscode/settings.json",
        ".github/workflows/ci.yml",
        "README.md",
        "package.json",
        "package-lock.json",
        "tsconfig.json",
        "vite.config.ts",
        "eslint.config.js",
        "config/env.example",
        "docs/architecture.md",
        "docs/contributing.md",
        "public/favicon.svg",
        "public/index.html",
        "scripts/build.ts",
        "scripts/generate-types.ts",
        "src/app.ts",
        "src/main.ts",
        "src/components/Button.tsx",
        "src/components/Card.tsx",
        "src/components/Header.tsx",
        "src/components/Modal.tsx",
        "src/features/dashboard.ts",
        "src/features/settings.ts",
        "src/hooks/useData.ts",
        "src/hooks/useTheme.ts",
        "src/lib/constants.ts",
        "src/lib/logger.ts",
        "src/services/api.ts",
        "src/services/auth.ts",
        "src/styles/global.css",
        "src/styles/tokens.css",
        "src/types/api.ts",
        "src/types/index.ts",
        "tests/app.test.ts",
        "tests/components.test.tsx",
        "tests/setup.ts"
    )

    foreach ($file in $emptyFiles) {
        New-Item -ItemType File -Force -Path (Join-Path $DestinationPath $file) |
            Out-Null
    }

    $captureShowcaseFile = Join-Path $DestinationPath "src/showcase.ts"
    $previewContent = @'
/**
 * A small, self-contained fixture used for theme previews.
 * It intentionally includes common TypeScript syntax and a few quiet details
 * that make editor colors easy to compare across themes.
 */
type ProjectStatus = "active" | "paused" | "archived";

interface Project {
    id: number;
    name: string;
    status: ProjectStatus;
    tags: string[];
    private: boolean;
}

const projects: Project[] = [
    {
        id: 1,
        name: "Wake the stars",
        status: "active",
        tags: ["design", "focus"],
        private: false,
    },
    {
        id: 2,
        name: "Quiet Hours",
        status: "paused",
        tags: ["research"],
        private: true,
    },
];

const describeProject = (project: Project): string => {
    const visibility = project.private ? "private" : "public";
    return `${project.name} (${visibility}) — ${project.tags.join(", ")}`;
};

async function loadSummary(items: Project[]): Promise<string> {
    // Pretend this came from an API so async keywords and error handling are
    // represented in the capture fixture.
    const response = await Promise.resolve({ ok: true, items });

    if (!response.ok) {
        throw new Error("Unable to load project summary");
    }

    return response.items
        .filter((project) => project.status !== "archived")
        .map(describeProject)
        .join("\n");
}

export async function renderShowcase(): Promise<void> {
    const summary = await loadSummary(projects);
    console.log("Project summary:\n" + summary);
}

void renderShowcase();
'@

    Set-Content -LiteralPath $captureShowcaseFile -Value $previewContent -Encoding UTF8

    return $captureShowcaseFile
}

$extensionsRoot = Join-Path $PSScriptRoot "..\extensions"
if (-not (Test-Path $extensionsRoot -PathType Container)) {
    throw "Could not locate the extensions directory next to the script: $extensionsRoot"
}

$extensionsRoot = (Resolve-Path $extensionsRoot).Path

$themeDefinitions = Get-ThemeCaptureDefinitions -ExtensionsRoot $extensionsRoot
$themeDefinitions | ForEach-Object {
    $_ | Add-Member -NotePropertyName PreviewExists `
        -NotePropertyValue (Test-Path (
                Join-Path (Join-Path $extensionsRoot $_.Family) $_.OutputPath
            ) -PathType Leaf)
}

if ($MissingOnly -and $All) {
    throw "The -All and -MissingOnly options cannot be used together."
}

if ($DiscoverOnly) {
    $themeDefinitions |
    Select-Object Name, Family, OutputPath |
    Format-Table -AutoSize
    return
}

$themesToCapture = Select-ThemeCaptureDefinitions `
    -Definitions $themeDefinitions `
    -All:$All `
    -MissingOnly:$MissingOnly

if ($themesToCapture.Count -eq 0) {
    Write-Host "All discovered themes already have previews." -ForegroundColor Green
    return
}

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

$dataDir = Join-Path $env:TEMP "xiomesh-vscode-theme-capture"
if (Test-Path $dataDir) {
    Remove-Item $dataDir -Recurse -Force
}

$settingsDir = Join-Path $dataDir "User"
$extensionsDir = Join-Path $dataDir "extensions"
$captureTempDir = Join-Path $dataDir "captures"
$captureWorkspaceDir = Join-Path $dataDir "workspace"

New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
New-Item -ItemType Directory -Force -Path $extensionsDir | Out-Null
New-Item -ItemType Directory -Force -Path $captureTempDir | Out-Null
New-Item -ItemType Directory -Force -Path $captureWorkspaceDir | Out-Null

$captureShowcaseFile = New-CaptureWorkspace `
    -DestinationPath $captureWorkspaceDir

$settingsPath = Join-Path $settingsDir "settings.json"

# Load all theme extensions directly from this repository.
$extensionSources = $themeDefinitions |
    Select-Object -ExpandProperty SourceDir -Unique

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

foreach ($theme in $themesToCapture) {
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

    $gotoTarget = "${captureShowcaseFile}:$PreviewLine:1"

    $arguments = @(
        "--user-data-dir", $dataDir,
        "--extensions-dir", $extensionsDir,
        "--new-window",
        "--skip-add-to-recently-opened",
        $captureWorkspaceDir,
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
