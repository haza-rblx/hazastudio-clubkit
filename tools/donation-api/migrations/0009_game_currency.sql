-- Per-game cash display currency, for admin dashboard labels only.
-- Kit config (ClubKitConfig.Donation.Currency) remains the source of truth in-game;
-- this column is display-only for ops (no engine sync). "IDR" | "PHP".
ALTER TABLE games ADD COLUMN currency TEXT NOT NULL DEFAULT 'IDR';
