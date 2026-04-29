# Bootstrap, Data Hierarchy, and Profile-Based Configuration

## Bootstrap with `.chezmoi.<format>.tmpl`

When `chezmoi init` runs against a source repo containing
`.chezmoi.toml.tmpl` (or `.chezmoi.yaml.tmpl` / `.chezmoi.json.tmpl`),
chezmoi renders that template once and writes the result to
`~/.config/chezmoi/chezmoi.<format>` on the new machine. This is the
ergonomic path for "set up a new laptop in one command" — the template
prompts the user for machine-local data (email, profile, hostname
suffix, …) and persists the answers into the per-machine config.

### Prompt functions

All of these are available **only** during init-template rendering, not
in regular templates:

| Function | Returns |
|---|---|
| `promptString` / `promptStringOnce` | string |
| `promptBool` / `promptBoolOnce` | bool |
| `promptInt` / `promptIntOnce` | int |
| `promptChoice` / `promptChoiceOnce` | one value from a fixed list |
| `promptMultichoice` / `promptMultichoiceOnce` | list of values |

The `*Once` variants prompt **only when the corresponding key is not
already present in the existing config map** — i.e., they read the
existing `~/.config/chezmoi/chezmoi.<format>` (if any) and skip the
prompt when the value is already there. They do not track "first time
on this machine" as a separate flag, so blowing away `chezmoi.toml`
re-prompts.

### Minimal example

```toml
# .chezmoi.toml.tmpl  — committed to the repo
{{- $email   := promptStringOnce . "email" "Git email address" -}}
{{- $profile := promptChoiceOnce . "profile" "Machine profile"
                  (list "personal" "work" "server") -}}

[data]
    email   = {{ $email   | quote }}
    profile = {{ $profile | quote }}
```

After `chezmoi init` on a fresh machine, the user is prompted twice and
`~/.config/chezmoi/chezmoi.toml` ends up with:

```toml
[data]
    email   = "me@example.com"
    profile = "work"
```

Subsequent `chezmoi init` runs on the same machine see those keys
already set and don't prompt again.

> The rendered config (`~/.config/chezmoi/chezmoi.<format>`) lives
> outside the source repo. If a `promptString` answer is sensitive,
> ensure that file is `0600` — and prefer not writing plaintext
> secrets into it at all (use `onepasswordRead`, `bitwardenFields`,
> etc., from regular templates instead).

---

## Profile system

Define profiles in `.chezmoidata/` with per-profile settings, then select in the config template:

```yaml
# .chezmoidata/defaults.yaml
profiles:
  personal:
    email: "me@home.com"
    install_gui: true
    install_docker: false
  work:
    email: "me@corp.com"
    install_gui: true
    install_docker: true
  server:
    email: "admin@srv.com"
    install_gui: false
    install_docker: true

packages:
  common:
    - git
    - neovim
    - ripgrep
```

## Boolean flags derived from OS and profile

Combine profile selection and derived flags into a single `[data]` block (TOML doesn't allow duplicate section headers):

```toml
# .chezmoi.toml.tmpl — complete example
{{- $profile := "personal" -}}
{{- if eq .chezmoi.hostname "work-laptop" "work-desktop" -}}
{{-   $profile = "work" -}}
{{- else if hasPrefix "srv-" .chezmoi.hostname -}}
{{-   $profile = "server" -}}
{{- else if stdinIsATTY -}}
{{-   $profile = promptChoiceOnce . "profile" "Machine profile"
        (list "personal" "work" "server") -}}
{{- end }}

{{- $p := index .profiles $profile -}}

[data]
    profile        = {{ $profile | quote }}
    is_windows     = {{ eq .chezmoi.os "windows" }}
    is_mac         = {{ eq .chezmoi.os "darwin" }}
    is_linux       = {{ eq .chezmoi.os "linux" }}
    email          = {{ $p.email | quote }}
    install_gui    = {{ $p.install_gui }}
    install_docker = {{ $p.install_docker }}
```

Templates then use these flags directly:

```
# dot_gitconfig.tmpl
[user]
    email = {{ .email }}
{{ if .install_gui -}}
[diff]
    tool = vscode
{{ end -}}
```

## Testing your data

```bash
chezmoi data | jq '.profile, .email, .is_windows'
chezmoi execute-template '{{ .profile }} on {{ .chezmoi.os }}'
```
