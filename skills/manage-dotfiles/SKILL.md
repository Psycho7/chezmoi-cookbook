---
name: manage-dotfiles
description: >-
  Manages dotfiles via chezmoi. Use when working with chezmoi-managed dotfiles -
  .chezmoiignore semantics, run_once_/modify_ scripts, or troubleshooting
  chezmoi apply/diff across macOS, Linux, Windows, CI. Also use when the user
  edits files under `~/.local/share/chezmoi/` or mentions
  `chezmoi add/edit/forget/remove` or `.chezmoidata/`, even without naming
  chezmoi explicitly.
---

# Chezmoi Dotfiles Management

## 1. Mental Model

Chezmoi operates over three distinct states (terms match chezmoi's own glossary), and most mistakes come from conflating them:

- **source** — files under `~/.local/share/chezmoi/` (or the configured source directory), typically carrying attribute prefixes such as `dot_`, suffixes such as `.tmpl`, or script prefixes such as `run_` and `modify_`. This is the version-controlled representation.
- **destination** — paths under `$HOME` (e.g. `~/.zshrc`), the actual files currently on disk. This is what other programs read right now, and what `chezmoi apply` writes to.
- **target** — the expected/rendered content for each destination path, computed from source after attribute stripping, template expansion, and modify-script execution. Derived and ephemeral: it is what chezmoi *would* write during `chezmoi apply`, not something stored anywhere.

| State | Where it lives | When chezmoi writes to it |
|---|---|---|
| Source | `~/.local/share/chezmoi/...` | `chezmoi add`, `chezmoi edit` |
| Destination | `~/...` (under `$HOME`) | `chezmoi apply` |
| Target | (derived, ephemeral) | computed during `chezmoi apply` |

`chezmoi diff` compares destination state (what's on disk right now) with target state (what `chezmoi apply` would produce). A non-empty diff signals drift between these two states, not a change over time.

> LLMs (and humans) reliably confuse these three states. Before reading or writing any file, confirm which state you are touching.

---

## 2. Choosing the Right Approach

Before creating or modifying a file, walk this decision tree:

```
Is the file identical on all platforms?
  YES → Plain copy (no .tmpl, no modify_)
  NO → Does chezmoi own the entire file?
    YES → Go template (.tmpl)
    NO → modify_ script (file is shared with programs/users)
      Is it structured data (JSON/YAML/TOML)?
        YES, simple key merge → modify_ with jq/yq deep merge
        YES, fine-grained control → modify_ with chezmoi:modify-template + setValueAtPath
        NO (line-based text) → modify_ with managed-block markers
```

### Don't edit managed files directly

If `chezmoi managed` lists a path, always edit the source via `chezmoi edit <path>` — this opens a hardlinked tmp file, so your edits flow back into the source tree. Direct edits to the file under `$HOME` (e.g. `$EDITOR ~/.zshrc`) are **lost on the next `chezmoi apply`**, silently.

```bash
chezmoi managed | grep -q '^\.zshrc$' && chezmoi edit ~/.zshrc
# not: $EDITOR ~/.zshrc
```

Before `chezmoi add <path>`, check `chezmoi managed`. If the path is already tracked, edit the source instead. Specifically: `chezmoi add` on a path whose source is a `.tmpl` silently **destroys the template** — it overwrites the `.tmpl` source with the raw destination content (what's currently in `$HOME`), discarding any Go-template logic.

```bash
chezmoi managed | grep -q '^\.foo$' || chezmoi add ~/.foo
# if already managed, use `chezmoi edit ~/.foo` instead
```

> To stop managing a file entirely (not just re-edit it), see `§10 › Unmanaging a file`.

### `chezmoi add` flags and gotchas

| Flag | What it does | Gotcha |
|---|---|---|
| `--template` / `-T` | Mark the file as a Go template; source gets `.tmpl` suffix | Edit the source thereafter; `chezmoi add` on a templated path overwrites the template (see above) |
| `--autotemplate` / `-a` | Auto-generate a template by substituting known data values into the added content | Per chezmoi docs: "uses a greedy algorithm which occasionally generates templates with unwanted variable substitutions" — review every generated template by hand |
| `--encrypt` | Encrypt the file with the configured backend before storing as source | Requires `encryption` configured in `chezmoi.toml` (`age` or `gpg`) |
| `--secrets <action>` | Fail or warn if added content looks like a secret. Values: `ignore` / `warning` (default) / `error` | Set to `error` in CI to catch accidental commits |
| `--template-symlinks` | Render symlink targets as templates using `.chezmoi.sourceDir` / `.chezmoi.homeDir` | Without this, absolute symlink targets get baked in literally and break on other machines |
| `--recursive` / `-r` | Walk into directories | Combine carefully with `--exact` (see footgun below) |
| `--exact` | Mark added directories `exact_`, so `chezmoi apply` removes anything not managed under them | Foot-gun on shared parents (see below) |

#### Foot-gun: `chezmoi add --exact --recursive` over a shared parent

`chezmoi add --exact --recursive ~/.config/nvim` adds `~/.config` as a
managed parent dir **with the `exact_` attribute applied to every parent
in the walk**, including `~/.config` itself. The next `chezmoi apply`
deletes every unmanaged sibling under `~/.config` — your other apps'
configs, gone.

Mitigations, in order of preference:

1. **Drop `--exact` when adding nested paths under a shared parent.** Add
   the leaf normally; if you need `exact_` only at the leaf, edit the
   source-side directory attribute afterwards (rename `nvim/` →
   `exact_nvim/`).
2. **Add only the deepest directory you actually want `exact_` on.** Let
   parents stay non-`exact_`. Skip `--recursive` if the directory is small.
3. **Community workaround (not in official docs):** seed the parent with
   a dummy file first
   (`touch ~/.config/.keep && chezmoi add ~/.config/.keep`), then add the
   leaf with `--exact --recursive`. The parent is added without the
   `exact_` attribute because of the prior `add` call.

### Quick reference

| Scenario | Source file pattern |
|---|---|
| Identical everywhere | `dot_editorconfig` |
| OS/machine-conditional sections | `dot_zshrc.tmpl` |
| Excluded on some OSes | `.chezmoiignore` entry |
| Partial JSON (add/override keys) | `modify_settings.json` (bash+jq) |
| Partial JSON/YAML/TOML (fine-grained) | `modify_` with `chezmoi:modify-template` |
| Partial text (shared with user) | `modify_` with managed-block markers |
| Package installation | `.chezmoiscripts/run_once_before_*.sh.tmpl` |
| Post-apply reload | `.chezmoiscripts/run_onchange_after_*` |

---

## 3. Data Hierarchy

Chezmoi merges template data from two layers (later overrides earlier):

1. **Static** — `.chezmoidata/` directory or top-level `.chezmoidata.$FORMAT` file at the source root. Shared across all machines, and these files cannot themselves be templates.
2. **Config `[data]`** — machine-specific values, written into `.chezmoi.toml.tmpl` at `chezmoi init` (typically populated via `promptString` / `promptBool`).

Verify with: `chezmoi data | jq .`

For init-time bootstrap (config templates with `promptStringOnce`) and profile-based configuration patterns, read `references/data-and-profiles.md` in this skill's directory.

---

## 4. Go Templates

Use `.tmpl` suffix when the file needs OS or machine-specific sections:

```
{{- if eq .chezmoi.os "darwin" }}
...macOS content...
{{- else if eq .chezmoi.os "linux" }}
...Linux content...
{{- else if eq .chezmoi.os "windows" }}
...Windows content...
{{- end }}
```

Place reusable snippets in `.chezmoitemplates/` and include with `{{ template "name.tmpl" . }}`. Always pass `.` explicitly.

---

## 5. Modify Scripts

### 5a. Managed-block pattern (text files)

The preferred pattern for config files that users also edit manually:

1. Read current file from stdin
2. Strip existing managed block (between `BEGIN` / `END` markers)
3. Rebuild managed block with chezmoi-controlled content
4. Output: preserved user content + new managed block

Rules:
- **Idempotency**: Modify scripts run on every `chezmoi apply`. Trim trailing blank lines before appending the managed block to prevent accumulation across repeated applies.
- **Interpreter**: Use bash even when targeting fish/zsh — chezmoi runs modify scripts before the target shell may be installed.
- **Templates**: Add `.tmpl` suffix for OS-conditional content inside the managed block.

### 5b. JSON deep merge (jq)

```bash
#!/bin/bash
MANAGED='{ "key": "value" }'
jq -s '.[0] * .[1]' - <(echo "$MANAGED")
```

### 5c. In-process modify-template

No external interpreter needed — works on all platforms:

```
{{- /* chezmoi:modify-template */ -}}
{{- $c := .chezmoi.stdin | fromToml -}}
{{- $c = $c | setValueAtPath "key" "value" -}}
{{- $c | toToml -}}
```

Parsers: `fromJson`/`toJson`/`toPrettyJson`, `fromYaml`/`toYaml`, `fromToml`/`toToml`.

For detailed examples of all modify patterns, read `references/modify-scripts.md` in this skill's directory.

---

## 6. .chezmoiignore

A Go template. Patterns match **target paths** (after `dot_`/`.tmpl`/`run_once_` stripping), not source filenames:

```
# CORRECT — target paths
{{- if ne .chezmoi.os "windows" }}
Documents/PowerShell
{{- end }}

# WRONG — source-style names silently never match:
# dot_config/fish          ← should be .config/fish
# run_once_00_install.ps1  ← should be 00_install.ps1
```

> Managing `~/.claude/` (user-level Claude Code config)? See the `manage-claude-config` skill for the authoritative track/ignore list and the `~/.claude.json` vs `~/.claude/settings.json` gotcha.

---

## 7. Run Scripts

| Prefix | Behavior |
|---|---|
| `run_before_` / `run_after_` | Before/after file deployment |
| `run_once_` | Only when content hash changes |
| `run_onchange_` | When referenced content changes |

Combine: `run_once_before_10-install-packages.sh.tmpl`

Use separate `.sh.tmpl` and `.ps1.tmpl` for cross-platform installs. For `run_onchange_`, embed a hash: `# hash: {{ include "dot_zshrc.tmpl" | sha256sum }}`.

Hooks (`hooks.*.pre/post` in config) run even on `--dry-run` — avoid destructive actions in hooks.

### Guard external tool invocations

Modify and run scripts execute on fresh machines where referenced tools may not be installed yet. Guard every invocation:

```powershell
# PowerShell
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
```

```bash
# bash
command -v starship &>/dev/null && eval "$(starship init bash)"
```

```fish
# fish
type -q starship && starship init fish | source
```

---

## 8. Platform & CI Pitfalls

Three reference files cover non-obvious failure modes. Read them when touching the relevant area:

- `references/windows-pitfalls.md` — Windows and PowerShell gotchas: configure `pwsh` with `-ExecutionPolicy Bypass`; `0..-1` is `@(0, -1)` not empty, use `Select-Object -SkipLast`; path/config layout differences; don't `winget install` the running PowerShell.
- `references/ci-pitfalls.md` — GitHub Actions issues: always `run: |` for PowerShell (leading `"` makes YAML mangle the line); set `Set-ExecutionPolicy Bypass` before `chezmoi apply` on Windows runners; refresh PATH from registry after `winget install`.

For the modify-script double-extension trap (cross-platform, most commonly hit on Windows with `.ps1` targets), see `references/modify-scripts.md`.

---

## 9. Init and Cross-Machine Sync

There is **no `chezmoi sync` command**. Cross-machine syncing is two
half-loops:

- **Producer (machine you edited on):** `chezmoi git -- add .`, `chezmoi git -- commit -m '...'`, `chezmoi git -- push`. Anything inside `~/.local/share/chezmoi/` is a normal git repo, so `chezmoi git -- <args>` is just a passthrough.
- **Consumer (every other machine):** `chezmoi update`. This runs `git pull --autostash --rebase` followed by `chezmoi apply`.

### Optional auto-commit / auto-push on the producer

```toml
# ~/.config/chezmoi/chezmoi.toml
[git]
    autoCommit = true
    autoPush   = true
```

`autoPush` implies `autoCommit`. Override the auto-generated commit
message via `git.commitMessageTemplate` (inline) or
`git.commitMessageTemplateFile` (path to a longer template, relative to
the source directory).

> **Public repo + `autoPush` + plaintext secret = leaked secret on
> push.** If the source repo is publishable, encrypt or externalize
> every secret (age recipients, password-manager template refs, or
> `private_` + `0600` outside the repo) before enabling these.

### Bootstrap on a new machine

```bash
# Conservative — apply only after reviewing the diff
chezmoi init https://github.com/USER/dotfiles.git
chezmoi diff
chezmoi apply

# Fast path — init, pull data, apply in one shot
chezmoi init --apply --verbose https://github.com/USER/dotfiles.git
```

If the source repo contains a `.chezmoi.<format>.tmpl` (see
`references/data-and-profiles.md` § "Bootstrap with
`.chezmoi.<format>.tmpl`"), `chezmoi init` prompts for any
`promptStringOnce` values it finds and persists them into the new
local config.

---

## 10. Troubleshooting

```bash
chezmoi diff                    # Preview changes
chezmoi doctor                  # Diagnose issues
chezmoi data | jq .             # Show template data
chezmoi cat ~/.gitconfig        # Test-render a file
chezmoi managed --include=all   # List managed files
```

### Gotcha: `chezmoi edit --apply` does not run `run_` scripts

`chezmoi edit --apply <path>` writes the edited source through to its destination. It does **not** re-run `run_once_`, `run_onchange_`, or `run_` scripts, so any downstream state they produce (package installs, service restarts, generated files) stays stale. Follow with a bare `chezmoi apply` to trigger the full script suite.

### Unmanaging a file

Deleting a managed file directly (e.g. `rm ~/.foo`) does **not** stop chezmoi from managing it — the next `chezmoi apply` recreates it from the source. Adding a `.chezmoiignore` entry *after* a file is already managed also does not retroactively unmanage it: ignore patterns filter the source tree during apply-time traversal, they do not untrack existing sources.

| Command | What it does | Use when |
|---|---|---|
| `chezmoi forget <path>` | Removes the source; leaves the destination file in place | You want to keep the file on disk but stop tracking it |
| `chezmoi remove <path>` | Removes both source and destination file | You want the file gone entirely |

> For how to *edit* a managed file correctly, see `§2 › Don't edit managed files directly`.

---

## 11. Recommended Layout

```
source-root/
├── .chezmoi.toml.tmpl
├── .chezmoiignore
├── .chezmoidata/defaults.yaml
├── .chezmoitemplates/*.tmpl
├── .chezmoiscripts/run_once_before_*.sh.tmpl
├── dot_gitconfig.tmpl              # dot_ → . in target
├── dot_editorconfig
├── modify_dot_config/app/settings.json
└── private_dot_ssh/config          # private_ → 0600 permissions
```

If using `.chezmoiroot`, the source state lives under that subdirectory — and `.chezmoi.yaml.tmpl` / `.chezmoi.toml.tmpl` must live **inside** that subdirectory, not at the repo root. A config template at the repo root is silently ignored when `.chezmoiroot` is set.

```
repo-root/
  .chezmoiroot          ← contains "home"
  home/
    .chezmoi.yaml.tmpl   ← MUST be here, not at repo root
```
