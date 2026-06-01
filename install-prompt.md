# The Claude Code install prompt

Open [Claude Code](https://claude.com/claude-code) in any directory and paste the block below.
Replace **`you@example.com`** with the one email allowed to register, and **`example.com`** with a
domain already on your Cloudflare account. That's the whole input.

> Prereqs Claude will check for you: a Cloudflare account, a domain on Cloudflare, and
> `wrangler` authenticated (`wrangler login`). It needs `git`, `node 22+`, `jq`, `curl`, and will
> install the Rust toolchain itself.

---

```
Set up a self-hosted Bitwarden vault on my Cloudflare account using
github.com/barkleesanders/claude-bitwarden-cloudflare.

My email (the ONLY address allowed to register): you@example.com
My domain (already on Cloudflare):                example.com
So the vault should live at:                      vault.example.com

Do this end to end and do NOT make it publicly registerable to anyone but me:

1. git clone github.com/barkleesanders/claude-bitwarden-cloudflare into ~/projects, then run its
   install.sh FIRST in dry-run so I can see the plan:
       bash install.sh --dry-run --email you@example.com --domain example.com
2. If the plan looks right, run it for real WITHOUT --dry-run. When wrangler prints the new D1
   database_id and KV namespace id, write them into warden-worker/wrangler.toml (the script does
   the clone+patch+build+deploy; you wire the two IDs the way the README's manual steps describe).
3. Set the secrets as the script does: ALLOWED_EMAILS = my email only, plus random JWT_SECRET and
   JWT_REFRESH_SECRET (openssl rand -base64 48). Never print secret values to chat.
4. Attach vault.example.com (proxied A record + Worker route). If CLOUDFLARE_API_TOKEN is set, the
   script does it; otherwise do it via the cloudflare-api MCP or tell me the two dashboard clicks.
5. VERIFY before declaring done: curl the register endpoint with attacker@evil.com and confirm it
   returns HTTP 401 (email-lock working). Then give me the URL to create my account.
6. After I register in the browser, walk me through enabling TOTP 2FA in Settings → Security.

Security rules: zero-knowledge (only my master password decrypts the vault), do not commit any
secret, keep ~/.hermes/.env at mode 600 if you store a CLI session there, and confirm the
non-allowed-email rejection with a live curl before you say it's done.
```

---

## What you get

- A real Bitwarden server at `https://vault.example.com` that works with every official Bitwarden
  client (browser extensions, mobile, desktop, `bw` CLI).
- The **API-key patch** applied, so `bw login --apikey` and the web vault's *View API key* button work.
- An email-locked, rate-limited, zero-knowledge vault running on Cloudflare's free tier.

## If you'd rather not use Claude

Everything the prompt does is in [`docs/INSTALL.md`](docs/INSTALL.md) as plain copy-paste commands,
and the installer itself (`install.sh`) is readable top to bottom.
