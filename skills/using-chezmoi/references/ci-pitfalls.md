# CI Pitfalls (GitHub Actions)

Issues that only surface when running `chezmoi apply` inside a CI pipeline. Most examples are GitHub Actions; the underlying causes apply to any CI.

## 1. GitHub Actions YAML quoting

Any `run:` value starting with `"` is parsed as a YAML double-quoted string where `\` is an escape and `|` has special meaning — so a PowerShell one-liner that begins with a quoted env var will be mangled:

```yaml
# WRONG — leading " makes YAML interpret the whole value
- run: "$env:USERPROFILE\.local\bin" | Out-File -Append "$env:GITHUB_PATH"

# CORRECT — block scalar preserves the string verbatim
- run: |
    "$env:USERPROFILE\.local\bin" | Out-File -Append "$env:GITHUB_PATH"
```

Rule of thumb: always use `run: |` for PowerShell steps.

## 2. Windows runners: set execution policy before `chezmoi apply`

Even when your `.chezmoi.yaml.tmpl` configures `pwsh` with `-ExecutionPolicy Bypass` (see `windows-pitfalls.md` item 1), the CI runner's *current* session still has its default policy, which can block `chezmoi apply` itself from invoking downstream scripts. Set it explicitly:

```yaml
- name: Allow PowerShell scripts
  if: runner.os == 'Windows'
  shell: pwsh
  run: Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force
```

## 3. Windows runners: refresh PATH after `winget install`

`winget` updates the User PATH in the registry, but GitHub Actions doesn't re-read the registry between steps — installed tools are missing from PATH in later steps. After a `winget` step, write the merged PATH back to `$GITHUB_PATH`:

```yaml
- name: Refresh PATH from registry
  shell: pwsh
  run: |
    $user = [Environment]::GetEnvironmentVariable("PATH", "User")
    $machine = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    "$machine;$user" -split ';' | Where-Object { $_ } | Sort-Object -Unique | Out-File -Append "$env:GITHUB_PATH"
```
