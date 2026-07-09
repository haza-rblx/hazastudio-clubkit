CREATE INDEX IF NOT EXISTS idx_donations_game_received_at
ON donations(game_id, received_at);

CREATE INDEX IF NOT EXISTS idx_donations_game_donation_at
ON donations(game_id, donation_at);
