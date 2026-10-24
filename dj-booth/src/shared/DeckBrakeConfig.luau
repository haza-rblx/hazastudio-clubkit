--!strict
-- Deck brake presets: how a turntable slows down when a deck is turned off. Read by the server
-- (does the timing) and the clients (do the slowdown on their own copy of the deck's Sound).
local DeckBrakeConfig = {}

export type BrakePreset = {
	duration: number, -- seconds the brake takes
	shape: number, -- curve exponent: 1 = linear, above 1 = holds speed longer then drops
	damp: number, -- 0-100, how much the treble and mids roll off
	wow: number, -- 0-100, pitch wobble
	dust: number, -- 0-100, vinyl crackle loop
	hum: number, -- 0-100, motor hum loop
	click: number, -- 0-100, power switch click
	needle: number, -- 0-100, needle drop at the end
	thump: number, -- 0-100, thump at the end
}

-- which preset deck-off uses; "" or a missing name turns the brake off (instant stop)
DeckBrakeConfig.Preset = "CabutListrik"

DeckBrakeConfig.Presets = {
	CabutListrik = {
		duration = 2.8,
		shape = 2.2,
		damp = 60,
		wow = 30,
		dust = 25,
		hum = 40,
		click = 70,
		needle = 40,
		thump = 70,
	},
	Realistis = {
		duration = 0.7,
		shape = 1.0,
		damp = 50,
		wow = 10,
		dust = 20,
		hum = 20,
		click = 0,
		needle = 50,
		thump = 40,
	},
	RemCepat = {
		duration = 0.35,
		shape = 1.0,
		damp = 40,
		wow = 0,
		dust = 15,
		hum = 10,
		click = 0,
		needle = 30,
		thump = 30,
	},
	CDJVinylBrake = {
		duration = 0.45,
		shape = 0.8,
		damp = 30,
		wow = 0,
		dust = 0,
		hum = 0,
		click = 0,
		needle = 0,
		thump = 0,
	},
	Bersih = { duration = 0.7, shape = 1.0, damp = 40, wow = 5, dust = 0, hum = 0, click = 0, needle = 0, thump = 25 },
	RetroKasar = {
		duration = 1.4,
		shape = 1.3,
		damp = 30,
		wow = 40,
		dust = 80,
		hum = 30,
		click = 40,
		needle = 80,
		thump = 50,
	},
} :: { [string]: BrakePreset }

-- asset ids for the optional layers; 0 = skip that layer
DeckBrakeConfig.Assets = {
	PowerClick = 95205227156821,
	HumLoop = 90287059764665,
	DustLoop = 114336978027821,
	EndNeedle = 84223860631330,
	EndThump = 132323068924327,
}

return DeckBrakeConfig
