-- Migration 0006: Admin scoped tokens for game-specific shareable links.

CREATE TABLE IF NOT EXISTS admin_scoped_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token_hash TEXT NOT NULL UNIQUE,
  game_keys TEXT NOT NULL,  -- JSON array of game keys, e.g. ["nuwa"]
  created_by TEXT,          -- game_key of the creator
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_scoped_tokens_hash ON admin_scoped_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_scoped_tokens_expires ON admin_scoped_tokens(expires_at);
