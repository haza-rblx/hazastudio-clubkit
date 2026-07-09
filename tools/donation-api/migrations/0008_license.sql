-- Per-game license tracking for Club Kit v1.3+.
-- license_enforced = 0: legacy games / kits that never call verify (unchanged behavior).
-- license_enforced = 1: set on first verify from Club Kit v1.3+; full enforcement applies.

ALTER TABLE games ADD COLUMN license_status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE games ADD COLUMN license_enforced INTEGER NOT NULL DEFAULT 0;
ALTER TABLE games ADD COLUMN universe_id TEXT NOT NULL DEFAULT '';
ALTER TABLE games ADD COLUMN place_id TEXT NOT NULL DEFAULT '';
ALTER TABLE games ADD COLUMN license_note TEXT NOT NULL DEFAULT '';
ALTER TABLE games ADD COLUMN maintenance_until TEXT NOT NULL DEFAULT '';
ALTER TABLE games ADD COLUMN last_seen_at TEXT NOT NULL DEFAULT '';
ALTER TABLE games ADD COLUMN last_seen_universe_id TEXT NOT NULL DEFAULT '';
ALTER TABLE games ADD COLUMN kit_build_id TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_games_license_status ON games(license_status);
CREATE INDEX IF NOT EXISTS idx_games_universe_id ON games(universe_id);
