--!nocheck
--[[
  Read / write buyer ClubKitConfig + Secrets Source from Studio plugin.
  Mutations use line-oriented patches so buyer comments stay where possible.

  Read evaluates a cloned ModuleScript (bypass require cache). Writes patch
  Source lines while preserving trailing commas/comments. Older Saves that
  dropped commas are auto-healed on read/write.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ConfigSchemaCore = require(script.Parent.ConfigSchemaCore)

local ConfigEditCore = {}

export type Snapshot = {
	branding: {
		gameName: string,
		welcome: string,
		logo: string,
	},
	group: {
		groupId: number,
		ownerUserId: number,
		ownerGroupRank: number,
	},
	features: { [string]: boolean },
	membership: {
		[string]: { label: string, enabled: boolean, priority: number },
	},
	shop: {
		[string]: { pass: number, gift: number, buyId: number, price: number },
	},
	donation: {
		provider: string,
		currency: string,
		providerLink: string,
		apiUrl: string,
		cashEnabled: boolean,
		robuxEnabled: boolean,
		minAmount: number,
		nukeWorldPosition: Vector3?,
	},
	secrets: {
		donationApiSecret: string,
		gameDataApiSecret: string,
	},
	ok: boolean,
	error: string?,
}

function ConfigEditCore.getFeatureGroups(): ({ any }, string?)
	return ConfigSchemaCore.getFeatureGroups()
end

function ConfigEditCore.getFeatureKeys(): { string }
	return ConfigSchemaCore.getFeatureKeys()
end

-- Legacy export: refreshed each call so new schema keys appear without plugin rebuild.
function ConfigEditCore.getFEATURE_KEYS(): { string }
	return ConfigEditCore.getFeatureKeys()
end

ConfigEditCore.FEATURE_KEYS = ConfigEditCore.getFeatureKeys()

local function findBuyerConfig(): ModuleScript?
	local folder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKitConfig")
	local mod = folder and folder:FindFirstChild("ClubKitConfig")
	if mod and mod:IsA("ModuleScript") then
		return mod
	end
	return nil
end

local function findSecrets(): ModuleScript?
	local folder = ServerScriptService:FindFirstChild("Hazastudio_ClubKitSecrets")
	local mod = folder and folder:FindFirstChild("Secrets")
	if mod and mod:IsA("ModuleScript") then
		return mod
	end
	return nil
end

-- Prefer fresh ModuleScript evaluation — require(mod) is session-cached and
-- stays stale after Source writes. Clone identity bypasses that cache.
-- Do NOT use loadstring: ClubKitConfig uses Luau `::` type assertions.
local function evaluateModule(mod: ModuleScript): (any?, string?)
	local clone = mod:Clone()
	local ok, result = pcall(require, clone)
	clone:Destroy()
	if ok and result ~= nil then
		return result, nil
	end
	local err = if ok then "module returned nil" else tostring(result)

	local okCached, cached = pcall(require, mod)
	if okCached and cached ~= nil then
		return cached, err
	end
	return nil, err
end

-- Split RHS after `Key = ` into value + trailing suffix (comma / comment).
local function splitAssignmentRhs(rhs: string): (string, string)
	local i = 1
	local len = #rhs
	local function at(n: number): string
		return string.sub(rhs, n, n)
	end
	while i <= len and string.match(at(i), "%s") do
		i += 1
	end
	local start = i
	if i > len then
		return "", rhs
	end
	local c0 = at(i)
	if c0 == '"' or c0 == "'" then
		local quote = c0
		i += 1
		while i <= len do
			local ch = at(i)
			if ch == "\\" then
				i += 2
			elseif ch == quote then
				i += 1
				break
			else
				i += 1
			end
		end
	elseif string.find(rhs, "^[%w_]+%.new%s*%(", i) then
		local open = string.find(rhs, "%(", i)
		if open then
			local depth = 0
			i = open
			while i <= len do
				local ch = at(i)
				if ch == "(" then
					depth += 1
				elseif ch == ")" then
					depth -= 1
					if depth == 0 then
						i += 1
						break
					end
				end
				i += 1
			end
		end
	else
		while i <= len do
			local ch = at(i)
			if ch == "," or ch == "\r" or ch == "\n" then
				break
			end
			if ch == "-" and at(i + 1) == "-" then
				break
			end
			i += 1
		end
		while i > start and string.match(at(i - 1), "%s") do
			i -= 1
		end
	end
	return string.sub(rhs, start, i - 1), string.sub(rhs, i)
end

-- Heal Sources broken by older patchers that dropped trailing commas between fields.
local function healMissingCommas(source: string): string
	-- Undo bad heals that inserted commas right after `{` / `(`
	source = string.gsub(source, "{,", "{")
	source = string.gsub(source, "%(,", "(")

	local lines = string.split(source, "\n")

	local function isFieldLine(line: string): boolean
		return line:match("^%s*[%w_]+%s*=") ~= nil
	end

	local function nextFieldIndex(from: number): number?
		for j = from, #lines do
			local L = lines[j]
			if L:match("^%s*%-%-") then
				-- comment-only line, keep scanning
			elseif L:match("^%s*$") then
				-- blank, keep scanning
			elseif isFieldLine(L) then
				return j
			else
				return nil -- hit `}` / other syntax — stop
			end
		end
		return nil
	end

	local function splitCodeComment(line: string): (string, string)
		local inStr = false
		local commentAt: number? = nil
		local j = 1
		while j <= #line do
			local ch = string.sub(line, j, j)
			if ch == "\\" and inStr then
				j += 2
			elseif ch == '"' then
				inStr = not inStr
				j += 1
			elseif not inStr and ch == "-" and string.sub(line, j + 1, j + 1) == "-" then
				commentAt = j
				break
			else
				j += 1
			end
		end
		if commentAt then
			return string.sub(line, 1, commentAt - 1), string.sub(line, commentAt)
		end
		return line, ""
	end

	for i = 1, #lines - 1 do
		if nextFieldIndex(i + 1) and isFieldLine(lines[i]) then
			local code, comment = splitCodeComment(lines[i])
			code = string.gsub(code, "%s*$", "")
			-- Skip incomplete openers: `Styles = {` / `fn = (`
			if code:match("[{(]%s*$") then
				continue
			end
			if not code:match(",%s*$") then
				if comment ~= "" then
					lines[i] = code .. ", " .. comment
				else
					lines[i] = code .. ","
				end
			end
		end
	end
	return table.concat(lines, "\n")
end

function ConfigEditCore.read(): Snapshot
	local snap: Snapshot = {
		branding = { gameName = "Club", welcome = "Welcome to the club, %s", logo = "" },
		group = { groupId = 0, ownerUserId = 0, ownerGroupRank = 255 },
		features = {},
		membership = {
			Tier1 = { label = "VIP", enabled = true, priority = 40 },
			Tier2 = { label = "VVIP", enabled = true, priority = 50 },
			Tier3 = { label = "Supreme", enabled = true, priority = 60 },
		},
		shop = {
			Tier1 = { pass = 0, gift = 0, buyId = 0, price = 1 },
			Tier2 = { pass = 0, gift = 0, buyId = 0, price = 1 },
			Tier3 = { pass = 0, gift = 0, buyId = 0, price = 1 },
		},
		donation = {
			provider = "bagibagi",
			currency = "IDR",
			providerLink = "",
			apiUrl = "",
			cashEnabled = true,
			robuxEnabled = true,
			minAmount = 1000,
			nukeWorldPosition = nil,
		},
		secrets = { donationApiSecret = "", gameDataApiSecret = "" },
		ok = false,
		error = nil,
	}

	local cfgMod = findBuyerConfig()
	if not cfgMod then
		snap.error = "ClubKitConfig ModuleScript not found under ReplicatedStorage.Hazastudio_ClubKitConfig"
		return snap
	end
	-- Heal commas dropped by older Saves, then evaluate a clone (not cached require).
	do
		local healed = healMissingCommas(cfgMod.Source)
		if healed ~= cfgMod.Source then
			cfgMod.Source = healed
		end
	end
	local cfg, evalErr = evaluateModule(cfgMod)
	if type(cfg) ~= "table" then
		snap.error = "Failed to evaluate ClubKitConfig Source"
			.. (if evalErr then (": " .. evalErr) else "")
		return snap
	elseif evalErr then
		warn("[ClubKit] ClubKitConfig Source still failing after heal; UI may show stale cache. ", evalErr)
	end

	local branding = cfg.Branding or {}
	snap.branding.gameName = tostring(branding.GameName or snap.branding.gameName)
	snap.branding.welcome = tostring(branding.WelcomeMessage or snap.branding.welcome)
	snap.branding.logo = tostring(branding.LogoImage or "")

	local group = cfg.Group or {}
	snap.group.groupId = tonumber(group.GroupId) or 0
	snap.group.ownerUserId = tonumber(group.OwnerUserId) or 0
	snap.group.ownerGroupRank = tonumber(group.OwnerGroupRank) or 255

	local features = cfg.Features or {}
	for _, key in ConfigEditCore.getFeatureKeys() do
		local v = features[key]
		if v == nil and key == "DonationCash" then
			v = features.DonationSaweria
		end
		snap.features[key] = v ~= false
	end

	local membership = cfg.Membership or {}
	for _, tier in { "Tier1", "Tier2", "Tier3" } do
		local t = membership[tier]
		if type(t) == "table" then
			snap.membership[tier] = {
				label = tostring(t.Label or snap.membership[tier].label),
				enabled = t.Enabled ~= false,
				priority = tonumber(t.Priority) or snap.membership[tier].priority,
			}
		end
	end

	local products = (cfg.Shop and cfg.Shop.Products) or {}
	for _, tier in { "Tier1", "Tier2", "Tier3" } do
		local t = products[tier]
		if type(t) == "table" then
			snap.shop[tier] = {
				pass = tonumber(t.BuyGamePassId) or 0,
				gift = tonumber(t.GiftId) or 0,
				buyId = tonumber(t.BuyId) or 0,
				price = tonumber(t.Price) or 1,
			}
		end
	end

	local don = cfg.Donation or {}
	snap.donation.provider = tostring(don.Provider or "bagibagi")
	snap.donation.currency = string.upper(tostring(don.Currency or "IDR"))
	snap.donation.providerLink = tostring(don.ProviderLink or "")
	snap.donation.apiUrl = tostring(don.ApiUrl or "")
	snap.donation.minAmount = tonumber(don.MinAmount) or 1000
	if type(don.Cash) == "table" then
		snap.donation.cashEnabled = don.Cash.Enabled ~= false
	end
	if type(don.Robux) == "table" then
		snap.donation.robuxEnabled = don.Robux.Enabled ~= false
	end
	if typeof(don.NukeWorldPosition) == "Vector3" then
		snap.donation.nukeWorldPosition = don.NukeWorldPosition
	end

	local secretsMod = findSecrets()
	if secretsMod then
		-- Strip illegal statement-level trailing commas from older Saves.
		local cleaned = string.gsub(secretsMod.Source, '(Secrets%.[%w_]+%s*=%s*"[^"]*"%s*),', "%1")
		cleaned = string.gsub(cleaned, "(Secrets%.[%w_]+%s*=%s*'[^']*'%s*),", "%1")
		if cleaned ~= secretsMod.Source then
			secretsMod.Source = cleaned
		end
		local secrets = evaluateModule(secretsMod)
		if type(secrets) == "table" then
			snap.secrets.donationApiSecret = tostring(secrets.DonationApiSecret or "")
			snap.secrets.gameDataApiSecret = tostring(secrets.GameDataApiSecret or "")
		end
	end

	snap.ok = true
	return snap
end

local function escapePattern(s: string): string
	return (string.gsub(s, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function quoteString(s: string): string
	return string.format("%q", s)
end

local function patchAssignment(source: string, key: string, valueLiteral: string): (string, boolean)
	-- Replace value after Key = …; preserve existing trailing comma + comment.
	-- Do NOT invent commas — top-level `Secrets.X = ""` must stay without trailing `,`.
	local pattern = "(%f[%w_]" .. escapePattern(key) .. "%s*=%s*)([^\r\n]*)"
	local found = false
	local nextSource = string.gsub(source, pattern, function(prefix: string, rhs: string)
		found = true
		local _old, suffix = splitAssignmentRhs(rhs)
		local hadComma = string.match(suffix, "^%s*,") ~= nil
		local rest = string.gsub(suffix, "^%s*,%s*", "")
		if hadComma then
			if rest == "" then
				return prefix .. valueLiteral .. ","
			elseif string.match(rest, "^%-%-") then
				return prefix .. valueLiteral .. ", " .. rest
			else
				return prefix .. valueLiteral .. ", " .. rest
			end
		else
			if rest == "" then
				return prefix .. valueLiteral
			elseif string.match(rest, "^%-%-") then
				return prefix .. valueLiteral .. " " .. rest
			else
				return prefix .. valueLiteral .. rest
			end
		end
	end, 1)
	return nextSource, found
end

local function patchNestedBool(source: string, parentKey: string, childKey: string, value: boolean): (string, boolean)
	-- Features.MusicPlayer style: ChildKey = true/false inside a table.
	-- Note: Lua patterns have NO `|` alternation — match true and false separately.
	local lit = value and "true" or "false"
	local keyPref = "(%f[%w_]" .. escapePattern(childKey) .. "%s*=%s*)"
	local found = false
	local nextSource = source
	for _, boolLit in { "true", "false" } do
		local n
		nextSource, n = string.gsub(nextSource, keyPref .. boolLit, function(prefix: string)
			found = true
			return prefix .. lit
		end, 1)
		if found then
			break
		end
	end
	return nextSource, found
end

local function patchTierField(source: string, blockHint: string, tier: string, field: string, valueLiteral: string): (string, boolean)
	-- Locate TierN = { ... Field = value ... } after a hint string (Shop.Products / Membership)
	local hintAt = string.find(source, blockHint, 1, true)
	if not hintAt then
		return source, false
	end
	local tierPat = tier .. "%s*=%s*%{"
	local tierStart = string.find(source, tierPat, hintAt)
	if not tierStart then
		return source, false
	end
	local close = string.find(source, "}", tierStart)
	if not close then
		return source, false
	end
	local chunk = string.sub(source, tierStart, close)
	local fieldPat = "(%f[%w_]" .. escapePattern(field) .. "%s*=%s*)([^,%s}]+)"
	local replaced = false
	local newChunk = string.gsub(chunk, fieldPat, function(prefix: string, _old: string)
		replaced = true
		return prefix .. valueLiteral
	end, 1)
	if not replaced then
		return source, false
	end
	return string.sub(source, 1, tierStart - 1) .. newChunk .. string.sub(source, close + 1), true
end

export type WritePayload = {
	branding: { gameName: string, welcome: string, logo: string }?,
	group: { groupId: number, ownerUserId: number, ownerGroupRank: number }?,
	features: { [string]: boolean }?,
	membership: { [string]: { label: string } }?,
	shop: { [string]: { pass: number, gift: number, buyId: number, price: number } }?,
	donation: {
		provider: string?,
		currency: string?,
		providerLink: string?,
		apiUrl: string?,
		cashEnabled: boolean?,
		robuxEnabled: boolean?,
		minAmount: number?,
		nukeX: number?,
		nukeY: number?,
		nukeZ: number?,
	}?,
	secrets: { donationApiSecret: string?, gameDataApiSecret: string? }?,
}

export type WriteReport = {
	ok: boolean,
	patched: { string },
	message: string,
}

function ConfigEditCore.write(payload: WritePayload): WriteReport
	local patched = {}
	local cfgMod = findBuyerConfig()
	if not cfgMod then
		return { ok = false, patched = {}, message = "ClubKitConfig not found" }
	end

	local source = healMissingCommas(cfgMod.Source)
	local function note(label: string)
		table.insert(patched, label)
	end

	if payload.branding then
		local b = payload.branding
		local ok1
		source, ok1 = patchAssignment(source, "GameName", quoteString(b.gameName))
		if ok1 then
			note("Branding.GameName")
		end
		local ok2
		source, ok2 = patchAssignment(source, "WelcomeMessage", quoteString(b.welcome))
		if ok2 then
			note("Branding.WelcomeMessage")
		end
		local ok3
		source, ok3 = patchAssignment(source, "LogoImage", quoteString(b.logo))
		if ok3 then
			note("Branding.LogoImage")
		end
	end

	if payload.group then
		local g = payload.group
		local ok
		source, ok = patchAssignment(source, "GroupId", tostring(g.groupId))
		if ok then
			note("Group.GroupId")
		end
		source, ok = patchAssignment(source, "OwnerUserId", tostring(g.ownerUserId))
		if ok then
			note("Group.OwnerUserId")
		end
		source, ok = patchAssignment(source, "OwnerGroupRank", tostring(g.ownerGroupRank))
		if ok then
			note("Group.OwnerGroupRank")
		end
	end

	if payload.features then
		for key, value in pairs(payload.features) do
			local ok
			source, ok = patchNestedBool(source, "Features", key, value)
			if ok then
				note("Features." .. key)
			end
		end
	end

	if payload.membership then
		for tier, t in pairs(payload.membership) do
			local ok
			source, ok = patchTierField(source, "Membership", tier, "Label", quoteString(t.label))
			if ok then
				note("Membership." .. tier .. ".Label")
			end
		end
	end

	if payload.shop then
		for tier, t in pairs(payload.shop) do
			local ok
			source, ok = patchTierField(source, "Products", tier, "BuyGamePassId", tostring(t.pass))
			if ok then
				note("Shop.Products." .. tier .. ".BuyGamePassId")
			end
			source, ok = patchTierField(source, "Products", tier, "GiftId", tostring(t.gift))
			if ok then
				note("Shop.Products." .. tier .. ".GiftId")
			end
			source, ok = patchTierField(source, "Products", tier, "BuyId", tostring(t.buyId))
			if ok then
				note("Shop.Products." .. tier .. ".BuyId")
			end
			source, ok = patchTierField(source, "Products", tier, "Price", tostring(t.price))
			if ok then
				note("Shop.Products." .. tier .. ".Price")
			end
		end
	end

	if payload.donation then
		local d = payload.donation
		local ok
		if d.provider then
			source, ok = patchAssignment(source, "Provider", quoteString(d.provider))
			if ok then
				note("Donation.Provider")
			end
		end
		if d.currency then
			source, ok = patchAssignment(source, "Currency", quoteString(string.upper(d.currency)))
			if ok then
				note("Donation.Currency")
			end
		end
		if d.providerLink ~= nil then
			source, ok = patchAssignment(source, "ProviderLink", quoteString(d.providerLink))
			if ok then
				note("Donation.ProviderLink")
			end
		end
		if d.apiUrl ~= nil then
			source, ok = patchAssignment(source, "ApiUrl", quoteString(d.apiUrl))
			if ok then
				note("Donation.ApiUrl")
			end
		end
		if d.minAmount ~= nil then
			source, ok = patchAssignment(source, "MinAmount", tostring(d.minAmount))
			if ok then
				note("Donation.MinAmount")
			end
		end
		if d.nukeX and d.nukeY and d.nukeZ then
			local lit = ("Vector3.new(%s, %s, %s)"):format(tostring(d.nukeX), tostring(d.nukeY), tostring(d.nukeZ))
			source, ok = patchAssignment(source, "NukeWorldPosition", lit)
			if ok then
				note("Donation.NukeWorldPosition")
			end
		end
		-- Cash/Robux Enabled live under nested tables — patch Enabled after Cash/Robux keywords carefully.
		-- Lua patterns have no `|` — match true/false separately.
		if d.cashEnabled ~= nil then
			local cashAt = string.find(source, "Cash%s*=%s*%{")
			if cashAt then
				local close = string.find(source, "}", cashAt)
				if close then
					local chunk = string.sub(source, cashAt, close)
					local lit = d.cashEnabled and "true" or "false"
					local newChunk, n = string.gsub(chunk, "(Enabled%s*=%s*)true", "%1" .. lit, 1)
					if n == 0 then
						newChunk, n = string.gsub(chunk, "(Enabled%s*=%s*)false", "%1" .. lit, 1)
					end
					if n > 0 then
						source = string.sub(source, 1, cashAt - 1) .. newChunk .. string.sub(source, close + 1)
						note("Donation.Cash.Enabled")
					end
				end
			end
		end
		if d.robuxEnabled ~= nil then
			local robuxAt = string.find(source, "Robux%s*=%s*%{")
			if robuxAt then
				local close = string.find(source, "}", robuxAt)
				if close then
					local chunk = string.sub(source, robuxAt, close)
					local lit = d.robuxEnabled and "true" or "false"
					local newChunk, n = string.gsub(chunk, "(Enabled%s*=%s*)true", "%1" .. lit, 1)
					if n == 0 then
						newChunk, n = string.gsub(chunk, "(Enabled%s*=%s*)false", "%1" .. lit, 1)
					end
					if n > 0 then
						source = string.sub(source, 1, robuxAt - 1) .. newChunk .. string.sub(source, close + 1)
						note("Donation.Robux.Enabled")
					end
				end
			end
		end
	end

	local writeOk, writeErr = pcall(function()
		cfgMod.Source = source
	end)
	if not writeOk then
		return { ok = false, patched = patched, message = "Failed writing ClubKitConfig: " .. tostring(writeErr) }
	end

	if payload.secrets then
		local secretsMod = findSecrets()
		if secretsMod then
			-- Fix legacy Saves that added illegal trailing commas after statement assignments.
			local secSrc = string.gsub(secretsMod.Source, '(Secrets%.[%w_]+%s*=%s*"[^"]*"%s*),', "%1")
			secSrc = string.gsub(secSrc, "(Secrets%.[%w_]+%s*=%s*'[^']*'%s*),", "%1")
			local ok
			if payload.secrets.donationApiSecret ~= nil then
				secSrc, ok = patchAssignment(secSrc, "DonationApiSecret", quoteString(payload.secrets.donationApiSecret))
				if ok then
					note("Secrets.DonationApiSecret")
				end
			end
			if payload.secrets.gameDataApiSecret ~= nil then
				secSrc, ok = patchAssignment(secSrc, "GameDataApiSecret", quoteString(payload.secrets.gameDataApiSecret))
				if ok then
					note("Secrets.GameDataApiSecret")
				end
			end
			local sok, serr = pcall(function()
				secretsMod.Source = secSrc
			end)
			if not sok then
				return { ok = false, patched = patched, message = "Failed writing Secrets: " .. tostring(serr) }
			end
		else
			table.insert(patched, "(Secrets module missing — skipped)")
		end
	end

	return {
		ok = true,
		patched = patched,
		message = ("Patched %d keys"):format(#patched),
	}
end

function ConfigEditCore.findBuyerConfig()
	return findBuyerConfig()
end

function ConfigEditCore.findSecrets()
	return findSecrets()
end

return ConfigEditCore
