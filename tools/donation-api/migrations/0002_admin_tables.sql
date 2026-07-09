CREATE TABLE IF NOT EXISTS legacy_seed_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL,
  saweria_name TEXT NOT NULL,
  saweria_name_lc TEXT NOT NULL,
  total_amount INTEGER NOT NULL,
  rank_hint INTEGER,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE (game_id, saweria_name_lc),
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS webhook_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL,
  received_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  raw_payload TEXT NOT NULL,
  processed INTEGER NOT NULL DEFAULT 0,
  donation_id INTEGER,
  error TEXT NOT NULL DEFAULT '',
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

ALTER TABLE donations ADD COLUMN is_voided INTEGER NOT NULL DEFAULT 0;
ALTER TABLE donations ADD COLUMN voided_at TEXT;
ALTER TABLE donations ADD COLUMN voided_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE donor_links ADD COLUMN roblox_user_id INTEGER;

CREATE INDEX IF NOT EXISTS idx_legacy_game ON legacy_seed_entries(game_id);
CREATE INDEX IF NOT EXISTS idx_webhook_game_time ON webhook_events(game_id, received_at DESC);
