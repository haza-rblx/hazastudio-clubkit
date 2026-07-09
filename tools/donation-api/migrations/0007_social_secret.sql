-- Per-game secret for Game Data API (friends count / social push).
-- Managed from donation admin dashboard; read by game-data-api worker via shared D1.
ALTER TABLE games ADD COLUMN social_secret TEXT NOT NULL DEFAULT '';
