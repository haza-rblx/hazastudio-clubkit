--!strict
-- What a fresh DJ deck starts with. The library is empty; the pads and their sounds are the kit's
-- defaults (Roblox-licensed SFX, so they play in any experience).
local Types = require(script.Parent.Types)
local DeckBrakeConfig = require(script.Parent.DeckBrakeConfig)

local Defaults = {}

Defaults.EFFECTS = { "Camera shake", "Camera rotate", "Darken camera", "Low gravity" }

function Defaults.sounds(): { Types.Sound }
	return {
		{ id = "s1", assetId = 9113071895, name = "Air Horn", len = 3.9 },
		{ id = "s2", assetId = 1846552189, name = "DJ Scratch", len = 3.0 },
		{ id = "s3", assetId = 162670113, name = "Spaceship", len = 5.0 },
		{ id = "s4", assetId = 9112766176, name = "Crowd Cheer", len = 41.5 },
	}
end

function Defaults.pads(): { Types.Pad }
	return {
		{ label = "Air Horn", kind = "sfx", sound = "s1", cooldown = 3, volume = 80, reach = 1 },
		{ label = "Scratch", kind = "sfx", sound = "s2", cooldown = 3, volume = 80, reach = 1 },
		{ label = "Camera Shake", kind = "world", effect = 1, cooldown = 8, intensity = 60, duration = 2 },
		{ label = "Camera Rotate", kind = "world", effect = 2, cooldown = 8, intensity = 40, duration = 3 },
		{ label = "Crowd Cheer", kind = "sfx", sound = "s4", cooldown = 5, volume = 70, reach = 1 },
		{ label = "Spaceship", kind = "sfx", sound = "s3", cooldown = 3, volume = 80, reach = 2 },
		{ label = "Darken Camera", kind = "world", effect = 3, cooldown = 8, intensity = 70, duration = 4 },
		{ label = "Low Gravity", kind = "world", effect = 4, cooldown = 15, intensity = 50, duration = 6 },
	}
end

function Defaults.library(): Types.Library
	return { tracks = {}, playlists = {}, sounds = Defaults.sounds(), pads = Defaults.pads(), nextAdded = 1 }
end

function Defaults.settings(): Types.Settings
	return {
		volume = 100,
		normalize = true,
		limiter = true,
		fadeOut = 3,
		crossfade = 4,
		pitch = 2,
		keyLock = true,
		syncOnLoad = false,
		autoCue = true,
		busyDeck = 1,
		padCooldown = 1,
		deckOff = DeckBrakeConfig.Preset,
		speakers = 2,
		openAtDjDeck = true,
		standLock = true,
		maxSet = 1,
		idle = 3,
		announce = true,
		nowPlaying = true,
		billboard = true,
		lights = true,
		camFx = true,
		camFxAmount = 50,
	}
end

-- the keys each Settings section owns (Reset to defaults)
Defaults.SECTION_KEYS = {
	sound = { "volume", "normalize", "limiter", "fadeOut", "crossfade" },
	decks = { "pitch", "keyLock", "syncOnLoad", "autoCue", "busyDeck", "padCooldown", "deckOff" },
	djDeck = { "speakers", "openAtDjDeck", "standLock", "maxSet", "idle" },
	show = { "announce", "nowPlaying", "billboard", "lights", "camFx", "camFxAmount" },
	panel = { "panelSize", "hotkey", "reduceMotion" },
}

function Defaults.prefs(): Types.Prefs
	return { panelSize = 2, reduceMotion = false, hotkey = 1, view = "window" }
end

function Defaults.access(): Types.Access
	return {
		people = {},
		gates = { group = { on = false, id = "", rank = "" }, pass = { on = false, id = "" }, takeOver = 2 },
	}
end

function Defaults.deck(): Types.Deck
	return {
		trackId = nil,
		playing = false,
		pos = 0,
		at = 0,
		cue = 0,
		pitch = 0,
		synced = false,
		eq = { 0.5, 0.5, 0.5 },
		filter = 0.5,
		vol = 0.8,
		fx = { 0, 0, 0 },
		lastCue = nil,
		brake = nil,
	}
end

function Defaults.session(): Types.Session
	return {
		live = nil,
		liveSince = nil,
		online = {},
		decks = { Defaults.deck(), Defaults.deck() },
		xfader = 0.5,
		curve = 0,
		master = 0.8,
		queue = {},
		automix = true,
		padReady = { 0, 0, 0, 0, 0, 0, 0, 0 },
		fade = nil, -- set while the room fades out (Decks.fadeOutAll)
	}
end

function Defaults.stage(): Types.Stage
	return { tracks = {} }
end

return Defaults
