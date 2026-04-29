# Modify Scripts — Detailed Examples

## Double-extension trap (applies on every OS)

Chezmoi strips recognized interpreter extensions from modify script filenames before computing the target path. If the target *also* has one of these extensions, you must double it:

```
modify_Microsoft.PowerShell_profile.ps1      → Microsoft.PowerShell_profile  (WRONG)
modify_Microsoft.PowerShell_profile.ps1.ps1  → Microsoft.PowerShell_profile.ps1  (CORRECT)

modify_my-helper.sh                          → my-helper                      (WRONG)
modify_my-helper.sh.sh                       → my-helper.sh                   (CORRECT)
```

Recognized extensions: `.sh`, `.ps1`, `.py`, `.pl`, `.rb`, `.nu`. This is cross-platform — most often seen on Windows because `.ps1` profile files are the common case, but `.sh`/`.py` targets are affected on Unix too.

## Managed-block pattern (bash)

```bash
#!/bin/bash
# modify_dot_config/fish/config.fish
set -e

BEGIN_MARKER='# BEGIN chezmoi managed'
END_MARKER='# END chezmoi managed'

existing=$(cat)

managed=()
managed+=("$BEGIN_MARKER")
managed+=('fish_add_path $HOME/.local/bin')
managed+=('starship init fish | source')
managed+=("$END_MARKER")

# Strip existing managed block and collect non-managed lines
output=""
in_block=0
while IFS= read -r line; do
    if [ "$line" = "$BEGIN_MARKER" ]; then
        in_block=1
    elif [ "$line" = "$END_MARKER" ]; then
        in_block=0
    elif [ "$in_block" -eq 0 ]; then
        output="$output$line"$'\n'
    fi
done <<< "$existing"

# Trim trailing blank lines to prevent accumulation on repeated applies
while [[ "$output" == *$'\n'$'\n' ]]; do
    output="${output%$'\n'}"
done

# Output preserved content, then managed block
printf '%s\n' "$output"
for line in "${managed[@]}"; do
    printf '%s\n' "$line"
done
```

## Managed-block pattern (PowerShell)

PowerShell requires extra care for idempotency:

```powershell
#!/usr/bin/env pwsh
# modify_Microsoft.PowerShell_profile.ps1.ps1
# Note the doubled .ps1 extension (target file is .ps1)

$BeginMarker = '# BEGIN chezmoi managed'
$EndMarker = '# END chezmoi managed'
$existing = @($input)

$managed = @(
  $BeginMarker
  'Invoke-Expression (&starship init powershell | Out-String)'
  $EndMarker
)

# Strip existing managed block
$output = @()
$inBlock = $false
foreach ($line in $existing) {
  if ($line -eq $BeginMarker) { $inBlock = $true }
  elseif ($line -eq $EndMarker) { $inBlock = $false }
  elseif (-not $inBlock) { $output += $line }
}

# Trim trailing blanks to prevent accumulation
while ($output.Count -gt 0 -and $output[-1] -eq '') {
  $output = @($output | Select-Object -SkipLast 1)
}
if ($output.Count -gt 0) { $output += '' }
$output += $managed

$output | ForEach-Object { $_ }
```

## JSON deep merge with jq

**Important**: `jq -s '.[0] * .[1]'` does a deep merge where objects are merged recursively, but **arrays are replaced entirely**. Choose the right approach:

### Object-only merge (arrays get replaced)

Use when your managed keys are all scalars or objects — no arrays the user might add to:

```bash
#!/bin/bash
# modify_dot_config/app/config.json

MANAGED='{ "theme": "dark", "editor": { "fontSize": 14 } }'
jq -s '.[0] * .[1]' - <(echo "$MANAGED")
```

### Additive array merge (arrays are unioned)

Use when you need to add items to arrays without removing user-added entries (e.g., permissions, plugins):

```bash
#!/bin/bash
# modify_dot_claude/settings.json

baseline='["WebSearch", "Bash(git status:*)"]'

existing=$(cat)
[ -z "$existing" ] && existing='{}'

echo "$existing" | jq --argjson baseline "$baseline" '
  .permissions.allow = ((.permissions.allow // []) + $baseline | unique)
'
```

## chezmoi:modify-template (in-process, cross-platform)

### Partial JSON

```
# modify_dot_config/Code/User/settings.json
{{- /* chezmoi:modify-template */ -}}
{{- $s := .chezmoi.stdin | fromJson -}}
{{- $s = $s | setValueAtPath "editor.fontSize" 14 -}}
{{- $s = $s | setValueAtPath "editor.formatOnSave" true -}}
{{- if eq .chezmoi.os "darwin" -}}
{{-   $s = $s | setValueAtPath "editor.fontFamily" "SF Mono" -}}
{{- else -}}
{{-   $s = $s | setValueAtPath "editor.fontFamily" "Fira Code" -}}
{{- end -}}
{{- $s | toPrettyJson -}}
```

### Partial TOML

```
# modify_dot_config/starship.toml
{{- /* chezmoi:modify-template */ -}}
{{- $c := .chezmoi.stdin | fromToml -}}
{{- $c = $c | setValueAtPath "add_newline" true -}}
{{- $c = $c | setValueAtPath "character.success_symbol" "[➜](bold green)" -}}
{{- $c | toToml -}}
```

### Text file with marker blocks (regex)

```
# modify_dot_ssh/config
{{- /* chezmoi:modify-template */ -}}
{{- $begin := "# BEGIN CHEZMOI MANAGED" -}}
{{- $end   := "# END CHEZMOI MANAGED" -}}
{{- $managed := printf "%s\nHost github.com\n    User git\n%s" $begin $end -}}
{{- $content := .chezmoi.stdin -}}
{{- if regexMatch $begin $content -}}
{{-   regexReplaceAll (printf "(?s)%s.*?%s" $begin $end) $content $managed -}}
{{- else -}}
{{-   printf "%s\n%s\n" $content $managed -}}
{{- end -}}
```

## Python modify script

Use for complex transformations that Go templates can't handle cleanly:

```python
# modify_dot_config/Code/User/keybindings.json.py
import sys, json

current = sys.stdin.read().strip()
bindings = json.loads(current) if current else []

managed = [
    {"key": "ctrl+shift+p", "command": "workbench.action.showCommands", "_managed_by": "chezmoi"},
]

user_bindings = [b for b in bindings if b.get("_managed_by") != "chezmoi"]
print(json.dumps(managed + user_bindings, indent=4))
```

## Python + .tmpl (OS-conditional logic)

The `.tmpl` is rendered first (Go template), then `.py` triggers Python:

```python
# modify_dot_npmrc.py.tmpl
import sys
content = sys.stdin.read()
lines = [l for l in content.splitlines() if not l.startswith("registry=")]
{{ if eq .profile "work" -}}
lines.append("registry=https://npm.example.com/")
{{ else -}}
lines.append("registry=https://registry.npmjs.org/")
{{ end -}}
print("\n".join(lines))
```

## Interpreter configuration

```toml
# .chezmoi.toml.tmpl
{{ if eq .chezmoi.os "windows" -}}
[interpreters.py]
    command = "py"
    args = ["-3"]
{{ else -}}
[interpreters.py]
    command = "python3"
{{ end -}}
```
