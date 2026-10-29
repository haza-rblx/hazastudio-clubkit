--!strict
-- The eight pads. SFX pads play a one-shot for the room (everywhere, or from the DJ deck for "near
-- the DJ deck"); world pads run camera effects on every client and low gravity on the server.
-- Cooldowns are deck-wide and enforced here; the ready time syncs so the pads count down.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.HazaDJ.Shared
local Dict = require(Shared.Dict)
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.State)

local Pads = {}

-- the Settings "Pad cooldown" scales each pad's own cooldown: none / short / long
local COOLDOWN_SCALE = { 1, 1.5, 2 }
local gravityToken = 0
local baseGravity = workspace.Gravity

-- each client plays its own one-shot (the server makes no Sound)
local function oneShot(assetId: number, volume: number, nearDjDeck: boolean)
	Net.PadSfx.FireAll(assetId, math.clamp(volume, 0, 1) * 2, nearDjDeck)
end

function Pads.press(i: number): (boolean, string?)
	local lib = State.library()
	local pad = lib.pads[i]
	if not pad or not pad.kind then
		return false, "This pad is empty."
	end
	local s = State.session()
	local now = State.now()
	if now < (s.padReady[i] or 0) then
		return false, nil -- still cooling down; the pad shows it
	end
	local settings = State.settings()
	local cooldown = pad.cooldown * (COOLDOWN_SCALE[settings.padCooldown] or 1)
	State.update(State.session, function(cur)
		return Dict.merge(cur, { padReady = Dict.set(cur.padReady, i, now + cooldown) })
	end)
	if pad.kind == "sfx" then
		local snd
		for _, x in lib.sounds do
			if x.id == pad.sound then
				snd = x
			end
		end
		if not snd then
			return false, "This pad has no sound."
		end
		oneShot(snd.assetId, (pad.volume or 80) / 100, pad.reach == 2)
		return true
	end
	local effect = pad.effect or 1
	local intensity = pad.intensity or 50
	local duration = pad.duration or 3
	if effect == 4 then
		-- low gravity for everyone: intensity 100 % = a fifth of normal gravity
		gravityToken += 1
		local token = gravityToken
		workspace.Gravity = baseGravity * (1 - 0.8 * intensity / 100)
		task.delay(duration, function()
			if gravityToken == token then
				workspace.Gravity = baseGravity
			end
		end)
		return true
	end
	if not settings.camFx then
		return true
	end
	local scaled = math.floor(intensity * settings.camFxAmount / 100 + 0.5)
	Net.WorldFx.FireAll(effect, scaled, duration)
	return true
end

return Pads
