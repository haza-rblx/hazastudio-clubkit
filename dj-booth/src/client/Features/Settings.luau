--!strict
-- The Settings tab (311 | 937): sections on the left, the section's cards on the right. Edits go
-- into a draft; a Save / Discard bar shows while the draft differs (owner, 2026-10-22). "This
-- panel" is the player's own prefs (ProfileStore); the rest is the booth's (owner only).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Shared = ReplicatedStorage.HazaDJ.Shared
local Defaults = require(Shared.Defaults)
local DeckBrakeConfig = require(Shared.DeckBrakeConfig)
local Format = require(Shared.Format)
local LicensePolicy = require(Shared.LicensePolicy)
local Mix = require(Shared.Mix)
local Actions = require(script.Parent.Parent.Actions)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.UI.Base)
local Controls = require(script.Parent.Parent.UI.Controls)
local Layout = require(script.Parent.Parent.UI.Layout)
local Debug = require(script.Parent.Parent.Debug)

local source, untrack = Vide.source, Vide.untrack
local C = Theme.C
local frame, label = Base.frame, Base.label

local Settings = {}

local PAGE_H, PAGE_PAD, PAGE_HEAD = Theme.PAGE_H, Theme.PAGE_PAD, Theme.PAGE_HEAD

local PREF_KEYS = { panelSize = true, reduceMotion = true, hotkey = true }

local SECTIONS = {
	{ key = "sound", title = "Sound" },
	{ key = "decks", title = "Decks" },
	{ key = "booth", title = "Booth" },
	{ key = "show", title = "Show" },
	{ key = "panel", title = "This panel" },
	{ key = "license", title = "License" }, -- the owner only (ADR 0022)
}

-- deck-off brake: "" = instant stop, then the presets in a fixed order, the rest sorted after
local DECK_OFF_ORDER = { "CabutListrik", "Realistis", "RemCepat", "CDJVinylBrake", "Bersih", "RetroKasar" }
local DECK_OFF_LABELS = {
	CabutListrik = "Cabut listrik",
	Realistis = "Realistis",
	RemCepat = "Rem cepat",
	CDJVinylBrake = "CDJ vinyl brake",
	Bersih = "Bersih",
	RetroKasar = "Retro kasar",
}
local deckOffNames: { string } = { "" }
local deckOffLabels: { string } = { "Instant" }
do
	local seen = {}
	for _, n in DECK_OFF_ORDER do
		if DeckBrakeConfig.Presets[n] then
			table.insert(deckOffNames, n)
			seen[n] = true
		end
	end
	local rest = {}
	for n in DeckBrakeConfig.Presets do
		if not seen[n] then
			table.insert(rest, n)
		end
	end
	table.sort(rest)
	for _, n in rest do
		table.insert(deckOffNames, n)
	end
	for i = 2, #deckOffNames do
		local n = deckOffNames[i]
		table.insert(deckOffLabels, DECK_OFF_LABELS[n] or n)
	end
end
local function deckOffIndex(name: string): number
	for i, n in deckOffNames do
		if n == name then
			return i
		end
	end
	return 1
end

-- the saved values: booth settings + this player's prefs, flattened
local function saved(): { [string]: any }
	local v = table.clone(Store.settings()) :: any
	local prefs = Store.me().prefs
	v.panelSize, v.reduceMotion, v.hotkey = prefs.panelSize, prefs.reduceMotion, prefs.hotkey
	return v
end

