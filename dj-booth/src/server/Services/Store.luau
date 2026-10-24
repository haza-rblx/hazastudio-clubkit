--!strict
-- Persistence for the booth's own data: library, access (residents, gates) and settings, as one
-- versioned DataStore document. Global state, so not ProfileStore (that is per player, session
-- locked). Writes are debounced UpdateAsync calls; other servers hear about a save through
-- MessagingService and reload. Guests are session only and never written.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Charm = require(ReplicatedStorage.HazaDJ.Packages.Charm)
local Shared = ReplicatedStorage.HazaDJ.Shared
local Defaults = require(Shared.Defaults)
local Fixture = require(Shared.Fixture)
local Types = require(Shared.Types)
local State = require(script.Parent.State)

local STORE_NAME = "HazaDJ_v1" -- the document key is versioned; a format change gets a new name
local DOC_KEY = "booth"
local TOPIC = "HazaDJ_v1_saved"
local DEBOUNCE = 6
local SIZE_WARN = 3_500_000

local Store = {}

type Doc = {
	v: number,
	rev: number,
	library: Types.Library,
	access: Types.Access,
	settings: Types.Settings,
}

local store: DataStore? = nil
local memoryOnly = false
local rev = 0
local dirty = false
local saving = false
local applyingRemote = false
local lastSaveAt = 0

Store.fixture = false

-- fill fields a newer build added, so an old document never crashes the booth
local function fillForward<T>(value: any, defaults: T): T
	if type(value) ~= "table" or type(defaults) ~= "table" then
		return if value == nil then defaults else value
	end
	local out = table.clone(value)
	for k, v in defaults :: any do
		if out[k] == nil then
			out[k] = v
		elseif type(v) == "table" and type(out[k]) == "table" and next(v) ~= nil and #v == 0 then
			out[k] = fillForward(out[k], v)
		end
	end
	return out :: any
end

local function snapshot(): Doc
	local access = State.access()
	local keep = {}
	for k, p in access.people do
		if p.role ~= "Guest" then
			keep[k] = p
		end
	end
	return {
		v = 1,
		rev = rev,
		library = State.library(),
		access = { people = keep, gates = access.gates },
		settings = State.settings(),
	}
end

local function apply(doc: Doc)
	applyingRemote = true
	State.library(fillForward(doc.library, Defaults.library()))
	local access = fillForward(doc.access, Defaults.access())
	-- keep this server's guests
	local people = table.clone(access.people)
	for k, p in State.access().people do
		if p.role == "Guest" then
			people[k] = p
		end
	end
	access.people = people
	State.access(access)
	State.settings(fillForward(doc.settings, Defaults.settings()))
	rev = doc.rev or 0
	applyingRemote = false
end

local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local delayS = 1
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[HazaDJ] {label} failed (attempt {attempt}): {result}`)
		task.wait(delayS)
		delayS *= 2
	end
	return false, nil
end

local function save()
	if memoryOnly or Store.fixture or saving or not store then
		return
	end
	saving = true
	dirty = false
	local doc = snapshot()
	local size = #HttpService:JSONEncode(doc)
	if size > SIZE_WARN then
		warn(`[HazaDJ] booth document is {size} bytes; the library is close to the DataStore limit`)
	end
	local ok = retry("save", function()
		return (store :: DataStore):UpdateAsync(DOC_KEY, function(old: Doc?)
			doc.rev = ((old and old.rev) or rev) + 1
			return doc
		end)
	end)
	if ok then
		rev = doc.rev
		lastSaveAt = os.clock()
		pcall(MessagingService.PublishAsync, MessagingService, TOPIC, { rev = rev, job = game.JobId })
	else
		dirty = true
	end
	saving = false
end

function Store.markDirty()
	if applyingRemote or memoryOnly or Store.fixture then
		return
	end
	if dirty then
		return
	end
	dirty = true
	task.delay(DEBOUNCE, function()
		if dirty then
			save()
		end
	end)
end

local function reload()
	if not store then
		return
	end
	local ok, doc = retry("reload", function()
		return (store :: DataStore):GetAsync(DOC_KEY)
	end)
	if ok and doc and (doc :: Doc).rev > rev then
		apply(doc :: Doc)
	end
end

function Store.start()
	if RunService:IsStudio() and workspace:GetAttribute("HazaDJ_Fixture") then
		Store.fixture = true
		local now = os.time()
		State.library(Fixture.cues(Fixture.library()))
		State.access(Fixture.access(now))
		State.session(Fixture.session(State.now()))
		return
	end
	local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	if not ok then
		warn("[HazaDJ] DataStores unavailable (enable Studio API access to save); the booth runs from memory")
		memoryOnly = true
		return
	end
	store = ds
	local loaded, doc = pcall(function()
		return (ds :: DataStore):GetAsync(DOC_KEY)
	end)
	if not loaded then
		warn("[HazaDJ] could not read the booth document; the booth runs from memory: " .. tostring(doc))
		memoryOnly = true
		return
	end
	if doc then
		apply(doc :: Doc)
	end

	-- every edit to the stored parts schedules a save
	for _, atom in { State.library, State.access, State.settings } :: { any } do
		Charm.subscribe(atom, Store.markDirty)
	end

	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(msg)
			local data = msg.Data
			if type(data) == "table" and data.job ~= game.JobId and (data.rev or 0) > rev then
				task.spawn(reload)
			end
		end)
	end)

	game:BindToClose(function()
		if dirty or os.clock() - lastSaveAt > 1 then
			save()
		end
	end)
end

function Store.status(): string
	return if Store.fixture then "fixture" elseif memoryOnly then "memory" else "datastore"
end

return Store
