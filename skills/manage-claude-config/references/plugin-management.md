# Bootstrapping Claude Code plugins via chezmoi

## The wrong mental model (and why it fails)

The intuitive approach for personal user-scope dotfiles is to seed `enabledPlugins` and `extraKnownMarketplaces` in `~/.claude/settings.json` from chezmoi (often via a `modify_dot_claude_settings.json` script that deep-merges defaults with `jq`), expecting Claude Code to clone the marketplaces and install the listed plugins on next launch.

At user scope, this does not work. The CLI writes those keys as side effects of `/plugin install`, but on launch Claude Code does not read them as install directives — pre-seeded entries sit in `settings.json` while `~/.claude/plugins/` stays empty. Long-lived machines accumulate the keys naturally, so the synced file looks "right" until it lands on a fresh box and provisions nothing.

**Two adjacent paths where these keys ARE input** — out of scope for this reference but worth knowing exists:

- **Project scope.** When `extraKnownMarketplaces` and `enabledPlugins` appear in a repo's `.claude/settings.json` and a teammate trusts the folder, Claude Code prompts to install — the documented team-distribution mechanism.
- **Managed settings (`forcedPlugins`).** The platform-supported non-interactive bootstrap for CI/CD and managed environments. Different field name, different settings location. Right answer for fleet-managed machines.

This reference covers the third case — personal user-scope dotfiles synced via chezmoi.

**Verify the user-scope claim yourself, with no risk to your real `~/.claude/`:**

```bash
tmp=$(mktemp -d)
mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/settings.json" <<'EOF'
{
  "extraKnownMarketplaces": {"some-marketplace": {"source": {"source": "github", "repo": "owner/name"}}},
  "enabledPlugins": {"some-plugin@some-marketplace": true}
}
EOF
HOME="$tmp" claude plugin list --json   # any non-interactive command that loads settings
ls "$tmp/.claude/plugins" 2>/dev/null   # empty or nonexistent — no install triggered
rm -rf "$tmp"
```

## The correct mechanism

The `claude` binary exposes documented non-interactive subcommands. Verified surface (from `claude plugin --help`):

| Command | Purpose | Notable flags |
|---|---|---|
| `claude plugin marketplace add <source>` | Register a marketplace from URL, path, or `owner/repo` | `--scope user\|project\|local` (default `user`), `--sparse <paths...>` for monorepos |
| `claude plugin marketplace list --json` | Snapshot registered marketplaces | `--json` required for stable parsing |
| `claude plugin marketplace remove <name>` | Unregister | `--scope` |
| `claude plugin install <plugin>` | Install `name@marketplace` | `--scope` (default `user`) |
| `claude plugin uninstall <plugin>` | Remove | `--scope` |
| `claude plugin enable <plugin>` | Re-enable a disabled plugin | `--scope` |
| `claude plugin disable [plugin]` | Mark as installed-but-off | `--scope` (default **`auto-detect`**, not `user`) |
| `claude plugin list --json` | Snapshot installed plugins | `--json` for parsing, `--available` for marketplace listings |
| `claude plugin update <plugin>` | Pull latest version | restart required |

The mutating subcommands above (`install`, `uninstall`, `enable`, `disable`, `marketplace add`, `marketplace remove`) write to `~/.claude/settings.json` for you. The applier never touches that file directly.

Two scope subtleties matter for unattended bootstrap:

- `install` and `marketplace add` default to `--scope user`, but stating it explicitly protects against future default changes during long-lived dotfiles.
- `disable` defaults to `--scope auto-detect`, which can pick the wrong scope when an id exists in multiple scopes. **Always pass `--scope user` to `disable`** in a bootstrap script — it is necessary, not just defensive.

The shape of `claude plugin list --json`:

```json
[
  {
    "id": "claude-md-management@claude-plugins-official",
    "version": "1.0.0",
    "scope": "user",
    "enabled": true,
    "installPath": "/Users/.../plugins/cache/.../1.0.0",
    "installedAt": "2026-03-05T09:19:19.615Z",
    "lastUpdated": "2026-03-05T09:19:19.615Z"
  }
]
```

`id` is the canonical `name@marketplace` identifier — match on this, not on `name` alone, since the same plugin name can exist in multiple marketplaces.

## Bootstrap pattern: manifest + applier

Two files in the chezmoi source root.

### Manifest (data only)

Minimal three-section schema. List **every** marketplace your plugins depend on under `marketplaces`, including `anthropics/claude-plugins-official`. Despite the name, it is a regular GitHub-hosted marketplace — not a bundled default — and is not auto-registered on a fresh CLI. Long-lived machines may have it registered from some past code path, which masks the issue locally; CI and freshly bootstrapped machines fail without an explicit entry. `marketplace add` is idempotent, so listing it has no cost on machines where it is already present — only upside on fresh ones.

