---
name: manage-claude-config
description: >-
  Syncs user-level Claude Code config across machines via chezmoi. Use when
  managing `~/.claude/` - track/ignore decisions, credentials split, `plugins/`
  churn, `settings.local.json`. Not for project-level `.claude/` inside a repo.
---

# Syncing ~/.claude/ with chezmoi

## 1. Scope

This skill covers **user-level** Claude Code configuration only:

- `~/.claude/` — the directory in `$HOME`
- `~/.claude.json` — a single file at the root of `$HOME` (not inside `.claude/`)

It does **not** cover project-level `.claude/` directories inside a repository. Those are scoped to one project and belong in that project's own git history, not in dotfiles. If the task is about `<repo>/.claude/settings.json` or similar, stop. This skill does not apply, and the file should be tracked in the repo's own git instead.

> Two files are reliably confused: `~/.claude.json` and `~/.claude/settings.json` are **different files**. The former lives at `$HOME` root and holds OAuth sessions, MCP state, and auto-managed caches (ignore it). The latter lives inside the `.claude/` directory and holds portable user preferences (track it).

For chezmoi mechanics (source vs destination vs target state, `.chezmoiignore` syntax, `chezmoi forget`/`remove`, run-script timing), see the `manage-dotfiles` skill. This skill assumes those and focuses on the Claude-specific decisions.

---

## 2. What to track

Portable across machines. Add these to chezmoi:

| Path | Why |
|---|---|
| `~/.claude/CLAUDE.md` | Global instructions you want on every machine |
| `~/.claude/settings.json` | Permissions, env, hooks, user preferences |
| `~/.claude/keybindings.json` | Keyboard shortcuts |
| `~/.claude/agents/` | User-authored agent definitions |
| `~/.claude/commands/` | User-authored slash commands |
| `~/.claude/skills/` | User-authored skills |
| `~/.claude/hooks/` | Standalone hook scripts, if you keep them there; hooks declared inline in `settings.json` already travel with that file |
| `~/.claude/statuslines/` | User-authored status-line scripts |

Only add directories that actually contain your own authored content. A fresh install has most of these empty.

---

## 3. What to ignore

### Runtime state (rewritten every session)

| Path | Why |
|---|---|
| `history.jsonl` | Slash-command history, often hundreds of KB |
| `projects/` | Per-cwd conversation state (0700) |
| `sessions/` | Session payloads (0700) |
| `session-env/` | Per-session environment snapshots; grows unboundedly, easily into the hundreds |
| `todos/` | Per-session task state (0700) |
| `tasks/` | Per-session task state |
| `telemetry/` | Usage telemetry |
| `file-history/` | Session file-edit history (0700) |
| `shell-snapshots/` | Shell environment captures |
| `plans/` | Runtime plan artifacts (see gotcha in §6) |
| `debug/` | Diagnostic dumps (0700) |

### Caches (regeneratable)

| Path | Why |
|---|---|
| `cache/` | Generic cache |
| `paste-cache/` | Recent-paste history |
| `downloads/` | Fetched artifacts |
| `statsig/` | Feature-flag cache |
| `stats-cache.json` | Usage-stats cache |
| `backups/` | Auto-backups of config (regenerated) |

### Per-machine / transient

| Path | Why |
|---|---|
| `ide/` | IDE-integration state, tied to installed IDEs |
| `plugins/` | Marketplace cache + install state (see gotcha in §6) |
| `settings.json.bak`, `settings.json.orig`, `*.log` | Editor/tool backup and log patterns |
| `.DS_Store` | macOS Finder metadata |
| `settings.local.json`, `CLAUDE.local.md` | Claude Code's `.local` convention for per-machine overrides (see gotcha in §6) |

### Secrets (never sync)

| Path | Why |
|---|---|
| `.credentials.json` | OAuth tokens on Linux/Windows/WSL. On macOS the file does not exist because credentials live in Keychain |
| `mcp-needs-auth-cache.json` | MCP auth state |
| `~/.claude.json` (at `$HOME` root) | OAuth sessions, MCP config, and caches (tens to hundreds of KB of auto-managed state) |

---

## 4. Ready-made `.chezmoiignore` snippet

Add to `.chezmoiignore` at your chezmoi source root. Patterns match **target paths** (as they appear under `$HOME`), not source filenames. See `manage-dotfiles` §6 for why.

