--!strict
-- Background preload (ADR 0021 §7): loads the DJ deck's audio once ahead of time, so a deck's
-- first load is a cache hit. Order: the live DJ's hints, the tracks on the decks, the queue, then the
-- library newest first (only players who may open the panel get the library). Each id is asked for
-- once; a slow fetch frees its slot after 25 s even if Roblox has not answered. Each preloaded track
-- keeps ~0.7 MB of sound memory for the session (measured 2026-10-30), hence the caps.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Charm = require(ReplicatedStorage.CosmicDJ.Packages.Charm)
local LoadPolicy = require(ReplicatedStorage.CosmicDJ.Shared.LoadPolicy)
local Store = require(script.Parent.Store)

local Preload = {}

local DEBOUNCE = 2 -- seconds a change waits before the list is rebuilt
local SLOT_TIME = 25 -- seconds before a slot is freed, whether or not Roblox has answered
local HINT_CAP = 30 -- hinted tracks a client preloads per session, on top of the cap below

local seen: { [number]: boolean } = {} -- asset ids already queued (never twice)
local queued = 0 -- ids queued in total, against the cap
local hinted = 0 -- hinted ids queued, against HINT_CAP
local waiting: { number } = {}
local inFlight = 0
local scheduled = false
local isTouch = false

-- the asset ids in preload order, skipping tracks Roblox can't load
local function collect(): { number }
	local lib = Store.libraryAtom()
	local stage = Store.stageAtom()
	local s = Store.sessionAtom()
	local out: { number } = {}
	local function add(id: string?)
		local t = if id then stage.tracks[id] or lib.tracks[id] else nil
		if t and t.status ~= "unavailable" then
			table.insert(out, t.assetId)
		end
	end
	for n = 1, 2 do
		add(s.decks[n].trackId)
	end
	for _, e in s.queue do
		add(e.trackId)
	end
	local all = {}
	for _, t in lib.tracks do
		table.insert(all, t)
	end
	table.sort(all, function(a, b)
		return a.added > b.added
	end)
	for _, t in all do
		add(t.id)
	end
	return out
end

local function fetch(id: number)
	-- a silent Sound in the DataModel that is waited on until it has loaded: measured 2026-10-30, a
	-- ContentProvider.PreloadAsync on a loose Sound left a deck's first load at 600-760 ms, while a
	-- Sound that actually loaded once makes every later load of that id take a frame or two
	local holder = Instance.new("Sound")
	holder.Name = "CosmicDJ_Warm"
	holder.Volume = 0
	holder.SoundId = LoadPolicy.contentId(id, 1)
	holder.Parent = SoundService
	local t0 = os.clock()
	while not holder.IsLoaded and os.clock() - t0 < SLOT_TIME do
		task.wait(0.1)
	end
	holder:Destroy()
	inFlight -= 1
	Preload.pump()
end

function Preload.pump()
	while inFlight < LoadPolicy.PRELOAD_CONCURRENCY and #waiting > 0 do
		local id = table.remove(waiting, 1) :: number
		inFlight += 1
		task.spawn(fetch, id)
	end
end

-- the live DJ's hints jump the line, at once (no debounce): the DJ is about to play one of them
local function queueHints(stage: any)
	for i = #stage.hints, 1, -1 do
		local t = stage.tracks[stage.hints[i]]
		local id = if t and t.status ~= "unavailable" then t.assetId else nil
		if id and not seen[id] and hinted < HINT_CAP then
			seen[id] = true
			hinted += 1
			table.insert(waiting, 1, id)
		end
	end
	Preload.pump()
end

-- rebuild the list (debounced) and queue what is new
local function schedule()
	if scheduled then
		return
	end
	scheduled = true
	task.delay(DEBOUNCE, function()
		scheduled = false
		local limit = if isTouch then LoadPolicy.PRELOAD_CAP_MOBILE else LoadPolicy.PRELOAD_CAP_DESKTOP
		for _, id in collect() do
			if queued >= limit then
				break
			end
			if not seen[id] then
				seen[id] = true
				queued += 1
				table.insert(waiting, id)
			end
		end
		Preload.pump()
	end)
end

function Preload.start()
	isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	-- nothing until the first full state has arrived; then again whenever the library, queue or decks change
	Charm.effect(function()
		if not Store.readyAtom() then
			return
		end
		Store.libraryAtom()
		Store.stageAtom()
		Store.sessionAtom()
		schedule()
	end)
	Charm.effect(function()
		if Store.readyAtom() then
			queueHints(Store.stageAtom())
		end
	end)
end

return Preload