For each `marketplaces` entry:
- `source` is the value passed to `claude plugin marketplace add` — a GitHub `owner/repo`, a git URL, or a local path.
- `name` must match the `name` field declared in that repo's `.claude-plugin/marketplace.json`. Claude Code reads it from the cloned manifest, **not** from the source URL — so guessing from the repo name (e.g., assuming `openai/codex-plugin-cc` becomes `codex-plugin-cc`) will produce a name mismatch. Look it up before adding the entry. The applier's idempotency check uses `name`, so a wrong value causes `marketplace add` to be re-attempted on every run, which `set -e` may turn into a hard abort.

For each plugin entry under `enabled` / `disabled`:
- `name` is the plugin id from its hosting marketplace's `marketplace.json`.
- `marketplace` must match a `name` from the `marketplaces` list above. Plugins from `anthropics/claude-plugins-official` are not exempt — register that marketplace like any other.

```yaml
# home/.chezmoidata/claude_plugins.yaml
claude_plugins:
  marketplaces:
    - name: claude-plugins-official     # not bundled — must be listed explicitly
      source: anthropics/claude-plugins-official
    - name: openai-codex                # value of "name" in the upstream marketplace.json
      source: openai/codex-plugin-cc
    - name: my-monorepo
      source: acme/devtools
      sparse: [.claude-plugin, plugins] # optional, for monorepo checkouts

  enabled:
    - { name: claude-md-management, marketplace: claude-plugins-official }
    - { name: codex,                marketplace: openai-codex }

  disabled:
    - { name: clangd-lsp, marketplace: claude-plugins-official }
```

### Applier (behavior only)

Idempotent. Diffs the manifest against live state and only acts on the delta. `run_once_after_*` ordering ensures the `claude` CLI is already installed by the time this fires.

```bash
#!/usr/bin/env bash
# home/run_once_after_install_claude_plugins.sh.tmpl
set -euo pipefail

command -v claude >/dev/null 2>&1 || { echo "claude CLI not found on PATH" >&2; exit 1; }
command -v jq     >/dev/null 2>&1 || { echo "jq not found on PATH"     >&2; exit 1; }

# Snapshot live state. `pipefail` is what makes a `claude plugin list` failure
# abort — silencing or removing it lets an empty result fool the diff into
# "install everything". Both `--json` calls return `[]` on empty state.
existing_marketplaces="$(claude plugin marketplace list --json | jq -r '.[].name')"
existing_plugins="$(claude plugin list --json | jq -r 'map(select(.scope == "user")) | .[].id')"

# Marketplaces first — plugins reference them by name.
{{- range .claude_plugins.marketplaces }}
if ! grep -Fxq -- {{ .name | quote }} <<<"$existing_marketplaces"; then
  {{- if .sparse }}
  claude plugin marketplace add {{ .source | quote }} --scope user --sparse {{ range $i, $p := .sparse }}{{ if $i }} {{ end }}{{ $p | quote }}{{ end }}
  {{- else }}
  claude plugin marketplace add {{ .source | quote }} --scope user
  {{- end }}
fi
{{- end }}

# Enabled plugins: install if absent. Already-installed entries are NOT
# re-enabled — that respects per-machine `/plugin disable` toggles.
{{- range .claude_plugins.enabled }}
plugin_id="{{ .name }}@{{ .marketplace }}"
if ! grep -Fxq -- "$plugin_id" <<<"$existing_plugins"; then
  claude plugin install "$plugin_id" --scope user
fi
{{- end }}

# Disabled plugins: install + disable on first apply only. Mirrors the
# enabled block — already-installed entries are not re-disabled, respecting
# per-machine `/plugin enable` toggles.
{{- range .claude_plugins.disabled }}
plugin_id="{{ .name }}@{{ .marketplace }}"
if ! grep -Fxq -- "$plugin_id" <<<"$existing_plugins"; then
  claude plugin install "$plugin_id" --scope user
  if ! claude plugin disable "$plugin_id" --scope user; then
    if ! claude plugin uninstall "$plugin_id" --scope user; then
      echo "ERROR: disable AND uninstall both failed for $plugin_id; plugin is now installed AND enabled" >&2
    fi
    exit 1
  fi
fi
{{- end }}
```

The `enabled` and `disabled` blocks treat existing installs identically: skip. The semantic difference is only what happens on the **install** path. To flip an already-installed-and-enabled plugin to disabled (or vice versa), do it manually with `claude plugin disable <id> --scope user` (or `enable`); editing the manifest alone has no effect on already-present entries.

### `.chezmoiignore` gating

The script is part of the standard `useClaude` opt-out, not a runtime gate inside the template. Add to the existing block:

```
{{ if not .useClaude }}
.claude
install_claude_plugins.sh
{{ end }}
```

