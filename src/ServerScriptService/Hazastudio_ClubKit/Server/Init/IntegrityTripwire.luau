--!strict
-- Self-integrity tripwire (ADR 0006 Pillar 6).
--
-- Runs INDEPENDENTLY of LicenseService, on purpose: the most common strip is to
-- flip `KitProduct.LicenseEnforcementEnabled = false`, which makes LicenseService
-- take its disabled path and never verify or beacon. This tripwire is a separate
-- code site with its own HTTP post, so disabling enforcement does not also
-- disable the signal. Best-effort; never blocks or errors boot.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local IntegrityTripwire = {}

local _fired = false

local function beacon(apiUrl: string, secret: string, reason: string, kitProduct: any)
	local url = apiUrl:gsub("/+$", "") .. "/v2/beacon"
	local creatorType = if game.CreatorType == Enum.CreatorType.Group then "Group" else "User"
	task.spawn(function()
		pcall(function()
			HttpService:RequestAsync({
				Url = url,
				Method = "POST",
				Headers = {
					Authorization = "Bearer " .. secret,
					["Content-Type"] = "application/json",
				},
				Body = HttpService:JSONEncode({
					reason = reason,
					universe_id = game.GameId,
					place_id = game.PlaceId,
					creator_id = game.CreatorId,
					creator_type = creatorType,
					job_id = game.JobId,
					kit_version = tostring((kitProduct or {}).KitVersion or ""),
					build_id = tostring((kitProduct or {}).BuildId or ""),
					player_count = #Players:GetPlayers(),
				}),
				Timeout = 10,
			})
		end)
	end)
end

-- Call once at boot, unconditionally, BEFORE the LicenseService enforcement gate.
-- `apiUrl`/`secret` are the buyer's donation API config (the only endpoint the
-- kit is configured to reach).
function IntegrityTripwire.check(config: { kitProduct: any, apiUrl: string?, secret: string? })
	if _fired then
		return
	end
	_fired = true

	-- Studio is the developer's own machine; never trip there.
	if RunService:IsStudio() then
		return
	end

	local apiUrl = config.apiUrl or ""
	local secret = config.secret or ""
	-- An unconfigured place (no license endpoint) has nothing to protect and no
	-- way to report — leave it alone.
	if apiUrl == "" or secret == "" then
		return
	end

	local kitProduct = config.kitProduct
	-- Enforcement EXPLICITLY turned off on a configured, licensed place is the
	-- tell-tale of a strip. (An older kit build omits the flag entirely -> nil,
	-- which is not a strip, so we check for `== false` specifically.)
	if (kitProduct :: any).LicenseEnforcementEnabled == false then
		beacon(apiUrl, secret, "enforcement_disabled", kitProduct)
	end
end

return IntegrityTripwire
