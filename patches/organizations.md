# The Organizations patch

`warden-worker` ships as a **personal-vault** engine — no Organizations or shared Collections.
This optional patch adds a **working** Organizations + shared-Collections + member-sharing feature,
implemented **clean-room** from the public Bitwarden API contract + official-client behavior
(**no Vaultwarden/AGPL code**), so the repo stays MIT.

Why it works on Cloudflare Workers: **all organization crypto is client-side.** When you add a
member, an existing member's client wraps the Organization Symmetric Key with the new member's RSA
public key and uploads that blob ([Bitwarden whitepaper](https://bitwarden.com/help/bitwarden-security-white-paper/)).
The server only stores encrypted blobs + per-member wrapped keys and enforces access — pure CRUD +
ACL, which is exactly what D1 + Workers do.

## Apply it (after the API-key patch)

```bash
cd warden-worker
git apply ../claude-bitwarden-cloudflare/patches/api-key.patch          # if not already applied
git apply ../claude-bitwarden-cloudflare/patches/organizations.patch
git apply ../claude-bitwarden-cloudflare/patches/login-hardening.patch  # clear login errors + failed-only rate limit
cp ../claude-bitwarden-cloudflare/patches/0015_add_organizations.sql migrations/0015_add_organizations.sql
cp ../claude-bitwarden-cloudflare/patches/0016_add_org_enterprise.sql migrations/0016_add_org_enterprise.sql
```

`login-hardening.patch` (error.rs + identity.rs) makes a failed login return the proper Bitwarden
error body — so the web vault shows *"Incorrect master password…"* / *"No account is registered
for `<email>`…"* instead of a generic "unexpected error" — and changes the login rate limiter to
count **only failed attempts**, so a correct password is never throttled (no self-lockout across
multiple devices/2FA round-trips). The `sso_auth_codes` table + `client_*` columns the OIDC
authorization-code grant needs are included in `0016_add_org_enterprise.sql`.

Verified end-to-end against a **fresh upstream clone**: all three patches `git apply` cleanly in
sequence, and the assembled `src/` tree is byte-for-byte identical to the live, deployed worker
(0 file diffs). Builds with `worker-build --release` (0 errors, 0 clippy warnings).

> **⚠️ Required `wrangler.toml` change (or `/sso/*` and `/scim/*` will 404 in production).**
> warden-worker serves non-API paths as static assets. The new SSO + SCIM routes live outside
> `/api/*`, so you must add them to `run_worker_first`:
> ```toml
> run_worker_first = ["/api/*", "/identity/*", "/notifications/*", "/sso/*", "/scim/*"]
> ```
> (This was caught by the end-to-end test below — a unit test wouldn't have.)

## What it adds (full working flow)

- **Create / edit / delete organizations**, leave an org, fetch org keys.
- **Members:** invite by email, accept, **confirm** (admin stores the member-wrapped org key),
  change member type, remove. Last-owner protection on remove/demote/leave.
- **Collections:** create/rename/delete, plus **per-collection member assignment** with
  read-only / hide-passwords / manage flags.
- **Cipher sharing:** move a personal cipher into an org (`/share`), set a cipher's collections,
  create ciphers directly in an org. Org ciphers are **org-owned** (`user_id` NULL) and reached via
  collection membership.
- **ACL-enforced everything:** sync, read, edit, and delete of org ciphers respect membership +
  per-collection access; owners/admins see all org ciphers, regular members see only their
  collections.
- **`GET /api/users/{id}/public-key`** so the admin client can wrap the org key on confirm.

### Endpoints

```
POST   /api/organizations                              create
GET    /api/organizations/{id}                         profile (members)
PUT    /api/organizations/{id}                          edit (owner)
DELETE /api/organizations/{id}                          delete (owner)
GET    /api/organizations/{id}/keys                     org keypair (members)
POST   /api/organizations/{id}/leave                    leave
GET    /api/organizations/{id}/users                    list members
POST   /api/organizations/{id}/users/invite             invite by email (owner/admin)
GET    /api/organizations/{id}/users/{ouid}             member detail
PUT    /api/organizations/{id}/users/{ouid}             change type + collections
DELETE /api/organizations/{id}/users/{ouid}             remove member
POST   /api/organizations/{id}/users/{ouid}/accept      invited user accepts
POST   /api/organizations/{id}/users/{ouid}/confirm     admin confirms (stores wrapped key)
GET|POST|PUT|DELETE /api/organizations/{id}/collections[/{cid}]    collections CRUD
GET|PUT /api/organizations/{id}/collections/{cid}/users           member assignment
GET    /api/collections                                 all the caller's collections
PUT|POST /api/ciphers/{id}/share                        move a personal cipher into an org
PUT|POST /api/ciphers/{id}/collections                  set an org cipher's collections
GET    /api/users/{id}/public-key
```

## Cloudflare-native invites (no external email required)

Cloudflare's free tier can't reliably send arbitrary outbound email (the MailChannels integration
ended; Email Routing's `send_email` binding only delivers to *verified* destinations). So invites
default to **manual-confirm**, which needs no email at all:

1. Admin invites an email that **already has an account on this vault**. In manual mode
   (`ORG_AUTO_ACCEPT_INVITES` defaults to `true`) the membership is created as **Accepted**.
2. The org appears in that user's own vault on their next sync.
3. Admin **confirms** the member (their client wraps the org key with the member's public key).

Set `ORG_AUTO_ACCEPT_INVITES="false"` to require the invited user to explicitly **accept** first
(the standard Invited → Accepted → Confirmed flow). Wiring real outbound notification email would
require an external provider (e.g. Resend) or Email Routing with verified destinations — optional,
not required for the flow to work.

## Security model

- Every org endpoint passes `require_org_member`; writes pass `require_org_manage` (Owner/Admin).
- **Cross-org guards:** linking a cipher to a collection verifies the collection belongs to the
  cipher's own org; assigning collections to a member ignores collections outside the org.
- Org ciphers are stored org-owned (`user_id` NULL); read uses "member can access", edit/delete use
  "member can manage" (owner/admin, or `manage` on a holding collection).
- The server stores only the org RSA keypair (private key already encrypted with the org symmetric
  key) and, per member, the org symmetric key wrapped with that member's public key. Never plaintext.

## Enterprise features (also included)

These go beyond "orgs + shared collections" — added on request, all compiling:

- **Groups** — group CRUD, group↔collection grants, group membership; group-based access is
  honored in the cipher ACL (sync/read/edit). `…/organizations/{id}/groups[...]`.
- **Policies** — upsert/list/read org policies. `…/organizations/{id}/policies[/{type}]`.
- **Event logs** — an audit trail of org admin actions (org/member/collection/group/policy
  mutations), readable by admins. `GET …/organizations/{id}/events`.
- **Outbound invite email** — best-effort, **optional**, two transports (first configured wins):
  1. **Gmail API** — send as a real Gmail / Google Workspace account. Set Worker **secrets**
     `GMAIL_REFRESH_TOKEN`, `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET` + a var `EMAIL_FROM` (the
     authenticated account or a verified send-as alias). The Worker exchanges the refresh token
     for a short-lived access token and calls `users.messages.send`. **Verified end-to-end**: an
     invite triggered from the Admin Console produced a `messages.send` `HTTP 200` and the email
     landed in the recipient's inbox.
  2. **Resend-compatible endpoint** (fallback) — set `EMAIL_PROVIDER_URL` + `EMAIL_API_KEY`
     (secret) + `EMAIL_FROM`.
  No-op (and invites still work via manual-confirm) if neither is configured. **No credentials
  live in this repo** — only the env-var *names*; you supply the secrets via `wrangler secret`.
- **SCIM v2 provisioning** — bearer-token Users endpoints (`/scim/v2/{orgId}/Users`) for
  list/create/get/delete, plus token management (`…/organizations/{id}/scim/tokens`). Maps to org
  memberships.
- **SSO (OIDC)** — config storage + management (`…/organizations/{id}/sso`) and an
  authorize/callback OIDC flow.

### SSO — built and **tested end-to-end** (one remaining caveat)

The full OIDC login flow is implemented and **verified working end-to-end** by an automated test
(`tools/sso-e2e-test.mjs`) that runs the real worker under `wrangler dev` against a controlled OIDC
IdP and drives the whole chain:

1. `authorize` redirects to the IdP, carrying the web vault's `state` / `redirectUri` /
   `codeChallenge` through the round-trip.
2. `callback` runs OIDC **discovery**, fetches the IdP **JWKS**, and **verifies the id_token's RS256
   signature (WebCrypto) + iss/aud/exp/nonce** — real authentication, not a decode.
3. It links the IdP subject to a vault account, mints a **one-time Bitwarden SSO authorization code**,
   and redirects back to the web vault.
4. `/identity/connect/token`'s **`authorization_code` grant** (with **PKCE S256**) redeems the code
   and issues a real warden access token.

The test passes: `authorize → IdP → callback (JWKS RS256 verify + link) → SSO code → token`. It also
caught three real bugs during development (the `run_worker_first` routing gap above, a JWK-as-JS-Map
WebCrypto rejection, and an identifier-conflict 500) — all fixed.

**The remaining caveat:** the controlled IdP exercises the exact OIDC contract, but this has **not
been driven by the *official Bitwarden web-vault* SSO UI** (its prevalidate/connector redirect
specifics are version-coupled) nor against a specific commercial IdP — confirm against yours before
relying on it. And SSO does **not** give password-less unlock: the vault is end-to-end encrypted, so
you still enter your master password to decrypt (password-less needs Key Connector / TDE — not
included). Run the test yourself: `node tools/sso-e2e-test.mjs` with `wrangler dev` running locally.

## Still not included

Admin reset-password (Key Connector / TDE), the `access_all` membership flag, and org-cipher
**favorite/folder partial edits** (these are per-user personal associations the shared schema can't
model without a per-user cipher-state table — archive *is* extended to org managers). None block the
create-org → invite → confirm → share → use flow.

## Deploying it (additive + backward-compatible)

The migration only **adds** tables; existing `users`/`ciphers`/`folders`/`sends` are untouched. Sync
returns your same vault plus your orgs/collections (empty if you have none). To go live: apply
`0015_add_organizations.sql` to your D1 and redeploy (see the repo README's deploy section). Not
deploying changes nothing.

## Inviting real teammates (registration + optional email)

For the Admin Console **Invite member** dialog to fully work, three endpoints the members page
loads were added (they were mis-routed to wildcards before): `GET /organizations/{id}/collections/details`,
`GET /ciphers/organization-details`, and the self-host billing metadata. Without them the org-admin
component's data load rejects and the Invite button does nothing — fixed and verified by driving the
live web vault over CDP.

Two more pieces make invites usable by *other people*:

1. **Invited emails can self-register.** The `/identity/accounts/register` endpoint now allows any
   email that holds a pending org invite (in addition to `ALLOWED_EMAILS`), and **links the new
   account to its pending memberships on signup**. So you don't hand-edit an allowlist per person.
   Set `DISABLE_USER_REGISTRATION="false"` so invitees see the **Create account** button — the
   endpoint still rejects anyone who isn't allowed-or-invited.

2. **Outbound invite email is optional — and proven.** Easiest reliable transport is the **Gmail
   API**: set Worker secrets `GMAIL_REFRESH_TOKEN` / `GMAIL_CLIENT_ID` / `GMAIL_CLIENT_SECRET` and a
   var `EMAIL_FROM` (the authenticated Gmail/Workspace account, or a verified send-as alias). The
   Worker mints a short-lived access token from the refresh token and calls `users.messages.send`;
   invitees get a real notification from your address. (A Resend-compatible endpoint via
   `EMAIL_PROVIDER_URL` + `EMAIL_API_KEY` is the fallback.) **All credentials are Worker secrets,
   never in this repo.** **Without any of it, invites still work** — the org appears in the
   invitee's vault after they register, and an admin confirms them.

   > How to get a Gmail refresh token without a custom OAuth app: authorize the account once with a
   > desktop OAuth client (e.g. the `gogcli` tool, or your own Google Cloud OAuth client with the
   > `gmail.send`/`gmail.modify` scope), then store the resulting refresh token + client id/secret
   > as the three Worker secrets above. The grant only needs send scope.

**Flow without email:** invite → tell the person to open the vault and create an account → it links
to their invite → they appear in your members list → you confirm them (their client wraps the org
key). **Flow with email:** same, but they get a notification instead of you telling them.