function Settings.new(props: Base.Props?): Frame
	local current = source("sound")
	local draft = source(untrack(saved))
	-- when the saved values change underneath (another owner, or our own save), the draft follows
	-- for every key the player hasn't touched
	local base = untrack(saved)
	Vide.effect(function()
		local s = saved()
		local d = table.clone(untrack(draft))
		for k, v in s do
			if d[k] == base[k] then
				d[k] = v
			end
		end
		base = s
		draft(d)
	end)
	local changes = function(): number
		local s, d = saved(), draft()
		local n = 0
		for k, v in d do
			if s[k] ~= v then
				n += 1
			end
		end
		return n
	end
	local dirty = function()
		return changes() > 0
	end
	local function set(k: string)
		return function(v: any)
			local d = table.clone(untrack(draft))
			d[k] = v
			draft(d)
		end
	end
	local val = function(k: string)
		return untrack(draft)[k]
	end
	Debug.on("settings", function(cmd: string, a: any, b: any)
		if cmd == "section" then
			current(a)
		elseif cmd == "set" then
			set(a)(b)
		end
		return "ok"
	end)

	-- ── left ──
	local meta = {
		sound = function()
			return draft().volume .. "%"
		end,
		decks = function()
			return Mix.PITCH_LABELS[draft().pitch] or ""
		end,
		license = function()
			local v = Store.license()
			if v.status == "active" then
				return "Active"
			elseif v.status == "guest" then
				local days = math.floor((v.secondsLeft or 0) / 86400)
				return if days >= 1 then `{days} day{if days == 1 then "" else "s"} left` else "Ends today"
			end
			return "Locked"
		end,
	}
	local isOwner = function()
		return Store.me().role == "Owner"
	end
	local navKids = {}
	do
		local nx = Layout.counter()
		for _, grp in
			{ { "Room", { "sound", "show" } }, { "Booth", { "decks", "booth", "license" } }, { "You", { "panel" } } }
		do
			table.insert(navKids, Layout.sideCaption(nx(), grp[1]))
			for _, key in grp[2] do
				local sec
				for _, x in SECTIONS do
					if x.key == key then
						sec = x
					end
				end
				local navRow = Layout.sideRow(
					nx(),
					function()
						return current() == key
					end,
					sec.title,
					meta[key],
					nil,
					function()
						current(key)
						Controls.closeMenu()
					end
				)
				if key == "license" then
					Vide.effect(function()
						navRow.Visible = isOwner()
					end)
				end
				table.insert(navKids, navRow)
			end
		end
	end
	local navTile = Base.tile(0, 0, 311, PAGE_H, {
		Base.scroll({
			Size = UDim2.fromScale(1, 1),
			ScrollingDirection = Enum.ScrollingDirection.XY,
			Base.pad(0, 0, 12, 12),
			Base.vlist(0),
			navKids,
		}),
	})

	-- ── right: the section ──
	local BUILD = {}
	local function toggle(k: string)
		return Controls.toggle(val(k), set(k))
	end
	local function seg(k: string, options: { string })
		return Controls.segmented(options, val(k), set(k), 240)
	end
	local function drop(k: string, options: { string })
		return Controls.dropdown(options, val(k), set(k), 200)
	end
	BUILD.sound = function(nx)
		local out = {}
		for _, x in
			Layout.group(nx, "Level", {
				-- up to 800 %, a plain stepper (owner, 2026-10-23)
				Layout.settingRow(
					nx(),
					"Volume limit",
					"Loudest the decks can go, up to 800%",
					Controls.stepper(val("volume"), 0, 800, 25, Format.pct, set("volume"))
				),
				Layout.settingRow(
					nx(),
					"Even out loudness",
					"Quiet and loud tracks play at the same level",
					toggle("normalize")
				),
				Layout.settingRow(nx(), "Master limiter", "Catch peaks before they clip", toggle("limiter"), true),
			}, true)
		do
			table.insert(out, x)
		end
		for _, x in
			Layout.group(nx, "Transitions", {
				Layout.settingRow(
					nx(),
					"Fade out on stop",
					"Ease the room out when a set ends",
					Controls.stepper(val("fadeOut"), 0, 10, 1, Format.offSeconds, set("fadeOut"))
				),
				Layout.settingRow(
					nx(),
					"Auto crossfade",
					"Blend into the next track when one runs out",
					Controls.stepper(val("crossfade"), 0, 12, 1, Format.offSeconds, set("crossfade")),
					true
				),
			})
		do
			table.insert(out, x)
		end
		return out
	end
	BUILD.decks = function(nx)
		local out = {}
		for _, x in
			Layout.group(nx, "Tempo", {
				Layout.settingRow(
					nx(),
					"Pitch range",
					"How far the speed faders reach",
					seg("pitch", Mix.PITCH_LABELS)
				),
				Layout.settingRow(nx(), "Key lock", "Change speed without changing pitch", toggle("keyLock")),
				Layout.settingRow(
					nx(),
					"Sync on load",
					"A loaded track matches the other deck's BPM",
					toggle("syncOnLoad"),
					true
				),
			}, true)
		do
			table.insert(out, x)
		end
		for _, x in
			Layout.group(nx, "Loading", {
				Layout.settingRow(nx(), "Skip silence", "Start at the first sound, not at 0:00", toggle("autoCue")),
				Layout.settingRow(
					nx(),
					"Loading onto a playing deck",
					"When a DJ drops a track on the live deck",
					seg("busyDeck", { "Ask", "Block", "Allow" })
				),
				Layout.settingRow(
					nx(),
					"Deck off",
					"How a deck stops when you pause, cue or eject",
					Controls.dropdown(deckOffLabels, function()
						return deckOffIndex(draft().deckOff)
					end, function(i: number)
						set("deckOff")(deckOffNames[i])
					end, 200),
					true
				),
			})
		do
			table.insert(out, x)
		end
		for _, x in
			Layout.group(nx, "Pads", {
				Layout.settingRow(
					nx(),
					"Pad cooldown",
					"Wait between presses of the same pad",
					seg("padCooldown", { "None", "Short", "Long" }),
					true
				),
			})
		do
			table.insert(out, x)
		end
		return out
	end
	BUILD.booth = function(nx)
		local out = {}
		for _, x in
			Layout.group(nx, "At the booth", {
				Layout.settingRow(
					nx(),
					"Open at the booth",
					"Open this panel when a DJ steps up",
					toggle("openAtBooth")
				),
				Layout.settingRow(
					nx(),
					"DJs only behind the decks",
					"Keep everyone else off the booth floor",
					toggle("standLock"),
					true
				),
			})
		do
			table.insert(out, x)
		end
		for _, x in
			Layout.group(nx, "Sets", {
				Layout.settingRow(
					nx(),
					"Longest set",
					"Hand the booth on after this long",
					drop("maxSet", { "No limit", "30 minutes", "1 hour", "2 hours" })
				),
				Layout.settingRow(
					nx(),
					"Free an idle booth",
					"Hand over after no input for…",
					drop("idle", { "Never", "5 minutes", "10 minutes", "15 minutes" }),
					true
				),
			})
		do
			table.insert(out, x)
		end
		return out
	end
	BUILD.show = function(nx)
		local out = {}
		for _, x in
			Layout.group(nx, "On screen", {
				Layout.settingRow(
					nx(),
					"Announce the live DJ",
					"Show “… is live” to everyone",
					toggle("announce")
				),
				Layout.settingRow(nx(), "Now playing", "Show the track title to the room", toggle("nowPlaying")),
				Layout.settingRow(
					nx(),
					"Name above the booth",
					"The live DJ's name floats over the decks",
					toggle("billboard"),
					true
				),
			}, true)
		do
			table.insert(out, x)
		end
		for _, x in
			Layout.group(nx, "In the room", {
				Layout.settingRow(
					nx(),
					"Lights follow the beat",
					"Club lights pulse on the playing deck's BPM",
					toggle("lights")
				),
				Layout.settingRow(nx(), "Camera effects", "Pads may shake or tilt listeners' cameras", toggle("camFx")),
				Layout.settingRow(
					nx(),
					"Effect strength",
					"How hard those camera effects hit",
					Controls.dots(220, {
						min = 0,
						max = 100,
						step = 10,
						value = val("camFxAmount"),
						default = 50,
						fmt = Format.pct,
						onChange = set("camFxAmount"),
					}),
					true
				),
			})
		do
			table.insert(out, x)
		end
		return out
	end
	BUILD.panel = function(nx)
		local out = {}
		for _, x in
			Layout.group(nx, "Look", {
				Layout.settingRow(
					nx(),
					"Panel size",
					"Scale of this panel on your screen",
					seg("panelSize", { "Small", "Normal", "Large" })
				),
				Layout.settingRow(nx(), "Reduce motion", "Fewer animations in the panel", toggle("reduceMotion"), true),
			}, true)
		do
			table.insert(out, x)
		end
		for _, x in
			Layout.group(nx, "Keys", {
				Layout.settingRow(
					nx(),
					"Open the panel",
					"Key that shows or hides it",
					drop("hotkey", { "J", "K", "B", "None" }),
					true
				),
			})
		do
			table.insert(out, x)
		end
		return out
	end

	-- the licence as the owner sees it (ADR 0022): status, time left, venue, owner; and, while on a
	-- guest pass, a field to switch to a full licence
	local venue = source("This venue")
	task.spawn(function()
		local okInfo, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
		if okInfo and type(info) == "table" and info.Name then
			venue(info.Name)
		end
	end)
	local function text(t: any, props: Base.Props?): TextLabel
		return label(
			t,
			Base.with({ TextSize = 13, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5) }, props)
		)
	end
	BUILD.license = function(nx)
		local lic = Store.license
		local isGuest = function()
			return lic().status == "guest"
		end
		local out = {}
		local pill = Base.new("Frame", {
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.field,
			Base.round(1),
			Base.pad(10, 12, 0, 0),
			Base.hlist(8),
			Base.new("Frame", {
				Size = UDim2.fromOffset(6, 6),
				LayoutOrder = 1,
				BackgroundColor3 = function()
					local s = lic().status
					return if s == "active" then C.ok elseif s == "guest" then Theme.W else C.red
				end,
				Base.round(1),
			}),
			label(function()
				local s = lic().status
				return if s == "active" then "Active" elseif s == "guest" then "Guest pass" else "Locked"
			end, { TextSize = 13, LayoutOrder = 2 }),
		})
		local timeLeft = frame({
			Size = UDim2.fromOffset(180, 30),
			text(function()
				local v = lic()
				return if v.status == "guest" then LicensePolicy.leftText(v.secondsLeft or 0) else "No end date"
			end, {
				AnchorPoint = Vector2.new(1, 0),
				Size = UDim2.new(1, 0, 0, 16),
				AutomaticSize = Enum.AutomaticSize.None,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = function()
					return if isGuest() then UDim2.fromScale(1, 0) else UDim2.new(1, 0, 0.5, -8)
				end,
			}),
			Base.new("Frame", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				Size = UDim2.fromOffset(180, 4),
				BackgroundColor3 = C.field,
				Visible = isGuest,
				Base.round(1),
				Base.new("Frame", {
					BackgroundColor3 = Theme.W,
					Size = function()
						local v = lic()
						local span = (v.expiresAt or 0) - (v.startedAt or 0)
						local f = if span > 0 then math.clamp((v.secondsLeft or 0) / span, 0, 1) else 1
						return UDim2.fromScale(f, 1)
					end,
					Base.round(1),
				}),
			}),
		})
		for _, x in
			Layout.group(nx, "Status", {
				Layout.settingRow(nx(), "License", "What this venue is running on", pill),
				Layout.settingRow(
					nx(),
					"Time left",
					(
							function()
								local v = lic()
								if v.status == "guest" and v.expiresAt then
									return `Ends {os.date("%d %b %Y, %H:%M", v.expiresAt)} · then the booth locks`
								end
								return "A full license does not expire"
							end
						) :: any,
					timeLeft
				),
				Layout.settingRow(nx(), "Venue", "Universe " .. tostring(game.GameId), text(venue)),
				Layout.settingRow(
					nx(),
					"Owner",
					"Only the owner can change the license",
					text("@" .. Players.LocalPlayer.Name),
					true
				),
			}, true)
		do
			table.insert(out, x)
		end
		local code = ""
		local upgrade = Layout.group(nx, "Upgrade", {
			Layout.settingRow(
				nx(),
				"Activation code",
				"Turns the guest pass into a full license",
				frame({
					Size = UDim2.fromOffset(336, 32),
					Controls.input({
						placeholder = "Activation code",
						w = 244,
						onText = function(t: string)
							code = t
						end,
					}),
					Controls.button({
						text = "Activate",
						kind = "primary",
						w = 84,
						h = 32,
						onClick = function()
							if (string.gsub(code, "%s", "")) ~= "" then
								Actions.send({ Kind = "Activate", Code = code })
							end
						end,
					}, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0) }),
				}),
				true
			),
		})
		for _, x in upgrade do
			Vide.effect(function()
				x.Visible = isGuest()
			end)
			table.insert(out, x)
		end
		return out
	end

	local function save()
		local d = untrack(draft)
		local s = untrack(saved)
		local boothChanged, prefsChanged = false, false
		for k, v in d do
			if s[k] ~= v then
				if PREF_KEYS[k] then
					prefsChanged = true
				else
					boothChanged = true
				end
			end
		end
		task.spawn(function()
			if prefsChanged then
				Actions.run({
					Kind = "PrefsSet",
					PanelSize = d.panelSize,
					ReduceMotion = d.reduceMotion,
					Hotkey = d.hotkey,
				})
			end
			if boothChanged then
				local values = {}
				for k in Defaults.settings() :: any do
					values[k] = d[k]
				end
				local r = Actions.run({ Kind = "SettingsSave", Values = values :: any })
				if not r.Ok then
					-- refused (not the owner): drop the booth edits so the bar doesn't linger
					local back = table.clone(untrack(draft))
					for k in Defaults.settings() :: any do
						back[k] = untrack(saved)[k]
					end
					draft(back)
				end
			end
		end)
	end

	local bar = Base.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = C.raised,
		ZIndex = 5,
		Visible = dirty,
		Base.rule(false),
		Base.pad(PAGE_PAD, PAGE_PAD, 0, 0),
		label(function()
			local n = changes()
			return if n == 1 then "1 unsaved change" else n .. " unsaved changes"
		end, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), TextSize = 13, ZIndex = 5 }),
		frame({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 32),
			ZIndex = 5,
			Base.hlist(8, Enum.HorizontalAlignment.Right),
			Controls.button({
				text = "Discard",
				kind = "secondary",
				h = 32,
				onClick = function()
					draft(untrack(saved))
					current(untrack(current)) -- re-render the section with the saved values
				end,
			}, { LayoutOrder = 1, ZIndex = 5 }),
			Controls.button(
				{ text = "Save changes", kind = "primary", h = 32, onClick = save },
				{ LayoutOrder = 2, ZIndex = 5 }
			),
		}),
	})

	-- the section rebuilds on a section switch, a discard or a reset (not on each edit)
	local epoch = source(0)
	local main = frame({
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		Base.rebuild(function()
			return current() .. "|" .. epoch()
		end, function(key: string)
			local sec = string.split(key, "|")[1]
			local title = ""
			for _, x in SECTIONS do
				if x.key == sec then
					title = x.title
				end
			end
			return {
				Layout.pageHead(
					title,
					-- the licence has nothing to reset
					if sec == "license"
						then nil
						else Controls.button({
							text = "Reset to defaults",
							kind = "ghost",
							h = 32,
							onClick = function()
								-- Reset fills the draft with the defaults; nothing changes until Save
								local d = table.clone(untrack(draft))
								local defaults = Defaults.settings() :: any
								local prefs = Defaults.prefs() :: any
								for _, k in Defaults.SECTION_KEYS[sec] do
									d[k] = if defaults[k] ~= nil then defaults[k] else prefs[k]
								end
								draft(d)
								epoch(untrack(epoch) + 1)
							end,
						})
				),
				Layout.pageBody(BUILD[sec](Layout.counter()), {
					Size = function()
						return UDim2.new(1, 0, 1, -PAGE_HEAD - (if dirty() then 64 else 0))
					end,
				}),
			}
		end),
	})
	-- Discard re-renders with the saved values
	local lastDirty = false
	Vide.effect(function()
		local d = dirty()
		if lastDirty and not d then
			epoch(untrack(epoch) + 1)
		end
		lastDirty = d
	end)

	local mainTile = Base.tile(313, 0, 937, PAGE_H, { main, bar })
	return frame(Base.with({ Name = "Settings", Size = UDim2.fromScale(1, 1), navTile, mainTile }, props))
end

return Settings
