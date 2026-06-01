-- Migration: add api_key column to users table.
-- Stores the personal API key (client secret) used by `bw login --apikey`
-- and the client_credentials grant on /identity/connect/token.
-- NULL until the user first views/rotates their API key.
ALTER TABLE users ADD COLUMN api_key TEXT;
