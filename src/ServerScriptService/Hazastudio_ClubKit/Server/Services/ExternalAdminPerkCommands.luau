--!strict
--[[
	External-admin member perk commands wired into the kit's own command
	surface (Command Library `/...` + chat). Registered via
	commandExecutionService:registerRawHandler from Main.server after the
	ExternalAdminFacade singleton is initialised — the library entries and
	this handler share one gate (facade.checkPerk), so the Kohl's chat
	commands (`;fly`/`;smite`) and the kit's `/fly`/`/smite` always agree.

	- /fly, /unfly — self-target. Staff (Perks.StaffBypass) and gated tiers
	  both land here; flight itself rides Kohl's own `_KFly` attribute, which
	  its client already renders. No Kohl's client → the attribute is inert
	  (the perk stays a bridge-only feature by design).
	- /smite <player> — any target for gated members; one quota unit per use
	  (DataStore `PerkQuota_v1`, ISO-week). The strike effect is kit-side and
	  self-contained (neon pillar + delayed kill), mirroring Kohl's native
	  smite look without touching its runtime.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

type Result<T> = Types.Result<T>

local FLY_DEFAULT_SPEED = 128
local SMITE_STRIKE_DELAY = 2.2
local SMITE_SOUNDS = { 9116282544, 9116282647, 9116282646, 9116282791, 9116282875 }

local function createExternalAdminPerkCommands(deps: {
	facade: any,
	playerLookupService: any,
	notify: any,
})
	local facade = deps.facade
	local playerLookupService = deps.playerLookupService
	local notify = deps.notify
	local log = Logger.new("ExternalAdminPerkCommands")

	local function perkGate(player: Player, perk: string): (boolean, any?)
		local gateResult = facade.checkPerk(player.UserId, perk)
		if not (gateResult.ok and type(gateResult.value) == "table") then
			return false, nil
		end
		local gate = gateResult.value
		if not gate.allowed then
			return false, gate
		end
		return true, gate
	end

	local function denyNoPerk(player: Player, perk: string)
		notify.player(player, `[Perk] The {string.lower(perk)} perk needs a higher membership tier.`, "WARNING")
	end

	local function executeFly(player: Player, _rawText: string)
		local pass, gate = perkGate(player, "Fly")
		if not pass then
			denyNoPerk(player, "Fly")
			return
		end
		-- Staff bypass and members land the same way: Kohl's client renders the flight.
		player:SetAttribute("_KFly", FLY_DEFAULT_SPEED :: any)
		player:SetAttribute("_KFlyConstant", nil :: any)
		player:SetAttribute("_KNoClip", nil :: any)
		notify.player(player, "[Perk] Flight enabled — /unfly to land.", "SUCCESS")
		log:info("Perk fly on", { player = player.Name, reason = gate and gate.reason })
	end

	local function executeUnfly(player: Player, _rawText: string)
		-- Ungating the landing side on purpose: a member whose tier lapsed mid-flight
		-- must always be able to come down.
		player:SetAttribute("_KFly", nil)
		player:SetAttribute("_KFlyConstant", nil)
		player:SetAttribute("_KNoClip", nil)
		notify.player(player, "[Perk] Flight disabled.", "SUCCESS")
	end

	local function resolveTargetOrNotify(player: Player, query: string): Player?
		local resolveResult = playerLookupService:resolveDetailed(query)
		if not resolveResult.ok then
			notify.player(player, resolveResult.error, "ERROR")
			return nil
		end
		local payload = resolveResult.value
		if payload.kind == "found" then
			return payload.player
		end
		if payload.kind == "too_short" then
			notify.player(player, "[Perk] Give me at least 3 letters, or use the full name.", "WARNING")
			return nil
		end
		if payload.kind == "ambiguous" then
			notify.player(
				player,
				"[Perk] That matches a few people. Be more specific: "
					.. playerLookupService:describePlayers(payload.matches or {}),
				"WARNING"
			)
			return nil
		end
		notify.player(player, ("[Perk] I could not find '%s' in this server."):format(query), "ERROR")
		return nil
	end

	local function strikeTarget(target: Player)
		local character = target.Character
		if not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not (humanoid and root) then
			return
		end

		local hipHeight = if humanoid.RigType == Enum.HumanoidRigType.R15
			then humanoid.HipHeight + root.Size.Y / 2
			else root.Size.Y * 1.5

		task.delay(SMITE_STRIKE_DELAY, function()
			if not target.Parent or not character.Parent then
				return
			end
			local part = Instance.new("Part")
			part.Transparency = 0.9
			part.Material = Enum.Material.Neon
			part.Color = Color3.new(1, 1, 1)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Size = Vector3.one
			part.CFrame = CFrame.new(character:GetPivot().Position - Vector3.new(0, hipHeight, 0))
			local mesh = Instance.new("BlockMesh")
			mesh.Scale = Vector3.new(2, 1e4, 2)
			mesh.Offset = Vector3.new(0, 5e3, 0)
			mesh.Parent = part
			for i = 1, 4 do
				local outer = part:Clone()
				outer:ClearAllChildren()
				local outerMesh = Instance.new("BlockMesh")
				outerMesh.Scale = Vector3.new(2 + i, 1e4, 2 + i)
				outerMesh.Offset = Vector3.new(0, 5e3, 0)
				outerMesh.Parent = outer
				outer.Parent = part
			end
			part.Parent = workspace

			humanoid.MaxHealth = math.max(1, humanoid.MaxHealth)
			humanoid.Health = 0
			task.delay(0.4, part.Destroy, part)
		end)

		local sound = Instance.new("Sound")
		sound.SoundId = `rbxassetid://{SMITE_SOUNDS[math.random(#SMITE_SOUNDS - 1)]}`
		sound.PlayOnRemove = true
		sound.Volume = 1
		sound.Parent = workspace
		sound:Destroy()
	end

	local function executeSmite(player: Player, rawText: string)
		local query = rawText:match("^%S+%s+(.+)$")
		local targetQuery = if query then (query:match("^%s*(.-)%s*$") :: string) else ""
		if targetQuery == "" then
			notify.player(player, "[Perk] Try /smite <player>.", "WARNING")
			return
		end
		local pass, gate = perkGate(player, "Smite")
		if not pass then
			denyNoPerk(player, "Smite")
			return
		end
		local target = resolveTargetOrNotify(player, targetQuery)
		if not target then
			return
		end
		-- One quota unit per use for capped tiers; staff bypass skips the store.
		local quota = gate and gate.quota
		if type(quota) == "number" then
			local consume = facade.consumePerkQuota(player.UserId, "Smite", quota)
			if not (consume.ok and type(consume.value) == "number") then
				if consume.error == "perk_quota_exhausted" then
					notify.player(
						player,
						(`[Perk] Weekly smite quota used up ({quota}/{quota}). Resets Monday 00:00 UTC.`),
						"WARNING"
					)
				else
					notify.player(player, "[Perk] Could not check your smite quota - try again in a moment.", "ERROR")
				end
				return
			end
			local remaining = consume.value :: number
			if remaining > 0 then
				notify.player(player, (`[Perk] Smite used - {remaining} free smite(s) left this week.`), "SUCCESS")
			else
				notify.player(player, "[Perk] Smite used - that was your last free smite this week!", "WARNING")
			end
		end
		strikeTarget(target)
		log:info("Perk smite", { player = player.Name, target = target.Name, reason = gate and gate.reason })
	end

	local service = {}

	--- Bind /fly, /unfly and /smite onto the shared command pipeline.
	function service.register(commandExecutionService: any)
		commandExecutionService:registerRawHandler("fly", executeFly)
		commandExecutionService:registerRawHandler("unfly", executeUnfly)
		commandExecutionService:registerRawHandler("smite", executeSmite)
	end

	return service
end

return createExternalAdminPerkCommands
