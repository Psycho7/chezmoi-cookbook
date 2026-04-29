---
description: Detect OS, print the chezmoi install one-liner, and interpret `chezmoi doctor` (read-only — never installs or modifies anything).
allowed-tools: Bash
---

Diagnose the user's chezmoi setup. Run a fixed sequence of read-only checks, then report findings.

**Out of scope — do NOT do any of these:** execute the install command, run `chezmoi init`, run `chezmoi apply`, or diagnose / install `age`, `gpg`, or any password-manager binaries (`bitwarden`, `1password`, `lastpass`, `keepassxc`, `pass`, `vault`, `keychain`, etc.). Secrets tooling is intentionally excluded from this command.

Perform the following steps in order:

1. **Detect host OS.** Run `uname -s`. Map: `Darwin` → macOS, `Linux` → Linux. If the command fails or returns anything else, treat the host as Windows. State the detected OS in the response.

2. **Print the install one-liner as plain text — do not execute it.** Pick the line that matches the detected OS:

   - macOS: `brew install chezmoi`
   - Windows: `winget install twpayne.chezmoi`
   - Linux: `sh -c "$(curl -fsLS get.chezmoi.io)"`

   Make clear in the response that this is informational only; the user must run it themselves if they want to install chezmoi.

3. **Check whether chezmoi is installed.** Run `chezmoi --version`.

   - If the command fails (binary not found), report that chezmoi is not installed and skip step 4.
   - If it succeeds, report the version string.

4. **Interpret `chezmoi doctor`.** Run `chezmoi doctor` and capture the full output. Surface to the user **only** these items, ignoring everything else:

   - any line starting with `error:`
   - any indication that `git` is missing or unavailable
   - any indication that `pwsh` (PowerShell Core) is missing — only when the detected OS is Windows

   Ignore all other warnings and info lines, including every reference to `age`, `gpg`, or password managers.

5. **Summarize.** End with a short summary: detected OS, install hint, whether chezmoi is installed (and which version), and either the filtered findings or "no relevant issues."