`.chezmoiignore` matches target paths after attribute stripping (see `manage-dotfiles` §6 for the rule). For this script, that's `dot_claude/` → `.claude` and `run_once_after_install_claude_plugins.sh.tmpl` → `install_claude_plugins.sh`. Source-style names here are a silent no-op.

Putting the gate in the template body instead would leave a rendered, empty script that churns whenever the manifest changes. `.chezmoiignore` is the right layer.

### settings.json hygiene

If a `modify_dot_claude_settings.json` previously seeded `enabledPlugins` or `extraKnownMarketplaces`, **strip both blocks**. The CLI owns those keys now; leaving the modify-script entries in place creates a second source of truth that re-adds them after every `/plugin disable`.

## Workflow

| Action | Steps |
|---|---|
| Add a plugin to defaults | Edit the `enabled` (or `disabled`) list in the manifest; next `chezmoi apply` installs it |
| Register a new marketplace | Add to `marketplaces`; next apply registers it |
| Toggle a plugin per-machine | Use `/plugin enable\|disable` interactively; the applier respects already-installed state and will not override |
| Remove from defaults | Delete the manifest entry. Existing installs stay — the applier only adds, never removes |
| Force a clean uninstall | `claude plugin uninstall <id> --scope user` by hand, then remove the manifest entry |

## Scope

Only user-scope plugins belong in this bootstrap. Project-scope plugins live in the repo's own `.claude/settings.json` (tracked in that repo's git, not in dotfiles). Local-scope plugins are per-checkout and per-developer.

## Gotcha checklist

Hard-won lessons from a working implementation. Skip any of these and the script silently misbehaves on edge cases.

1. **Use `--json`, not awk on human output.** `claude plugin list` and `claude plugin marketplace list` have stable JSON output. The human-readable form has no stability contract.
2. **Filter plugin list results by scope** (`jq 'map(select(.scope == "user"))'`) before extracting `id`s — without it, a project- or local-scope plugin with the same id masks the user-scope check. Marketplaces don't need (and can't take) the same filter: `claude plugin marketplace list --json` does not expose a `scope` field, since marketplaces are name-global in the listing.
3. **Match on `id` (`name@marketplace`), not `name`.** Same plugin name can exist in multiple marketplaces.
4. **Never silence list errors with `2>/dev/null`.** Auth failures, version mismatches, or missing CLI must abort the script. Silenced errors produce empty existing-state, which causes the applier to attempt a full install on every run.
5. **Two-phase install+disable for the disabled list.** If `disable` fails after `install` succeeds, the plugin is enabled forever (next run sees it installed and skips). Roll back with `uninstall` so the next run retries.
6. **Explicit `--scope user` on `disable`.** The default is `auto-detect`, not `user`.
7. **Check for `jq` and `claude` up front.** Both are implicit dependencies. Aborting loudly beats partial execution.
8. **Manifest `name` must match upstream.** The marketplace declaration determines the plugin name. Renaming locally has no effect — `install` will fail with "plugin not found".
9. **Marketplaces must be added before plugins that depend on them.** The applier orders them in that sequence; preserve it if rewriting.
10. **`run_once_after_*` runs strictly after all file deployment** — including default-phase scripts like `run_once_00_install_packages.sh.tmpl`, which interleave with deployment rather than waiting for it to finish. So `claude` is on PATH by the time this applier fires. Don't confuse the `after_` attribute (phase selection) with the `_00_` numeric prefix (within-phase alphabetical ordering) — they're separate mechanisms.
11. **Manifest moves between `enabled` and `disabled` lists are no-ops on already-installed plugins.** The applier's existence check looks at `id` only, not enabled-state — so flipping an entry between lists does nothing on a re-apply. To change state on an already-installed plugin, run `claude plugin enable|disable <id> --scope user` directly.

## Why `run_once_after_*`, not bare `run_once_*` or `run_onchange_*`

For the run-script prefix table, see `manage-dotfiles` §7. Picking among them for this use case:

- Bare `run_once_*` runs interleaved with file deployment (after each enclosing directory is created, not strictly after `~/.claude/` is fully populated). Wrong timing — the applier needs the deployed `~/.claude/` complete before it touches plugins.
- `run_onchange_*` re-fires when the script's content changes — same trigger as `run_once_*` for body-only edits. The embedded-hash technique (e.g., `# {{ include "manifest.yaml" | sha256sum }}`) is what extends `run_onchange_*` to track *external* file content. For this use case the manifest is templated into the body, so `run_once_*` and `run_onchange_*` would behave equivalently; pick the simpler one.
- `run_once_after_*` is the fit: the script body embeds manifest values via Go template, so editing the manifest changes the rendered body, which trips the `once` content-hash check and re-runs. The `after_` attribute pins it to the post-deployment phase. User toggles via `/plugin enable` don't change the rendered body, so they don't re-trigger the applier — exactly the behavior wanted.
