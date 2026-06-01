# 🔐 Vaultflare — self-hosted Bitwarden on Cloudflare Workers, set up by Claude Code

> **TL;DR — why this is useful:** It's a real Bitwarden vault — works with every official Bitwarden app (Chrome/Safari/Firefox/Edge, iOS, Android, desktop, `bw` CLI) — but it runs on **your** Cloudflare account for **$0/year** instead of paying $20–96/user/yr to Bitwarden or 1Password. You own the encrypted data (zero-knowledge; nobody but you can read it), it works everywhere (not just Safari like Apple Keychain), and it's the only one with **CLI/API access so automations and AI agents can read credentials**. And you don't have to fight Cloudflare's setup — **you paste one prompt into [Claude Code](https://claude.com/claude-code) and it builds, deploys, and locks the whole thing down for you.**

---

## What this literally is (no magic)

It is **not** a new password manager. It's three concrete things:

1. **[`warden-worker`](https://github.com/qaz741wsd856/warden-worker)** — a Bitwarden-compatible server written in Rust, compiled to WASM, running on Cloudflare Workers + D1.
2. **An API-key patch we wrote** — adds the personal API-key endpoints warden-worker is missing, so `bw login --apikey`, the `client_credentials` OAuth grant, and the web vault's *"View API key"* button actually work.
3. **A Claude Code install prompt** — clones, patches, builds, deploys, and security-hardens it end-to-end, including the Cloudflare parts (D1, KV, secrets, DNS, routes) most people get stuck on.

You connect with the **official, unmodified Bitwarden clients**. The encrypted data lives in *your* Cloudflare D1 database — only your master password decrypts it.

| In this repo | What it is |
|---|---|
| `install-prompt.md` | The prompt you paste into Claude Code |
| `patches/api-key.md` | The API-key feature we added to warden-worker |
| `docs/INSTALL.md` | Manual steps, if you'd rather not use Claude |
| `docs/SECURITY.md` | Email-lock, rate-limiting, 2FA, disk encryption, the CF-account boundary |

---

## 💵 What you save vs paying

Running cost: **$0/year** (Cloudflare free tier; you already own the domain). Here's what you'd pay to get the same capability elsewhere — **verified, 2026 prices**:

| If you paid for it instead | Cost / user / yr | You pay here |
|---|---|---|
| **Bitwarden cloud Premium** (TOTP, attachments, emergency access) | **$19.80** | **$0** |
| **Bitwarden Families** (6 users) | $47.88 | **$0** |
| 1Password Individual | $35.88 | **$0** |
| 1Password Business | $95.88 | **$0** |
| Apple Keychain | $0 — but no real cross-browser support and **no CLI/API access** | ✅ has both |

**The direct saving:** self-hosting **unlocks Bitwarden's Premium features for free**, so you stop paying the **$19.80/yr/user** Bitwarden Premium fee (or $35.88 for 1Password) — forever.

### At scale (nonprofits / orgs) — cost is per-deployment, not per-seat
| People | Bitwarden Teams ($48/user/yr) | 1Password Business ($96/user/yr) | This setup (total) | Saved / yr |
|---|---|---|---|---|
| 50 | $2,400 | $4,800 | ~$0 | **$2.4k–4.8k** |
| 250 | $12,000 | $24,000 | ~$0–$60 | **$12k–24k** |
| 1,000 | $48,000 | $96,000 | ~$60–$600 | **$47k–95k** |

**Organizations + sharing:** base warden-worker is personal-vault only, but an optional **working** clean-room patch ([`patches/organizations.md`](patches/organizations.md)) adds **Organizations, shared Collections, member invites, and cipher sharing** — ACL-enforced, Cloudflare-native invites (manual-confirm, no external email), builds clean. So this **can** be a team-sharing setup, not just a personal vault — now including Groups, org policies, event-log audit, and SCIM provisioning. (SSO is a config + OIDC scaffold, not yet a full login path — honest boundary in the patch doc.) Said up front on purpose.

---

## 💸 What would it actually take to make this cost money on Cloudflare?

For one person — or even a small team — **you will never pay a cent.** A personal vault uses **well under 1%** of the free limits. Here's exactly where the meters are and what it takes to trip them:

| Cloudflare free limit | What uses it | Roughly when you'd exceed it |
|---|---|---|
| **Workers: 100,000 requests/day** | every sync, unlock, autofill | ~**200–1,000 daily-active users** hammering it (a personal vault is a few hundred req/**day**) |
| **D1: 5 GB + 5M row-reads/day** | the encrypted vault store | millions of items, or a **very large** active user base (your 1,500-item vault is ~0.2 MB) |
| **KV: 1 GB + 1k writes/day** | **file attachments** | storing **lots of file attachments** — the single most likely thing to push you over |
| **Durable Objects: 100k req/day + 13k GB-s/day** | login (PBKDF2) + live websocket sync | heavy concurrent login/sync at scale |

**Bottom line:** the only realistic ways to ever owe Cloudflare money are (a) **hundreds-to-thousands of daily-active users**, or (b) **storing many file attachments**. And even then you don't go per-seat — you move to **Workers Paid: a flat $5/month** (includes 10M requests/mo + far higher limits) for the **entire deployment**. So worst case for a 1,000-person org is roughly **$5–50/mo total** vs **$4,000/mo** for 1Password Business. ([Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/))

---

## 🤖 Install it (the Claude Code way)

Prereqs: a Cloudflare account, a domain on Cloudflare, and `wrangler` authenticated (`wrangler login`). Open Claude Code and paste the prompt in [`install-prompt.md`](install-prompt.md). Claude will:

1. Clone `warden-worker` + apply the **API-key patch**
2. Create the D1 database + KV namespace; download the bundled web vault
3. Install the Rust toolchain + `wasm32` target; build the WASM worker
4. Set `ALLOWED_EMAILS` (only your email can register) + random `JWT_SECRET`/`JWT_REFRESH_SECRET` + `BASE_URL`
5. Apply the D1 schema, deploy, attach `vault.<your-domain>` (proxied DNS + Worker route)
6. **Verify the lock-down** (only your email accepts, rate-limit live) **before** it's reachable
7. Hand you the URL to register + turn on TOTP 2FA

Prefer manual? See [`docs/INSTALL.md`](docs/INSTALL.md).

---

## What works / what doesn't
**Works:** logins, folders, TOTP, attachments (KV/R2), Bitwarden Send, device management, live sync/push, equivalent-domain matching, HIBP breach checks, 2FA (authenticator app), and the added **API key / `bw login --apikey`**. All official Bitwarden clients.
**Works (optional patch):** Organizations, shared Collections, member invites + confirm, cipher sharing, **Groups, org policies, event-log audit, SCIM provisioning** — ACL-enforced, Cloudflare-native invites, optional outbound email ([details](patches/organizations.md)).
**SSO (OIDC):** full flow built + **tested end-to-end** (`tools/sso-e2e-test.mjs` drives the real worker: discovery + JWKS **RS256 id_token verify** → identity link → one-time SSO code → `authorization_code` grant (PKCE) issuing a real token). Caveat: tested against a controlled IdP, **not** yet the official web-vault SSO UI or a specific commercial IdP; and the E2E vault still needs your master password to decrypt (no Key Connector/TDE). Honest boundary in the patch doc.

## Security defaults this playbook sets
- **`ALLOWED_EMAILS`** — only your address can register (the endpoint is public, but locked to you)
- **Rate limiting** — 5/min on login/register
- **Zero-knowledge** — D1 holds only ciphertext
- Recommends **TOTP 2FA** + **full-disk encryption** + **2FA on your Cloudflare account** (it's part of the security boundary)

## Credits
[`warden-worker`](https://github.com/qaz741wsd856/warden-worker) (MIT) · [`bw_web_builds`](https://github.com/dani-garcia/bw_web_builds) · official [Bitwarden](https://bitwarden.com) apps. API-key patch + Claude install playbook: this repo.

*Not affiliated with Bitwarden, Inc. "Bitwarden" is a trademark of Bitwarden, Inc.*

## License
MIT
