---
name: chezmoi-secrets
description: >-
  Use when storing tokens, passwords, SSH keys, API credentials, or any
  secret in a chezmoi-managed dotfiles tree: choosing between an external
  password-manager template function (1Password, Bitwarden, keyring, pass,
  KeePassXC, Vault, etc.), age-encrypted files in the repo, or plaintext
  machine-local config; using `chezmoi add --encrypt` / `--secrets`;
  configuring `encryption.age.identity` / `encryption.age.recipient`;
  setting up `chezmoi secret keyring`; or fixing a leaked plaintext
  credential. Also use when the user mentions `--encrypt`, `chezmoi
  secret`, age, 1Password, Bitwarden, keyring, pass, gopass, KeePassXC,
  Vault, or names a secret-handling backend alongside chezmoi.
---

# Secrets in chezmoi

## 1. Three-bucket model

| Bucket | Where the secret lives | When to use | Tradeoff |
|---|---|---|---|
| External password manager (template ref) | 1Password / Bitwarden / Vault / OS keyring; templates fetch at render time | A manager is already installed and signed in on every machine | Requires the manager CLI in `PATH`; render fails if the session expired |
| Encrypted file (age) | Encrypted blob committed to the repo | Repo-carried secret with no external manager — SSH keys, GPG keys, large multi-line secrets | Built-in age has limits (§3); recipient management is manual |
| Plaintext + `0600` | `[data]` block in `~/.config/chezmoi/chezmoi.toml` | Tiny per-machine token, **private repo only** | Easy to leak — last resort |

The three are not exclusive. A common shape is keyring for the GitHub
token, age for `~/.ssh/id_ed25519`, and zero plaintext.

---

## 2. Picking a backend

```
Do you already have a password manager installed and signed in?
  YES → Use its template function (§4)
  NO  → Repo-carried secret (e.g. SSH key, GPG key)?
    YES → age-encrypted file (§3)
    NO  → Tiny per-machine token (e.g. GitHub PAT)?
      YES → OS keyring via `chezmoi secret keyring` (§4)
      NO  → Plaintext + `0600` (§6) — only on a private repo
```

---

## 3. age limitations

The bundled age implementation does **not** support:

- Passphrases (routine ops like `chezmoi diff` would re-prompt every time)
- Symmetric encryption
- SSH keys as recipients (age's authors recommend against them)

For any of those, configure `encryption.command` to call the external
`age` binary instead of the bundled one.

Typical setup with the bundled age:

```toml
# ~/.config/chezmoi/chezmoi.toml
encryption = "age"
[age]
  identity = "~/.config/chezmoi/key.txt"
  recipient = "age1abc...xyz"
```

Generate the keypair once with `chezmoi age-keygen -o ~/.config/chezmoi/key.txt`,
copy the `# public key:` line that command prints into the `recipient`
field above (use `recipients` plural for multiple machines).

Add encrypted files with `chezmoi add --encrypt <path>`. `chezmoi edit`
on an encrypted source decrypts into a private temp directory and
re-encrypts on save. Don't decrypt manually.

---

## 4. Password-manager template functions

chezmoi exposes one or more template functions per supported backend.
The naming convention is roughly `<vendor>` for the basic fetch, with
`<vendor>Fields`, `<vendor>Raw`, or `<vendor>Attribute` variants where
applicable. Authoritative list at
https://www.chezmoi.io/user-guide/password-managers/. Only a subset is
shown below.

Supported backends include 1Password, Bitwarden (incl. `rbw`), LastPass,
pass, gopass, KeePassXC, Vault, AWS Secrets Manager, Azure Key Vault,
Dashlane, Doppler, ejson, Keeper, Proton Pass, Passhole, and the OS
keyring (Keychain on macOS, Secret Service / GNOME Keyring on Linux,
Credential Manager on Windows).

### OS keyring (one-time setup, cross-platform)

```bash
chezmoi secret keyring set --service=github --user=octocat
```

Then in any template:

```
[github]
  user = "octocat"
  token = {{ keyring "github" "octocat" | quote }}
```

### 1Password

```
{{- $token := onepasswordRead "op://Personal/GitHub/token" -}}
```

### Generic backend (any CLI that prints to stdout)

```
{{- $token := secret "vault" "kv" "get" "-field=token" "secret/github" -}}
{{- $cfg   := secretJSON "op" "item" "get" "GitHub" "--format" "json" -}}
```

`secret` returns stdout as a string; `secretJSON` parses stdout as JSON
and returns a value.

---

## 5. 1Password on shared machines

Interactive `op` sessions pass the session token to the 1Password CLI as
a **command-line argument**, which is visible to other users on the same
host through `ps`. On any host you don't fully own, switch to a
non-interactive auth path:

- **1Password Connect** — set `OP_CONNECT_HOST` and `OP_CONNECT_TOKEN`
- **Service accounts** — set `OP_SERVICE_ACCOUNT_TOKEN`

Both inject credentials via env vars instead of process args.

---

## 6. Plaintext fallback

If you store tokens directly in `~/.config/chezmoi/chezmoi.toml`, chmod
the file to `0600`; chezmoi's docs say so explicitly. The file is not
in the source repo so it doesn't sync, but it is still readable by every
process running as your user, and accidentally `cat`-ing it on a screen
share will expose the token.

```bash
chmod 0600 ~/.config/chezmoi/chezmoi.toml
```

Better: `chezmoi secret keyring set`. Same locality, but the value lives
in the OS keychain instead of a flat file.

---

## 7. `chezmoi add` flags for secrets

| Flag | Effect |
|---|---|
| `--encrypt` | Encrypt the file with the configured backend before storing it as source. Required for any committed secret. |
| `--secrets <action>` | Action when potential secrets are detected in added content. Values: `ignore` / `warning` (default) / `error`. Set to `error` in CI to fail loudly. |
| `--template-symlinks` | When adding a symlink whose target points into the source or home dir, render the target as a template using `.chezmoi.sourceDir` / `.chezmoi.homeDir` (otherwise the literal absolute path is captured). |

For the full `chezmoi add` flag matrix and the `--exact --recursive`
parent-dir footgun, see the `using-chezmoi` skill, §2 ("`chezmoi add`
flags and gotchas").

---

## 8. Common mistakes

### Public repo + `git.autoPush` + plaintext secret = leaked secret on push

A `[data]` block with a real token is fine on a private repo. The moment
the repo is public **and** `git.autoPush = true` is configured, any
mutation of source state pushes the token. See `using-chezmoi` §9 for
sync semantics. If you're publishing to GitHub, prefer keyring or a
password-manager ref over plaintext, and set
`secrets = "error"` in `chezmoi.toml` so `chezmoi add` refuses to embed
detected secrets.

### Forgetting `--encrypt` on SSH private keys

`chezmoi add ~/.ssh/id_ed25519` stores the key in plaintext under the
source dir. Always pass `--encrypt`. The destination file inherits
`0600` automatically because chezmoi maps `~/.ssh` to `private_dot_ssh/`.

### Manually decrypting age files to edit them

Use `chezmoi edit ~/.ssh/id_ed25519` instead. The plaintext lives in a
private temp directory while the editor is open, and chezmoi re-encrypts
on close. Manual decrypt-edit-re-encrypt cycles leak via editor swap
files, shell history, and clipboard managers.

### Passing `op` session tokens via `--token` on shared infra

See §5. Use 1Password Connect or service accounts on any host you share.
