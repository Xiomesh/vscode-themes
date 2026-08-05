# Theme Preview Scripts

Generates consistent screenshots for every VS Code theme in this repository.

## Requirements

- Windows 11
- VS Code `code` command available on `PATH`
- CaptureGraphicsWin2D installed with its command alias enabled

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\capture-theme-previews.ps1
```

Previews are saved to each extension’s `images/previews/` directory.

Each capture uses a temporary mock workspace with a realistic project tree.
The script generates a TypeScript showcase at `src/showcase.ts`; the
surrounding files are intentionally empty so the Explorer looks like a project
without exposing this repository’s files or Git branch.

When run normally, the script discovers all registered themes and prompts you
to choose one. Select **All** to capture every theme. Use `-All` to skip the
prompt and capture every theme directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\capture-theme-previews.ps1 -All
```

Use `-MissingOnly` to capture only themes whose expected preview PNG does not
exist yet:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\capture-theme-previews.ps1 -MissingOnly
```

Use `-DiscoverOnly` to list discovered themes without opening VS Code or
capturing files.
