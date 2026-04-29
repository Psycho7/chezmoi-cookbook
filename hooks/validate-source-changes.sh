#!/usr/bin/env bash
# PostToolUse(Edit|Write) validator: render-test changed chezmoi templates.
# Surfaces `chezmoi execute-template` errors back to Claude as
# additionalContext so broken templates don't get applied.
#
# Limitation: `execute-template` reads from stdin, so `.chezmoitemplates/`
# includes and filename-attribute logic don't resolve. Standalone `.tmpl`
# files render correctly; templates that depend on includes will
# false-positive — opt out via CHEZMOI_COOKBOOK_NO_VALIDATE=1.

set -euo pipefail

[ "${CHEZMOI_COOKBOOK_NO_VALIDATE:-0}" != "1" ] || exit 0

input="$(cat)"

# Cheap pre-filter before forking jq/chezmoi: if the raw payload doesn't
# even mention `.tmpl`, this can't be a template edit. Hot path — runs on
# every Edit/Write across the whole session.
[[ "$input" == *.tmpl* ]] || exit 0

# Fail-open when required tools are absent. Without these guards, `set -e`
# would crash with exit 1, which Claude Code surfaces as a non-blocking
# error rather than a clean silent pass.
command -v jq >/dev/null 2>&1 || exit 0
command -v chezmoi >/dev/null 2>&1 || exit 0

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -n "$file_path" ] || exit 0
[[ "$file_path" == *.tmpl ]] || exit 0

source_dir="$(chezmoi source-path 2>/dev/null)" || exit 0
[ -n "$source_dir" ] || exit 0
[[ "$file_path" == "$source_dir"/* ]] || exit 0

if render_err="$(chezmoi execute-template < "$file_path" 2>&1 >/dev/null)"; then
  exit 0
fi

reason="\`${file_path}\` failed to render via \`chezmoi execute-template\`. Fix the template before \`chezmoi apply\`.

\`\`\`
${render_err}
\`\`\`"

jq -n --arg ctx "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
