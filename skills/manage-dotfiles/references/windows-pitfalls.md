# Windows & PowerShell Pitfalls

Gotchas that only bite on Windows hosts or when writing PowerShell. For GitHub Actions / CI-specific issues (including Windows-in-CI), see `ci-pitfalls.md`.

## 1. Use PowerShell 7 (`pwsh`), not Windows PowerShell 5.1

Chezmoi defaults to `pwsh` for `.ps1` scripts, falling back to `powershell.exe` (5.1) if not found. PowerShell 5.1 defaults to `Restricted` execution policy — scripts silently fail.

Configure explicitly:

```yaml
# .chezmoi.yaml.tmpl
{{- if eq .chezmoi.os "windows" }}
interpreters:
  ps1:
    command: pwsh
    args:
      - "-NoLogo"
      - "-NoProfile"
      - "-NonInteractive"
      - "-ExecutionPolicy"
      - "Bypass"
      - "-File"
{{- end }}
```

## 2. PowerShell array range semantics

The `..` range operator counts *through* negative indices instead of producing an empty array. This is a PowerShell language quirk (applies on Linux/macOS too), but you'll almost always meet it on Windows:

```powershell
0..3      # @(0, 1, 2, 3)
0..0      # @(0)
0..-1     # @(0, -1) — NOT empty!
```

Use `Select-Object -SkipLast N`:

```powershell
# WRONG
$output = $output[0..($output.Count - 2)]

# CORRECT
$output = @($output | Select-Object -SkipLast 1)
```

## 3. Path and config differences

| Concept | Unix | Windows |
|---|---|---|
| Home directory | `$HOME` | `$env:USERPROFILE` |
| PATH separator | `:` | `;` |
| Path separator | `/` | `\` (use `Join-Path`) |
| Profile location | `~/.config/...` | `~/Documents/PowerShell/...` |
| Config directory | `~/.config/` | `~/Documents/` or `~/AppData/` |

## 4. Don't install the running shell

A `run_once_` PowerShell script that tries to `winget install Microsoft.PowerShell` will fail — the MSI can't upgrade a running process. PowerShell is already installed if your script is running. (Unix package managers generally tolerate reinstalling the running shell; the MSI-based Windows installers do not.)
