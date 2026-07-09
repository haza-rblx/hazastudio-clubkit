-- 0005_game_admin_token.sql
-- Adds a per-game admin token for scoped dashboard access.
-- Master ADMIN_TOKEN (env) still works as super admin; new column enables
-- issuing a token that can only manage a single game.

ALTER TABLE games ADD COLUMN admin_token TEXT NOT NULL DEFAULT '';
