-- Organizations + shared Collections (Phase 1)
-- Clean-room implementation of the Bitwarden Organizations data model.
-- All org crypto is client-side: the server only stores the org RSA keypair
-- (private key already encrypted with the org symmetric key) and, per member,
-- the org symmetric key wrapped with that member's RSA public key (akey).
-- The server never sees plaintext keys.

CREATE TABLE IF NOT EXISTS organizations (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,                       -- org display name (plaintext, like Bitwarden)
    billing_email TEXT NOT NULL DEFAULT '',
    public_key TEXT NOT NULL,                 -- org RSA public key
    private_key TEXT NOT NULL,                -- org RSA private key, encrypted with the org symmetric key
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS organization_users (
    id TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    user_id TEXT,                             -- NULL while invited-by-email and not yet linked (Phase 2)
    email TEXT NOT NULL,                      -- invited/member email
    akey TEXT,                                -- org symmetric key wrapped with THIS member's RSA public key (NULL until confirmed)
    status INTEGER NOT NULL DEFAULT 0,        -- 0=Invited, 1=Accepted, 2=Confirmed
    atype INTEGER NOT NULL DEFAULT 2,         -- 0=Owner, 1=Admin, 2=User, 3=Manager
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_org_users_user ON organization_users(user_id);
CREATE INDEX IF NOT EXISTS idx_org_users_org ON organization_users(organization_id);

CREATE TABLE IF NOT EXISTS collections (
    id TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    name TEXT NOT NULL,                       -- encrypted with the org symmetric key
    external_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_collections_org ON collections(organization_id);

CREATE TABLE IF NOT EXISTS collection_users (
    collection_id TEXT NOT NULL,
    organization_user_id TEXT NOT NULL,
    read_only INTEGER NOT NULL DEFAULT 0,
    hide_passwords INTEGER NOT NULL DEFAULT 0,
    manage INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (collection_id, organization_user_id),
    FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE,
    FOREIGN KEY (organization_user_id) REFERENCES organization_users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS collection_ciphers (
    collection_id TEXT NOT NULL,
    cipher_id TEXT NOT NULL,
    PRIMARY KEY (collection_id, cipher_id),
    FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE,
    FOREIGN KEY (cipher_id) REFERENCES ciphers(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_collection_ciphers_cipher ON collection_ciphers(cipher_id);
