#!/usr/bin/env bash
# Self-hosted Bitwarden on Cloudflare Workers — one-command installer.
#
#   ./install.sh --email you@example.com --domain example.com [--subdomain vault] [--dry-run]
#
# Deploys the warden-worker server + the API-key patch to YOUR Cloudflare account.
# Requires: wrangler (authenticated: `wrangler login`), git, node 22+, jq, curl.
# For DNS + route automation set CLOUDFLARE_API_TOKEN (Zone:DNS edit + Workers Routes edit);
# otherwise the script prints the two dashboard steps to finish.
set -uo pipefail

REPO_UPSTREAM="https://github.com/qaz741wsd856/warden-worker.git"
HERE="$(cd "$(dirname "$0")" && pwd)"
EMAIL=""; DOMAIN=""; SUB="vault"; DRY=0; WORKDIR="${WORKDIR:-$HOME/warden-worker}"

while [ $# -gt 0 ]; do case "$1" in
  --email) EMAIL="$2"; shift 2;;
  --domain) DOMAIN="$2"; shift 2;;
  --subdomain) SUB="$2"; shift 2;;
  --dry-run) DRY=1; shift;;
  *) echo "unknown arg: $1"; exit 2;;
esac; done

HOST="${SUB}.${DOMAIN}"
say(){ printf '\033[36m›\033[0m %s\n' "$*"; }
run(){ if [ "$DRY" = 1 ]; then printf '   \033[33m[dry-run]\033[0m %s\n' "$*"; else eval "$@"; fi; }
die(){ printf '\033[31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

# ---- 0. validate inputs + prereqs (runs in dry-run too) ----
say "Validating inputs + prerequisites"
[ -n "$EMAIL" ] || die "missing --email (the only address allowed to register)"
[ -n "$DOMAIN" ] || die "missing --domain (a domain on your Cloudflare account)"
for t in git node jq curl; do command -v "$t" >/dev/null || die "missing tool: $t"; done
command -v wrangler >/dev/null || die "missing wrangler (npm i -g wrangler && wrangler login)"
NODEMAJ=$(node -p 'process.versions.node.split(".")[0]'); [ "$NODEMAJ" -ge 22 ] 2>/dev/null || die "node 22+ required (have $NODEMAJ)"
if [ "$DRY" = 0 ]; then wrangler whoami >/dev/null 2>&1 || die "wrangler not authenticated — run: wrangler login"; fi
command -v rustup >/dev/null || say "  (rustup missing — will install it for the wasm build)"
say "  ✓ email=$EMAIL  host=$HOST  workdir=$WORKDIR"

# ---- 1. clone + patch ----
say "Cloning warden-worker + applying the API-key patch"
run "git clone --depth 1 '$REPO_UPSTREAM' '$WORKDIR'"
run "cd '$WORKDIR' && git apply '$HERE/patches/api-key.patch'"
run "cp '$HERE/patches/0014_add_api_key.sql' '$WORKDIR/migrations/0014_add_api_key.sql'"

# ---- 2. Cloudflare resources ----
say "Creating D1 database + KV namespace"
run "cd '$WORKDIR' && wrangler d1 create vault1"
run "cd '$WORKDIR' && wrangler kv namespace create ATTACHMENTS_KV"
say "  → put the printed D1 database_id + KV id into wrangler.toml (the prompt/Claude does this automatically)"

# ---- 3. web vault + toolchain + build ----
say "Downloading bundled web vault + building Rust→WASM worker"
run "cd '$WORKDIR' && BW=v2026.4.1 && wget -q \"https://github.com/dani-garcia/bw_web_builds/releases/download/\$BW/bw_web_\$BW.tar.gz\" && tar -xzf bw_web_\$BW.tar.gz -C public/ && rm bw_web_\$BW.tar.gz && find public/web-vault -name '*.map' -delete"
run "command -v rustup >/dev/null || curl -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain none"
run "cd '$WORKDIR' && PATH=\"\$HOME/.cargo/bin:\$PATH\" rustup show >/dev/null && PATH=\"\$HOME/.cargo/bin:\$PATH\" cargo install --locked -q worker-build --version 0.8.3 && PATH=\"\$HOME/.cargo/bin:\$PATH\" worker-build --release --locked"

# ---- 4. config + secrets ----
say "Setting BASE_URL + email-lock + JWT secrets"
run "cd '$WORKDIR' && sed -i '' 's|# BASE_URL = .*|BASE_URL = \"https://$HOST\"|' wrangler.toml 2>/dev/null || true"
run "cd '$WORKDIR' && printf '%s' '$EMAIL' | wrangler secret put ALLOWED_EMAILS"
run "cd '$WORKDIR' && printf '%s' \"\$(openssl rand -base64 48)\" | wrangler secret put JWT_SECRET"
run "cd '$WORKDIR' && printf '%s' \"\$(openssl rand -base64 48)\" | wrangler secret put JWT_REFRESH_SECRET"

# ---- 5. schema + deploy ----
say "Applying D1 schema + deploying the worker"
run "cd '$WORKDIR' && wrangler d1 execute vault1 --file sql/schema.sql --remote --yes"
run "cd '$WORKDIR' && wrangler deploy"

# ---- 6. DNS + route (CF API if token present, else instructions) ----
say "Attaching https://$HOST"
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  run "ZID=\$(curl -s 'https://api.cloudflare.com/client/v4/zones?name=$DOMAIN' -H \"Authorization: Bearer \$CLOUDFLARE_API_TOKEN\" | jq -r '.result[0].id')"
  run "curl -s -X POST \"https://api.cloudflare.com/client/v4/zones/\$ZID/dns_records\" -H \"Authorization: Bearer \$CLOUDFLARE_API_TOKEN\" -H 'Content-Type: application/json' --data '{\"type\":\"A\",\"name\":\"$HOST\",\"content\":\"192.0.2.1\",\"proxied\":true}'"
  run "curl -s -X POST \"https://api.cloudflare.com/client/v4/zones/\$ZID/workers/routes\" -H \"Authorization: Bearer \$CLOUDFLARE_API_TOKEN\" -H 'Content-Type: application/json' --data '{\"pattern\":\"$HOST/*\",\"script\":\"warden-worker\"}'"
else
  say "  CLOUDFLARE_API_TOKEN not set — finish in the dashboard:"
  say "    1) DNS → add A record '$SUB' → 192.0.2.1 (Proxied / orange cloud)"
  say "    2) Workers & Pages → warden-worker → Settings → Domains & Routes → add route '$HOST/*'"
fi

# ---- 7. verify lock-down ----
say "Verifying the email-lock (a non-allowed email must be rejected)"
run "sleep 30; curl -s -o /dev/null -w 'attacker register -> HTTP %{http_code} (expect 401)\n' -X POST 'https://$HOST/identity/accounts/register' -H 'Content-Type: application/json' -d '{\"email\":\"attacker@evil.com\",\"masterPasswordHash\":\"x\",\"userSymmetricKey\":\"x\",\"userAsymmetricKeys\":{\"publicKey\":\"x\",\"encryptedPrivateKey\":\"x\"},\"kdf\":0,\"kdfIterations\":600000}'"

echo
if [ "$DRY" = 1 ]; then
  printf '\033[32m✓ DRY RUN complete — every step validated, nothing created.\033[0m\n'
else
  printf '\033[32m✓ Done. Open https://%s, click Create account (use %s), set a master password, enable TOTP.\033[0m\n' "$HOST" "$EMAIL"
fi
