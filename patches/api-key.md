# The API-key patch

`warden-worker` is a faithful Bitwarden server, but it ships **without the personal API-key
endpoints**. Those are what power:

- `bw login --apikey` (logging the `bw` CLI in without typing your master password interactively)
- the `client_credentials` OAuth grant
- the web vault's **Settings → Security → Keys → View API Key** button (it 500s without this)

This is exactly what blocks automations and AI agents from reading credentials out of the vault —
the whole reason a self-hosted vault is more useful than Apple Keychain. So we added it.

`api-key.patch` is a plain `git diff` you apply on top of a fresh clone:

```bash
git clone --depth 1 https://github.com/qaz741wsd856/warden-worker.git
cd warden-worker
git apply ../claude-bitwarden-cloudflare/patches/api-key.patch
cp ../claude-bitwarden-cloudflare/patches/0014_add_api_key.sql migrations/0014_add_api_key.sql
```

## What it changes (7 files, ~159 insertions)

| File | Change |
|---|---|
| `src/models/user.rs` | Adds `api_key: Option<String>` to the user model (`skip_serializing` so it never leaks in responses). |
| `sql/schema.sql` | Adds the `api_key TEXT` column to the `users` table. |
| `migrations/0014_add_api_key.sql` | `ALTER TABLE users ADD COLUMN api_key TEXT;` for existing databases. |
| `src/crypto.rs` | `generate_api_key()` — 20 random bytes, base32-encoded (Bitwarden's format). |
| `src/handlers/accounts.rs` | `post_api_key` / `rotate_api_key` handlers returning `{ApiKey, RevisionDate, Object:"apiKey"}`. |
| `src/handlers/identity.rs` | Adds the `client_secret` field + a `"client_credentials"` grant arm that validates `client_id = user.<uuid>` and constant-time-compares the API key. |
| `src/router.rs` | Routes the two new endpoints. |
| `src/entry.js` | Offloads the two API-key paths to the heavy Durable Object (PBKDF2 path), matching how login is handled. |

## How it works

When you click **View API Key** (or first use the CLI), `post_api_key` generates a key, stores it
on your user row, and returns it. The CLI then logs in with the `client_credentials` grant:
`client_id = "user.<your-uuid>"`, `client_secret = "<api key>"`. The identity handler looks up the
user, constant-time-compares the stored key, and issues a normal access token. No master password
is sent over the wire for that flow — the key *is* the credential. (Your vault data is still
end-to-end encrypted; the API key authenticates you to the server, it doesn't decrypt anything.)

## Security notes

- The key is stored server-side in your own D1 database and **never serialized back** except on the
  explicit "view/rotate" response.
- Comparison is constant-time (`ct_eq`) to avoid timing attacks.
- Rotating the key (the same button, again) invalidates the old one immediately.
- Treat an API key like a password: anyone holding it can authenticate as you to the server. Store
  it in the vault itself or in `~/.hermes/.env` (mode 600), never in a committed file.