```
# ~/.claude/ runtime state
.claude/history.jsonl
.claude/projects
.claude/sessions
.claude/session-env
.claude/todos
.claude/tasks
.claude/telemetry
.claude/file-history
.claude/shell-snapshots
.claude/plans
.claude/debug

# caches
.claude/cache
.claude/paste-cache
.claude/downloads
.claude/statsig
.claude/stats-cache.json
.claude/backups

# per-machine / transient
.claude/ide
.claude/plugins
.claude/settings.json.bak
.claude/settings.json.orig
.claude/*.log
.claude/.DS_Store

# secrets
.claude/.credentials.json
.claude/mcp-needs-auth-cache.json

# per-machine Claude Code state at $HOME root
.claude.json

# Claude Code's .local convention (per-machine overrides)
.claude/settings.local.json
.claude/CLAUDE.local.md
```

---

## 5. Adopting this pattern

### Starting from scratch

1. Make sure `.chezmoiignore` contains the block from §4 **before** adding anything.
2. Add portable files explicitly, one path at a time — never `chezmoi add ~/.claude/` (instance of the `--exact --recursive` parent foot-gun in `manage-dotfiles` §2):
   ```bash
   chezmoi add ~/.claude/CLAUDE.md
   chezmoi add ~/.claude/settings.json
   chezmoi add ~/.claude/keybindings.json
   chezmoi add ~/.claude/agents     # only if you have user-authored content
   chezmoi add ~/.claude/commands   # same
   chezmoi add ~/.claude/skills     # same
   chezmoi add ~/.claude/hooks      # same
   chezmoi add ~/.claude/statuslines # same
   ```
3. Verify: `chezmoi managed | grep claude` lists only the paths you want.

### If runtime paths are already tracked

`.chezmoiignore` filters source-tree traversal at apply time. It does not retroactively untrack. Run `chezmoi forget <path>` for each bad entry (keeps the file on disk, removes the source), *then* add the block from §4. See `manage-dotfiles` §10 for `forget` vs `remove`.

### Editing managed files

Once tracked, edit via `chezmoi edit ~/.claude/settings.json`, not the target directly. Direct edits to the target are lost on the next `chezmoi apply`. See `manage-dotfiles` §2.

---

## 6. Gotchas

### `~/.claude.json` ≠ `~/.claude/settings.json`

Two different files. `~/.claude.json` is auto-managed state (ignore the whole file). `~/.claude/settings.json` is portable user config (track). Users conflate them constantly.

### macOS stores credentials in Keychain

The `.credentials.json` ignore line is a no-op on macOS. The file doesn't exist there. Keeping the line cross-platform costs nothing and protects Linux/Windows/WSL users. Do not try to manage credentials through chezmoi regardless of platform; secrets handling is out of scope for this plugin.

### `plugins/` is runtime state — ignore the whole directory

`~/.claude/plugins/` holds marketplace clones, install metadata, and per-plugin data dirs — all populated by Claude Code's plugin sync at startup. Paths embed `/Users/...` which breaks across machines, so tracking any of it produces noisy diffs. Always ignore the whole directory.

Plugin provisioning is driven by `enabledPlugins` and `extraKnownMarketplaces` fields in `settings.json` — syncing that file is sufficient to provision plugins on a fresh machine. For the tracking pattern (modify script, workflow, scope), read `references/plugin-management.md` in this skill's directory.

### `.local.json` and `.local.md` are a Claude Code convention

In projects, Claude Code auto-excludes `settings.local.json` and `CLAUDE.local.md` via its own `.gitignore`. chezmoi doesn't know that convention, so the block in §4 ignores them explicitly at the user level. This matters when someone puts per-machine overrides in `~/.claude/settings.local.json`.

### `plans/` might be yours

The block assumes `~/.claude/plans/` is runtime scratch. If a user treats it as authored content (saved plans, templates they want synced), drop the `.claude/plans` line and track the directory instead.

### Target-path pattern, not source-style

`.chezmoiignore` patterns match target paths. Writing `dot_claude/projects` instead of `.claude/projects` silently matches nothing. The ignore has no effect, and the runtime directory gets tracked anyway. Verify with `chezmoi managed | grep claude` after editing.
