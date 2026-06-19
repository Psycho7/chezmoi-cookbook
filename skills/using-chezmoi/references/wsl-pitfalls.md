# WSL Pitfalls

Gotchas specific to running chezmoi inside WSL (Windows Subsystem for
Linux). For Windows-native PowerShell issues, see `windows-pitfalls.md`.
For CI runner specifics (including Windows runners), see `ci-pitfalls.md`.

## 1. Detecting WSL from a template

WSL kernels expose a `Microsoft` substring in `/proc/sys/kernel/osrelease`.
Both capitalizations occur (WSL1 ships `Microsoft`, WSL2 ships
`microsoft`), so always lowercase before matching:

```
{{- if and (eq .chezmoi.os "linux") (.chezmoi.kernel.osrelease | lower | contains "microsoft") -}}
# WSL-specific content
{{- end -}}
```

`.chezmoi.kernel` is Linux-only (it reads `/proc/sys/kernel`), so guard
with `eq .chezmoi.os "linux"` first or the template fails on macOS.

## 2. Repo placement: prefer the Linux filesystem over `/mnt/c`

Keep your chezmoi source repo inside the Linux filesystem (default
`~/.local/share/chezmoi`), **not** under `/mnt/c/...`. Cross-filesystem
operations under `/mnt/c` are slow, and Windows ACL semantics leak
through the 9P protocol in surprising ways: `chmod` may not stick,
breaking chezmoi's `0600` checks on `private_` paths, and case-only
filename collisions become possible (see §4).

This is general WSL guidance from Microsoft's WSL docs, not a
chezmoi-specific recommendation. chezmoi works either way; the
Linux-side layout just has fewer rough edges.

## 3. Line endings: pin LF in `.gitattributes`

If the same chezmoi repo is ever cloned from both Windows-native Git and
WSL-side Git, Windows-side checkouts will introduce CRLF on text files
while WSL-side checkouts stay LF, producing endless drift in `chezmoi
diff`. Pin LF for shell, PowerShell, and template files at the repo
root:

```
* text=auto eol=lf
*.ps1 text eol=lf
*.sh text eol=lf
*.tmpl text eol=lf
```

PowerShell scripts run fine with LF on Windows. The only files that
genuinely need CRLF are Windows batch files (`.bat`, `.cmd`).

## 4. Case sensitivity drift between Linux fs and `/mnt/c`

The Linux ext4 filesystem under WSL is case-sensitive; mounted Windows
drives (`/mnt/c`, `\\wsl$\...`) inherit Windows's case-insensitive
semantics unless you explicitly opt in with
`fsutil.exe file setCaseSensitiveInfo`.

Avoid filenames that differ only by case (e.g. `Config.toml` vs
`config.toml`) anywhere in the chezmoi source tree. They behave fine on
the Linux side but collide silently the moment the repo is checked out
on the Windows side.

## 5. PowerShell-in-WSL profile path is Linux-style

If you install `pwsh` *inside* the WSL distro and run it there, its
profile follows the Linux convention:

```
~/.config/powershell/Microsoft.PowerShell_profile.ps1
```

This is **not** the same as the Windows-native PowerShell 7 profile
under `Documents/PowerShell/...` (see `windows-pitfalls.md` §3 for the
host comparison table). A common mistake is copy-pasting the
Windows-side profile path into a WSL-side template, or vice versa, and
having the profile silently fail to load because nothing exists at the
expected path.

If you need both PowerShell profiles managed from one chezmoi repo,
treat them as two separate target paths and gate each with the WSL
detection from §1.
