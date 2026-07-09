CREATE TABLE IF NOT EXISTS games (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  webhook_token TEXT NOT NULL,
  secret TEXT NOT NULL,
  provider_link TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS donor_links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL,
  saweria_name TEXT NOT NULL,
  saweria_name_lc TEXT NOT NULL,
  roblox_username TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE (game_id, saweria_name_lc),
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS donations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL,
  provider_tx_id TEXT NOT NULL,
  saweria_name TEXT NOT NULL,
  saweria_name_lc TEXT NOT NULL,
  amount INTEGER NOT NULL,
  message TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'success',
  received_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  donation_at TEXT NOT NULL,
  raw_payload TEXT NOT NULL,
  UNIQUE (game_id, provider_tx_id),
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_donations_game_received
ON donations(game_id, received_at DESC);

CREATE INDEX IF NOT EXISTS idx_donations_game_donor
ON donations(game_id, saweria_name_lc);
