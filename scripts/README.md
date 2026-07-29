# Theme Preview Scripts

Generates consistent screenshots for every VS Code theme in this repository.

## Requirements

- Windows 11
- VS Code `code` command available on `PATH`
- CaptureGraphicsWin2D installed with its command alias enabled

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\capture-theme-previews.ps1 `
  -PreviewFile "C:\path\to\sample.ts" `
  -Workspace "C:\path\to\vscode-themes"
```

Screenshots are saved to `screenshots/`.
