# Security model

This is a real zero-knowledge vault — but "self-hosted" moves some responsibility to you. Here's
the honest threat model and the defaults this playbook sets.

## What protects your data

| Layer | What it does |
|---|---|
| **Zero-knowledge encryption** | Your master password derives the key (PBKDF2/Argon2) **on the client**. The Worker and D1 only ever see ciphertext. Cloudflare cannot read your vault. Neither can anyone who steals the D1 database. |
| **`ALLOWED_EMAILS` email-lock** | The register endpoint is public (Bitwarden clients require it), but only addresses on this list are accepted — everyone else gets `401`. This is what stops the world from making accounts on your instance. |
| **Rate limiting** | 5 requests/min on login + register, to blunt brute-force and credential-stuffing. |
| **Random JWT secrets** | `JWT_SECRET` / `JWT_REFRESH_SECRET` are random 48-byte values set as Worker secrets — never committed, never in `wrangler.toml`. |
| **TLS + proxied DNS** | Cloudflare terminates TLS; the origin is a Worker, so there's no server/VM to patch or expose. |

## What you are responsible for

1. **Your master password.** It's the only thing that decrypts the vault and **there is no reset**.
   Use a long passphrase. Losing it = losing the vault. (Write it down somewhere physical if needed.)
2. **TOTP 2FA on the vault.** Turn it on right after you register: Settings → Security →
   Two-step Login → Authenticator app.
3. **2FA on your Cloudflare account.** Your CF login can redeploy the Worker and read D1. It is part
   of the security boundary — protect it at least as well as the vault itself.
4. **Full-disk encryption on every device** that runs the `bw` CLI or stores a `BW_SESSION`. On a
   Mac: `sudo fdesetup enable` (FileVault). Store the recovery key in the vault.
5. **Keep secrets out of git.** Never commit `wrangler.toml` with real ids if you'd rather keep them
   private (they're not secrets, but the JWT values and API keys are). Never commit `~/.hermes/.env`.

## CLI session files

If you use the `bw` CLI with a persistent session (e.g. for automations), the session token grants
**read access to the whole unlocked vault**. Treat the file holding it like a root credential:

- Store `BW_SESSION` only in a `chmod 600`, owner-only file (e.g. `~/.hermes/.env`).
- Never print the value to logs or chat — reference it by name.
- Re-lock (`bw lock`) or let it expire when you're done with a batch of automation.
- An API key (`bw login --apikey`) authenticates you to the **server** but does **not** decrypt the
  vault — you still need the master password to unlock. Rotate it from the web vault if exposed.

## What this setup does NOT give you

- **No Organizations / shared Collections / SSO** — warden-worker is a personal-vault engine. Don't
  use it as a team-secret-sharing replacement for 1Password Business; shared team secrets need a
  real org tier.
- **No managed backups.** D1 is durable, but you own disaster recovery. Periodically export an
  encrypted vault backup (`bw export --format encrypted_json`) and store it somewhere safe.
- **No SOC 2 / compliance attestation.** It's your infrastructure. Fine for personal and small-org
  use; not a drop-in for a regulated enterprise that needs a vendor's compliance paperwork.

## Reporting issues

This repo is a thin orchestration + a patch. Server bugs belong upstream at
[`warden-worker`](https://github.com/qaz741wsd856/warden-worker). For issues with the patch or the
installer, open an issue here. **Do not** include real secrets, tokens, or vault contents in a
report.
