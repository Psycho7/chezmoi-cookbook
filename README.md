# chezmoi-cookbook

A Claude Code plugin for [chezmoi](https://www.chezmoi.io/). Teaches Claude how to manage dotfiles with chezmoi.

## Install

```
/plugin marketplace add Psycho7/chezmoi-cookbook
/plugin install chezmoi-cookbook@chezmoi-cookbook
```

## Skills

Both activate on their own when you're in a chezmoi repo or touching `~/.claude/`. To invoke by hand:

- `/chezmoi-cookbook:manage-dotfiles`. Chezmoi mechanics: source/destination/target states, the file-type decision tree (plain / `.tmpl` / `modify_`), `chezmoi add` flags, modify-script patterns, `.chezmoiignore` gotchas, cross-machine sync, Windows and CI pitfalls.
- `/chezmoi-cookbook:manage-claude-config`. Which parts of `~/.claude/` and `~/.claude.json` are portable, which are per-machine, which are secrets, plus a ready-made `.chezmoiignore` block.

## Commands

### `/chezmoi-cookbook:bootstrap`

Read-only diagnostic. Detects the host OS and prints the matching install one-liner (it does not run it). If chezmoi is already installed, runs `chezmoi doctor` and surfaces only `pwsh` (Windows), `git`, and `error:` lines. Secrets tooling (`age`, `gpg`, password managers) is filtered out on purpose. No arguments.

## Hooks

macOS and Linux only (bash + `jq`). Both fail open, so if `chezmoi` isn't on `PATH` the edit just goes through.

**`block-managed-edits`** runs as a PreToolUse hook on Edit and Write. If the target shows up in `chezmoi managed`, the call is denied and Claude is told to use `chezmoi edit` instead. Direct edits to managed files get silently overwritten on the next `chezmoi apply`, which is a frustrating bug to hit.

**`validate-source-changes`** runs as a PostToolUse hook on Edit and Write. If the changed file is a `.tmpl` under `chezmoi source-path`, it runs `chezmoi execute-template` and surfaces any render error so Claude sees it on the next turn. One caveat: `.chezmoitemplates/` includes don't resolve via stdin, so templates that pull in shared partials will false-positive. Set `CHEZMOI_COOKBOOK_NO_VALIDATE=1` for those.

Disable per-shell with `CHEZMOI_COOKBOOK_NO_GUARD=1` or `CHEZMOI_COOKBOOK_NO_VALIDATE=1`. Disable the whole plugin via `/plugins`.

## License

MIT
