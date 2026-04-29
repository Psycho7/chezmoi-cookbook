#!/usr/bin/env bash
# PreToolUse(Edit|Write) guard: deny edits to chezmoi-managed targets.
# Steers the user to `chezmoi edit` so writes survive `chezmoi apply`.

set -euo pipefail

# Per-hook opt-out. Claude Code has no built-in way to disable a single
# plugin hook, so the script provides one.
[ "${CHEZMOI_COOKBOOK_NO_GUARD:-0}" != "1" ] || exit 0

# Fail-open when required tools are absent. Without these guards, `set -e`
# would crash with exit 1, which Claude Code surfaces as a non-blocking error
# rather than a clean allow/deny.
command -v jq >/dev/null 2>&1 || exit 0
command -v chezmoi >/dev/null 2>&1 || exit 0

input="$(cat)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

# Defensive: nothing to check.
[ -n "$file_path" ] || exit 0

managed="$(chezmoi managed --path-style=absolute --include=files 2>/dev/null)" || exit 0

printf '%s\n' "$managed" | grep -Fxq -- "$file_path" || exit 0

reason="\`${file_path}\` is managed by chezmoi. Edit the source via \`chezmoi edit ${file_path}\`, or the source file directly (found at \`chezmoi source-path ${file_path}\`). Editing the target will be lost on \`chezmoi apply\`."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  },
  systemMessage: $reason
}'
