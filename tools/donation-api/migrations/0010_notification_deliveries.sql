-- Enterprise-grade notification delivery tracking.
-- One row per (donation × recipient player): the server registers intent to
-- deliver, the client acks after the notification is actually displayed.
-- Rows that exhaust retries land in status='dlq' for audit — never silently
-- dropped. Additive-only; no changes to existing tables.

CREATE TABLE IF NOT EXISTS notification_deliveries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL,
  donation_id INTEGER NOT NULL,
  roblox_user_id INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- pending | sent | acked | dlq | failed_resolve (roblox_user_id=0 sentinel)
  attempts INTEGER NOT NULL DEFAULT 0,
  first_sent_at TEXT,
  last_sent_at TEXT,
  acked_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE (game_id, donation_id, roblox_user_id),
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (donation_id) REFERENCES donations(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_deliveries_game_status
ON notification_deliveries(game_id, status);

CREATE INDEX IF NOT EXISTS idx_deliveries_donation
ON notification_deliveries(donation_id);

-- Append-only ack audit log: every ack received from a game server, even
-- duplicates, so ops can reconstruct exactly what the client confirmed.
CREATE TABLE IF NOT EXISTS delivery_acks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL,
  donation_id INTEGER NOT NULL,
  roblox_user_id INTEGER NOT NULL,
  displayed_at TEXT,
  server_reported_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (donation_id) REFERENCES donations(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_delivery_acks_game_donation
ON delivery_acks(game_id, donation_id);
