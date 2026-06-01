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
cp ../claude-bitwarden-cloudflare/patches/0015_add_organizations.sql migrations/0015_add_organizations.sql
```

Verified: applies cleanly on top of `api-key.patch`; builds with `worker-build --release`
(0 errors, 0 clippy warnings). ~2,100 insertions across 10 files.

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

## Genuinely deferred (not needed for orgs + shared collections to work)

Groups, SSO/SCIM, policies, event logs, admin reset-password, the `access_all` membership flag,
outbound invite email, and org-cipher **archive/partial-field** edits (personal-vault features).
None of these block the create-org → invite → confirm → share → use flow.

## Deploying it (additive + backward-compatible)

The migration only **adds** tables; existing `users`/`ciphers`/`folders`/`sends` are untouched. Sync
returns your same vault plus your orgs/collections (empty if you have none). To go live: apply
`0015_add_organizations.sql` to your D1 and redeploy (see the repo README's deploy section). Not
deploying changes nothing.
