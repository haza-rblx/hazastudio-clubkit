PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE d1_migrations(
		id         INTEGER PRIMARY KEY AUTOINCREMENT,
		name       TEXT UNIQUE,
		applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(1,'0001_init.sql','2026-05-26 15:34:13');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(2,'0002_admin_tables.sql','2026-05-26 15:34:13');
CREATE TABLE games (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  webhook_token TEXT NOT NULL,
  secret TEXT NOT NULL,
  provider_link TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
INSERT INTO "games" ("id","game_key","name","webhook_token","secret","provider_link","created_at") VALUES(1,'cf-smoke','CF Smoke','wh_P6T0z5Bw8-QWfLlYKEDYruUdkTii7cti','rbx_lsQ4SFk1s7Rl31Apvn-NNDHSL203Z1cC','https://saweria.co/cfsmoke','2026-05-26T15:52:30.504Z');
CREATE TABLE donor_links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL,
  saweria_name TEXT NOT NULL,
  saweria_name_lc TEXT NOT NULL,
  roblox_username TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), roblox_user_id INTEGER,
  UNIQUE (game_id, saweria_name_lc),
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);
CREATE TABLE donations (
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
  raw_payload TEXT NOT NULL, is_voided INTEGER NOT NULL DEFAULT 0, voided_at TEXT, voided_reason TEXT NOT NULL DEFAULT '',
  UNIQUE (game_id, provider_tx_id),
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);
CREATE TABLE legacy_seed_entries (
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
INSERT INTO "legacy_seed_entries" ("id","game_id","saweria_name","saweria_name_lc","total_amount","rank_hint","note","created_at","updated_at") VALUES(1,1,'bebear_e0','bebear_e0',5100000,NULL,'manual-seed','2026-05-26T15:53:04.883Z','2026-05-26T15:53:04.883Z');
CREATE TABLE webhook_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL,
  received_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  raw_payload TEXT NOT NULL,
  processed INTEGER NOT NULL DEFAULT 0,
  donation_id INTEGER,
  error TEXT NOT NULL DEFAULT '',
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);
DELETE FROM sqlite_sequence;
INSERT INTO "sqlite_sequence" ("name","seq") VALUES('d1_migrations',2);
INSERT INTO "sqlite_sequence" ("name","seq") VALUES('games',1);
INSERT INTO "sqlite_sequence" ("name","seq") VALUES('legacy_seed_entries',1);
CREATE INDEX idx_donations_game_received
ON donations(game_id, received_at DESC);
CREATE INDEX idx_donations_game_donor
ON donations(game_id, saweria_name_lc);
CREATE INDEX idx_legacy_game ON legacy_seed_entries(game_id);
CREATE INDEX idx_webhook_game_time ON webhook_events(game_id, received_at DESC);
