-- Store the resolved Roblox display name alongside the username/user id so
-- donations can auto-merge to the correct player when they donate.
ALTER TABLE donor_links ADD COLUMN roblox_display_name TEXT NOT NULL DEFAULT '';
