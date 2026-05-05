# Plugin Management via settings.json

## Mechanism

Claude Code's plugin sync (runs at startup, suppressed by `--bare`) reads two `~/.claude/settings.json` fields and reconciles them with on-disk state:

- **`enabledPlugins`** — map of `"plugin@marketplace": boolean`. Plugin sync auto-clones the marketplace and auto-installs entries set to `true`. `false` is recorded as explicitly disabled. Plugins not listed are unenabled.
- **`extraKnownMarketplaces`** — map of `"name": {source: {source, repo}}`. Registers GitHub repos as plugin sources. `claude-plugins-official` is bundled and not listed here.

Syncing `~/.claude/settings.json` across machines is sufficient to provision plugins — no separate install script needed.

## Tracking pattern

Use a `modify_` script (not a plain copy) to manage only the plugin fields, since `settings.json` is a shared file that Claude Code also writes. The script bakes managed fields into the JSON via `jq`:

```bash
#!/bin/bash
defaults='{
  "enabledPlugins": { "myplugin@marketplace": true },
  "extraKnownMarketplaces": {
    "marketplace": {"source": {"source": "github", "repo": "owner/name"}}
  }
}'
jq -s '.[1] * .[0]' - <(echo "$defaults")
```

`jq`'s `*` operator deep-merges with right-side precedence — tracked entries seed missing keys; local entries (written by Claude Code or the user) always win on conflict. Untracked locals are never removed.

## Workflow

| Action | Steps |
|---|---|
| Add a plugin to defaults | Edit `enabledPlugins` in the modify script, set value to `true` (auto-install on fresh machine) or `false` (registered but disabled) |
| Register a new marketplace | Edit `extraKnownMarketplaces` in the modify script |
| Toggle a plugin per-machine | Use `/plugin` interactively; local value wins on next `chezmoi apply` |
| Remove from defaults | Delete the line from the modify script; existing local entries on each machine are preserved |

## Scope

Only user-scope plugins belong in `~/.claude/settings.json`. Project-scope plugins go in the repo's own `.claude/settings.json` (tracked in that repo's git, not in dotfiles). Local-scope plugins stay per-checkout.

## Hygiene

`~/.claude/plugins/` is Claude Code's runtime cache: marketplace clones and install metadata. It is fully recreated from `settings.json` at startup. Always ignore the whole directory — tracking any of it produces noisy diffs and paths embed `/Users/...` which breaks across machines. See §3 of the main skill for the `.chezmoiignore` entry.
