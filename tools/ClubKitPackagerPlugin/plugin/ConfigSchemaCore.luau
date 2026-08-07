--!nocheck
--[[
  Load ClubKitConfigSchema from the synced engine in the open place.
  Plugin Config UI reads FEATURE_MANIFEST from schema (single source of truth).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigSchemaCore = {}

-- Used when place engine tag predates ClubKitConfigSchema (plugin still works).
local FALLBACK_FEATURE_MANIFEST = {
	{
		name = "Music & dance",
		items = {
			{ key = "MusicPlayer", label = "Music player" },
			{ key = "MusicCatalogSeed", label = "Default playlist" },
			{ key = "SyncDance", label = "Sync dance" },
			{ key = "LegacySyncBhms", label = "Legacy SyncBhms place-pack" },
		},
	},
	{
		name = "Interface",
		items = {
			{ key = "Hotbar", label = "Hotbar" },
			{ key = "LoadingScreen", label = "Loading screen" },
			{ key = "Settings", label = "Settings menu" },
			{ key = "JoinGreetings", label = "Join greetings" },
			{ key = "PromptJoinCommunityOnLoad", label = "Join community prompt" },
			{ key = "AdminHub", label = "Admin Hub (04-AdminHub)" },
		},
	},
	{
		name = "Social & progression",
		items = {
			{ key = "Couples", label = "Couple system" },
			{ key = "Stickers", label = "Stickers" },
			{ key = "LevelSystem", label = "Level & XP" },
		},
	},
	{
		name = "Monetization",
		items = {
			{ key = "Shop", label = "Shop" },
			{ key = "Leaderboards", label = "Donation boards" },
			{ key = "DonationCash", label = "Cash donations" },
			{ key = "DonationRobux", label = "Robux donations" },
			{ key = "DonationWorldEffects", label = "Donation world effects" },
		},
	},
	{
		name = "More",
		items = {
			{ key = "Gravity", label = "Gravity tool" },
			{ key = "VipOnCommunityJoin", label = "Free VIP for group members" },
			{ key = "DonationRankGradientAnim", label = "Donor rank animation" },
		},
	},
}

function ConfigSchemaCore.findSchemaModule(): ModuleScript?
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local shared = kit and kit:FindFirstChild("Shared")
	local configFolder = shared and shared:FindFirstChild("Config")
	local schema = configFolder and configFolder:FindFirstChild("ClubKitConfigSchema")
	if schema and schema:IsA("ModuleScript") then
		return schema
	end
	return nil
end

function ConfigSchemaCore.requireSchema(): (any?, string?)
	local schemaMod = ConfigSchemaCore.findSchemaModule()
	if not schemaMod then
		return nil, "ClubKitConfigSchema not in place (Update Engine to latest tag)"
	end
	local ok, schema = pcall(require, schemaMod)
	if not ok or type(schema) ~= "table" then
		return nil, "Failed to require ClubKitConfigSchema: " .. tostring(schema)
	end
	return schema, nil
end

function ConfigSchemaCore.getFeatureGroups(): ({ any }, string?)
	local schema, err = ConfigSchemaCore.requireSchema()
	if schema then
		if type(schema.getFeatureGroups) == "function" then
			local groups = schema.getFeatureGroups()
			if type(groups) == "table" and #groups > 0 then
				return groups, nil
			end
		end
		if type(schema.FEATURE_MANIFEST) == "table" and #schema.FEATURE_MANIFEST > 0 then
			return schema.FEATURE_MANIFEST, nil
		end
	end
	return FALLBACK_FEATURE_MANIFEST, err
end

function ConfigSchemaCore.getFeatureKeys(): { string }
	local schema = ConfigSchemaCore.requireSchema()
	if schema and type(schema.getFeatureKeys) == "function" then
		local keys = schema.getFeatureKeys()
		if type(keys) == "table" and #keys > 0 then
			return keys
		end
	end

	local keys: { string } = {}
	local seen: { [string]: boolean } = {}
	local groups = ConfigSchemaCore.getFeatureGroups()
	for _, group in groups do
		if type(group.items) == "table" then
			for _, item in group.items do
				local key = if type(item) == "table" then (item.key or item[1]) else nil
				if type(key) == "string" and key ~= "" and not seen[key] then
					seen[key] = true
					table.insert(keys, key)
				end
			end
		end
	end
	return keys
end

return ConfigSchemaCore
