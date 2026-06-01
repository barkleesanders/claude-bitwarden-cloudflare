# The Organizations patch (Phase 1)

`warden-worker` ships as a **personal-vault** engine — it has no Organizations or shared
Collections. This optional patch adds them, **clean-room** (implemented from the public Bitwarden
API contract + official-client behavior — **no Vaultwarden/AGPL code**), so the repo stays MIT.

Why it's possible on Cloudflare Workers at all: **all organization crypto is client-side.** When you
add a member, an existing member's client wraps the Organization Symmetric Key with the new member's
RSA public key and uploads that blob ([Bitwarden whitepaper](https://bitwarden.com/help/bitwarden-security-white-paper/)).
The server only stores encrypted blobs and enforces access — pure CRUD + ACL, which is exactly what
D1 + Workers do. warden-worker's sync protocol already declared the (empty) `organizations` field;
this fills it in.

## Apply it (after the API-key patch)

```bash
cd warden-worker
git apply ../claude-bitwarden-cloudflare/patches/api-key.patch          # if not already applied
git apply ../claude-bitwarden-cloudflare/patches/organizations.patch
cp ../claude-bitwarden-cloudflare/patches/0015_add_organizations.sql migrations/0015_add_organizations.sql
```

It applies cleanly on top of `api-key.patch` (verified) and builds with `worker-build --release`
(0 errors, 0 clippy warnings).

## What Phase 1 adds (8 files, ~843 insertions)

| File | Change |
|---|---|
| `migrations/0015_add_organizations.sql` | 5 tables: `organizations`, `organization_users`, `collections`, `collection_users`, `collection_ciphers` |
| `sql/schema.sql` | same tables for fresh installs |
| `src/models/organization.rs` | DB structs, request DTOs, Bitwarden-contract JSON builders |
| `src/handlers/organizations.rs` | create-org, get-org, collections CRUD, sync helpers, ACL gate |
| `src/handlers/sync.rs` | fills `profile.organizations` + `collections` in `GET /api/sync` |
| `src/router.rs` | routes the org + collection endpoints |
| `src/{handlers,models}/mod.rs` | module registration |

**Endpoints:** `POST /api/organizations`, `GET /api/organizations/{id}`,
`GET|POST /api/organizations/{id}/collections`, `PUT|POST|DELETE /api/organizations/{id}/collections/{cid}`,
`GET /api/collections`.

## Security model

- Every org endpoint goes through `require_org_member` (you must have a membership row); collection
  writes additionally require `require_org_manage` (Owner/Admin).
- The server stores only: the org RSA keypair (private key already encrypted with the org symmetric
  key) and, per member, the org symmetric key wrapped with that member's public key (`akey`). It
  never sees plaintext keys.

## Status — be honest about what's NOT done yet

**Phase 1 = the data model + your own orgs/collections.** It lets you create an organization and
collections and have them appear in sync. It does **not yet** do the thing orgs are *for*:

- ❌ **Inviting other users / multi-member sharing** — Phase 2 (Cloudflare-native: the Workers Email
  Routing `send_email` binding, plus a manual admin-confirm flow that needs no external email).
- ❌ **Moving a cipher into a shared collection** (`/api/ciphers/{id}/share`) — Phase 2.
- ❌ **Per-collection ACLs for non-owner members, Groups** — Phase 2/3.

So **until Phase 2 lands, treat the deployment as personal-vault.** Phase 1 is the foundation that
proves orgs run on Workers and compiles clean — not a finished team-sharing feature.

## Deploying it (it's additive + backward-compatible)

The migration only **adds** tables; it changes nothing existing. Sync returns your same
ciphers/folders/sends plus empty `organizations`/`collections` if you have no orgs. To go live you'd
apply `0015` to your D1 and redeploy — see the repo README's deploy section. Not deploying changes
nothing.
