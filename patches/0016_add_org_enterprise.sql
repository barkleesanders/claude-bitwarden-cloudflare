-- Enterprise org features (clean-room): Groups, Policies, Event logs, SSO (OIDC), SCIM.
-- All additive; nothing existing is modified.

-- ---- Groups ----
CREATE TABLE IF NOT EXISTS groups (
    id TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    name TEXT NOT NULL,
    external_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_groups_org ON groups(organization_id);

CREATE TABLE IF NOT EXISTS group_users (
    group_id TEXT NOT NULL,
    organization_user_id TEXT NOT NULL,
    PRIMARY KEY (group_id, organization_user_id),
    FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
    FOREIGN KEY (organization_user_id) REFERENCES organization_users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS collection_groups (
    collection_id TEXT NOT NULL,
    group_id TEXT NOT NULL,
    read_only INTEGER NOT NULL DEFAULT 0,
    hide_passwords INTEGER NOT NULL DEFAULT 0,
    manage INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (collection_id, group_id),
    FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE,
    FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
);

-- ---- Policies ----
CREATE TABLE IF NOT EXISTS org_policies (
    organization_id TEXT NOT NULL,
    ptype INTEGER NOT NULL,                 -- Bitwarden PolicyType enum
    enabled INTEGER NOT NULL DEFAULT 0,
    data TEXT,                              -- JSON config blob (nullable)
    PRIMARY KEY (organization_id, ptype),
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);

-- ---- Event logs ----
CREATE TABLE IF NOT EXISTS org_events (
    id TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    event_type INTEGER NOT NULL,            -- Bitwarden EventType enum
    acting_user_id TEXT,                    -- who performed it
    member_id TEXT,                         -- affected organization_users.id
    cipher_id TEXT,
    collection_id TEXT,
    group_id TEXT,
    policy_id INTEGER,
    device_type INTEGER,
    ip_address TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_org_events_org ON org_events(organization_id, created_at);

-- ---- SSO (OIDC) ----
CREATE TABLE IF NOT EXISTS org_sso_config (
    organization_id TEXT PRIMARY KEY NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 0,
    identifier TEXT UNIQUE,                 -- the org's SSO identifier users type at login
    authority TEXT,                         -- OIDC issuer URL
    client_id TEXT,
    client_secret TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);

-- Links an IdP subject to a warden user, per org.
CREATE TABLE IF NOT EXISTS sso_users (
    organization_id TEXT NOT NULL,
    external_id TEXT NOT NULL,              -- IdP subject (sub claim)
    user_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (organization_id, external_id),
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Short-lived OIDC login state (CSRF + nonce + PKCE verifier).
-- client_* columns carry the web vault's own SSO params through the IdP round-trip.
CREATE TABLE IF NOT EXISTS sso_login_state (
    state TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    nonce TEXT NOT NULL,
    code_verifier TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    client_state TEXT,
    client_redirect_uri TEXT,
    client_code_challenge TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);

-- One-time Bitwarden SSO authorization codes (issued at callback, redeemed at
-- /identity/connect/token grant_type=authorization_code).
CREATE TABLE IF NOT EXISTS sso_auth_codes (
    code TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL,
    organization_id TEXT NOT NULL,
    code_challenge TEXT,                    -- PKCE S256 challenge from the web vault
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);

-- ---- SCIM ----
CREATE TABLE IF NOT EXISTS scim_tokens (
    id TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    token_hash TEXT NOT NULL,               -- SHA-256 of the bearer token
    created_at TEXT NOT NULL,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_scim_tokens_hash ON scim_tokens(token_hash);
