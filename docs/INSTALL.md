# Manual install (no Claude)

This is exactly what [`install.sh`](../install.sh) and the Claude prompt do, as plain commands.
Run them in order. Replace `you@example.com` and `example.com` throughout.

> **Tip:** read the plan first with `bash install.sh --dry-run --email you@example.com --domain example.com`.
> It validates your prerequisites and prints every command without creating anything.

## 0. Prerequisites

```bash
node --version        # need 22+
git --version
jq --version
which wrangler        # npm i -g wrangler  if missing
wrangler login        # authenticate to YOUR Cloudflare account
wrangler whoami       # confirm the right account
```

You also need a **domain on that Cloudflare account** (so `vault.<domain>` can be proxied).

> **⚠️ Gotcha — pin `-c wrangler.toml` on every mutating command.** wrangler walks *up* the
> directory tree looking for a config. If you have a `wrangler.toml`/`wrangler.jsonc` anywhere in a
> parent directory (e.g. `$HOME`), a bare `wrangler deploy` / `secret put` / `secret list` can
> silently target the **wrong** worker and account. Always pass `-c wrangler.toml` (every command
> below does). Verify the resolved worker first with `wrangler deploy --dry-run -c wrangler.toml`.

## 1. Clone + apply the API-key patch

```bash
git clone --depth 1 https://github.com/qaz741wsd856/warden-worker.git ~/warden-worker
cd ~/warden-worker
git apply ~/projects/claude-bitwarden-cloudflare/patches/api-key.patch
cp ~/projects/claude-bitwarden-cloudflare/patches/0014_add_api_key.sql migrations/0014_add_api_key.sql
```

(Why the patch: warden-worker ships without personal API-key endpoints — see
[`../patches/api-key.md`](../patches/api-key.md).)

## 2. Create the D1 database + KV namespace

```bash
wrangler d1 create vault1 -c wrangler.toml
wrangler kv namespace create ATTACHMENTS_KV -c wrangler.toml
```

Each command prints an id. **Paste them into `wrangler.toml`** — the `database_id` under
`[[d1_databases]]` and the `id` under `[[kv_namespaces]]`. (wrangler v4 does not expand
`${...}` placeholders, so the ids must be literal.)

## 3. Download the web vault + build the worker

```bash
cd ~/warden-worker
BW=v2026.4.1
wget "https://github.com/dani-garcia/bw_web_builds/releases/download/$BW/bw_web_$BW.tar.gz"
tar -xzf "bw_web_$BW.tar.gz" -C public/ && rm "bw_web_$BW.tar.gz"
find public/web-vault -name '*.map' -delete   # trim source maps

# Rust toolchain (skip if you have rustup)
curl -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
cargo install --locked worker-build --version 0.8.3
worker-build --release --locked
```

## 4. Configure + set secrets

```bash
# BASE_URL must match your vault host
sed -i '' 's|# BASE_URL = .*|BASE_URL = "https://vault.example.com"|' wrangler.toml
# also set DISABLE_USER_REGISTRATION = "true" in wrangler.toml [vars] if you want
# registration fully closed AFTER you create your own account.

printf '%s' 'you@example.com'            | wrangler secret put ALLOWED_EMAILS      -c wrangler.toml
printf '%s' "$(openssl rand -base64 48)" | wrangler secret put JWT_SECRET          -c wrangler.toml
printf '%s' "$(openssl rand -base64 48)" | wrangler secret put JWT_REFRESH_SECRET  -c wrangler.toml
```

`ALLOWED_EMAILS` is the email-lock: the register endpoint stays public (Bitwarden clients call it),
but only addresses in this list are accepted. Everyone else gets `401`.

## 5. Apply the schema + deploy

```bash
wrangler d1 execute vault1 --file sql/schema.sql --remote --yes -c wrangler.toml
wrangler deploy --dry-run -c wrangler.toml   # confirm the resolved worker NAME is "warden-worker"
wrangler deploy -c wrangler.toml
```

## 6. Attach `vault.example.com`

In the Cloudflare dashboard for `example.com`:

1. **DNS** → add an `A` record: name `vault`, content `192.0.2.1`, **Proxied** (orange cloud).
   (The IP is a placeholder; the Worker route intercepts the request before it's ever used.)
2. **Workers & Pages → warden-worker → Settings → Domains & Routes** → add route `vault.example.com/*`.

Or via API with a `CLOUDFLARE_API_TOKEN` (Zone:DNS edit + Workers Routes edit) — see the
`install.sh` "Attaching" section for the two `curl` calls.

## 7. Verify the lock-down BEFORE you trust it

```bash
# A non-allowed email MUST be rejected:
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  'https://vault.example.com/identity/accounts/register' \
  -H 'Content-Type: application/json' \
  -d '{"email":"attacker@evil.com","masterPasswordHash":"x","userSymmetricKey":"x","userAsymmetricKeys":{"publicKey":"x","encryptedPrivateKey":"x"},"kdf":0,"kdfIterations":600000}'
# Expect: 401
```

## 8. Create your account + turn on 2FA

1. Open `https://vault.example.com`, click **Create account**, use `you@example.com`, set a strong
   master password (this is the only thing that decrypts your vault — there is no reset).
2. **Settings → Security → Two-step Login → Authenticator app** → scan the QR with any TOTP app.
3. Point the browser extension / mobile / desktop apps at the **Self-hosted** server URL
   `https://vault.example.com` and log in.

## 9. (Optional) CLI + API key

```bash
bw config server https://vault.example.com
bw login                          # interactive, or:
bw login --apikey                 # uses client_id=user.<uuid> + the API key from the web vault
export BW_SESSION="$(bw unlock --raw)"
bw get password 'github.com'
```

See [`docs/SECURITY.md`](SECURITY.md) for hardening (disk encryption, Cloudflare-account 2FA, what
to keep out of git).
