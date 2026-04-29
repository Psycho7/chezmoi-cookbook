# chezmoi-cookbook

A [Claude Code](https://claude.ai/code) plugin for [chezmoi](https://www.chezmoi.io/), the dotfile manager. It teaches Claude the chezmoi behaviors that aren't in the official docs (the ones buried in GitHub issues and forum posts), and adds two hooks that catch common ways to break a managed file.

## What it provides

- **File type decision tree**: when to use plain copy, `.tmpl`, or `modify_` scripts
- **`chezmoi add` flag matrix**: `--template`, `--autotemplate` (with the greedy-substitution warning), `--encrypt`, `--secrets`, `--template-symlinks`, plus the `--exact --recursive` parent-directory foot-gun and three documented mitigations
- **Modify script patterns**: managed-block (bash and PowerShell), JSON deep merge with `jq`, `chezmoi:modify-template`, Python scripts
- **Mental model**: source vs destination vs target states (chezmoi's glossary), and what `chezmoi diff` compares
- **Don't edit managed files**: always edit source via `chezmoi edit`, never the file under `$HOME`
- **Apply-loop trap**: `chezmoi edit --apply` does not run `run_` scripts; follow with a bare `chezmoi apply`
- **Unmanaging files**: `chezmoi forget` (keep the file on disk) vs `chezmoi remove` (delete both source and destination)
- **Bootstrap and data**: `.chezmoi.<format>.tmpl` with `promptStringOnce` for new-machine init; profile-based config, boolean flags, testing template data
- **Cross-machine sync**: there is no `chezmoi sync`. Producer pushes via `chezmoi git -- push`, consumer pulls via `chezmoi update`. Optional `git.autoCommit` / `autoPush`
- **`.chezmoiignore` gotchas**: target paths vs source paths (the most common mistake)
- **Run script conventions**: `run_once_`, `run_onchange_`, cross-platform installs
- **Windows & PowerShell pitfalls**: `pwsh` execution policy, array range semantics, path/config differences
- **CI pitfalls**: GitHub Actions YAML quoting, Windows runner execution policy, refreshing PATH after `winget install`
- **Troubleshooting**: `chezmoi diff`, `chezmoi doctor`, `chezmoi data`
- **Syncing `~/.claude/` with chezmoi**: which files in the user-level config are portable vs per-machine runtime vs secrets, with a ready-made `.chezmoiignore` block

## Installation

```
/plugin marketplace add Psycho7/chezmoi-cookbook
```

Skills activate on their own when you're working in a chezmoi-managed repo or with `~/.claude/`. To invoke explicitly:

```
/chezmoi-cookbook:using-chezmoi     # chezmoi mechanics, patterns, pitfalls
/chezmoi-cookbook:claude-dotfiles   # syncing ~/.claude/ with chezmoi
```

## Commands

### `/chezmoi-cookbook:bootstrap`

A read-only diagnostic. It detects the host OS and prints the matching install one-liner (it does not run it). If chezmoi is already installed, it runs `chezmoi doctor` and only surfaces three things: `pwsh` on Windows, `git`, and any `error:` line. The rest of the doctor output, including `age`, `gpg`, and password-manager warnings, is filtered out on purpose — the install command and any secrets tooling are the user's call, not the plugin's.

```
/chezmoi-cookbook:bootstrap
```

No arguments.

## Hooks

### `block-managed-edits` (PreToolUse on Edit/Write)

Before every `Edit` or `Write`, the hook checks whether the target path is in `chezmoi managed --path-style=absolute --include=files`. If yes, it denies the tool call and tells Claude to use `chezmoi edit <path>`. Why bother: direct edits to managed targets get silently overwritten on the next `chezmoi apply`, and that's a frustrating bug to hit twice.

Unmanaged paths pass through. So does everything if `chezmoi` isn't on `PATH` or the command errors — the hook fails open, so dropping this plugin onto a machine without chezmoi doesn't break editing.

macOS and Linux only. It's a bash script that needs `jq`. On Windows without a POSIX shell on `PATH` the automatic guard is unavailable, but the rule itself (don't edit managed targets) still applies; Claude just won't get the safety net.

To disable:

- For one shell or project, export `CHEZMOI_COOKBOOK_NO_GUARD=1`. The script checks this var and lets the edit through.
- For the whole plugin, in `~/.claude/settings.json`:
  ```json
  {
    "enabledPlugins": {
      "chezmoi-cookbook@Psycho7/chezmoi-cookbook": false
    }
  }
  ```
  (Confirm the exact `plugin@marketplace` key with `/plugins`.)
- For every hook everywhere, set `"disableAllHooks": true` in `settings.json`. That's nuclear; it affects every plugin.

### `validate-source-changes` (PostToolUse on Edit/Write)

After every `Edit` or `Write`, if the changed file is a `.tmpl` under `chezmoi source-path`, the hook runs `chezmoi execute-template` against it. If the render fails, the error is fed back to Claude as `additionalContext`, so the next turn sees it. Non-template edits, and edits outside the source dir, pass through silently.

One caveat. The render-test reads from stdin, so `.chezmoitemplates/` includes and filename-attribute logic don't resolve. Standalone `.tmpl` files render fine; templates that pull in shared partials via `{{ template "..." . }}` will false-positive. Set `CHEZMOI_COOKBOOK_NO_VALIDATE=1` per file or session when you're working on those.

Otherwise, same fail-open, same macOS/Linux constraint, same whole-plugin and all-hooks switches as `block-managed-edits`.

## Contents

| File | Description |
|---|---|
| `skills/using-chezmoi/SKILL.md` | Core decision tree, quick reference, and section summaries |
| `skills/claude-dotfiles/SKILL.md` | Track/ignore decisions for syncing `~/.claude/` and `~/.claude.json` with chezmoi |
| `skills/using-chezmoi/references/modify-scripts.md` | Full examples of every modify pattern, plus the double-extension trap |
| `skills/using-chezmoi/references/data-and-profiles.md` | `.chezmoi.<format>.tmpl` bootstrap, profile-based config, data hierarchy |
| `skills/using-chezmoi/references/windows-pitfalls.md` | Windows and PowerShell host-level gotchas |
| `skills/using-chezmoi/references/ci-pitfalls.md` | GitHub Actions pitfalls (YAML quoting, execution policy, PATH refresh) |
| `commands/bootstrap.md` | `/chezmoi-cookbook:bootstrap` slash command |
| `hooks/hooks.json` | Plugin hook registration |
| `hooks/block-managed-edits.sh` | `PreToolUse(Edit\|Write)` guard script |
| `hooks/validate-source-changes.sh` | `PostToolUse(Edit\|Write)` template render-test |

## Compatibility

Targets chezmoi v2.x. Templates, modify scripts, and ignore rules are stable across v2 releases.

## License

MIT
