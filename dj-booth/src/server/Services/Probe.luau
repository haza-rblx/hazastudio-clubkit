--!strict
-- Checks audio asset ids with Roblox: the catalogue name and creator, and whether the audio really
-- loads in this experience (a Sound parented under ServerStorage, up to 3 attempts). Only an explicit
-- fetch Failure marks a track unavailable; a timeout is Pending and re-checked (ADR 0021 §6). Also
-- re-checks the whole library in the background so tracks that went private show up.
local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Janitor = require(ReplicatedStorage.HazaDJ.Packages.Janitor)
local Dict = require(ReplicatedStorage.HazaDJ.Shared.Dict)
local State = require(script.Parent.State)
local Store = require(script.Parent.Store)

local Probe = {}

export type Result = { AssetId: number, Ok: boolean, Name: string?, Creator: string?, Len: number?, Pending: boolean? }

local TIMEOUT = 25 -- seconds per attempt
local ATTEMPTS = 3
local DEADLINE = ATTEMPTS * TIMEOUT + 10 -- Probe.many stops waiting after this, with what it has
local PENDING_EVERY = 300 -- pending (timed out) tracks and sounds are re-checked this often
local folder = Instance.new("Folder")
folder.Name = "HazaDJ_Probe"
folder.Parent = ServerStorage

local cache: { [number]: { result: Result, at: number } } = {}
-- the two background sweeps; stop() ends them
local janitor = Janitor.new()
local started = false

-- one attempt: the length if it loaded, else whether Roblox reports the fetch as failed
local function attempt(assetId: number): (number?, boolean)
	local url = "rbxassetid://" .. string.format("%d", assetId)
	local s = Instance.new("Sound")
	s.SoundId = url
	s.Volume = 0
	s.Parent = folder
	local t0 = os.clock()
	while not s.IsLoaded and os.clock() - t0 < TIMEOUT do
		task.wait(0.1)
	end
	local len = if s.IsLoaded and s.TimeLength > 0 then s.TimeLength else nil
	local failed = false
	if not len then
		-- the status API may not exist in every build: then only a loaded-but-empty Sound counts
		local okStatus, status = pcall(ContentProvider.GetAssetFetchStatus, ContentProvider, url)
		failed = (okStatus and status == Enum.AssetFetchStatus.Failure) or s.IsLoaded
	end
	s:Destroy()
	return len, failed
end

function Probe.one(assetId: number): Result
	local hit = cache[assetId]
	if hit and os.clock() - hit.at < 300 then
		return hit.result
	end
	local name, creator
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, assetId, Enum.InfoType.Asset)
	if ok and type(info) == "table" and info.AssetTypeId == 3 then
		name = info.Name
		creator = info.Creator and info.Creator.Name
	end
	local len: number? = nil
	local failed = false
	for _ = 1, ATTEMPTS do
		local l, f = attempt(assetId)
		if l then
			len = l
			break
		end
		if f then
			failed = true
			break
		end
	end
	local pending = len == nil and not failed
	local result: Result = {
		AssetId = assetId,
		Ok = len ~= nil,
		Name = name,
		Creator = creator,
		Len = len,
		Pending = pending,
	}
	-- a timeout is not cached: it is asked again on the next pending pass
	if not pending then
		cache[assetId] = { result = result, at = os.clock() }
	end
	return result
end

-- several at once, in parallel; always returns, one entry per id
function Probe.many(ids: { number }): { Result }
	local out = table.create(#ids) :: { Result? }
	local left = #ids
	local done = Instance.new("BindableEvent")
	for i, id in ids do
		task.spawn(function()
			local ok, r = pcall(Probe.one, id)
			if ok then
				out[i] = r
			end
			left -= 1
			if left == 0 then
				done:Fire()
			end
		end)
	end
	if left > 0 then
		local timer = task.delay(DEADLINE, function()
			done:Fire()
		end)
		done.Event:Wait()
		task.cancel(timer)
	end
	done:Destroy()
	local result = table.create(#ids) :: { Result }
	for i, id in ids do
		result[i] = out[i] or { AssetId = id, Ok = false, Pending = true }
	end
	return result
end

-- re-check one library track and store its status
function Probe.track(id: string)
	local t = State.library().tracks[id]
	if not t then
		return
	end
	local r = Probe.one(t.assetId)
	State.update(State.library, function(lib)
		local cur = lib.tracks[id]
		if not cur or cur.assetId ~= t.assetId then
			return lib
		end
		local status = if r.Ok then "ready" elseif r.Pending then "checking" else "unavailable"
		local len = r.Len or cur.len
		if cur.status == status and cur.len == len then
			return lib
		end
		return Dict.merge(lib, { tracks = Dict.set(lib.tracks, id, Dict.merge(cur, { status = status, len = len })) })
	end)
end

-- re-check one library sound and store its status (Sounds list, Library.addSound)
local function probeSound(id: string)
	local s = nil
	for _, x in State.library().sounds do
		if x.id == id then
			s = x
		end
	end
	if not s then
		return
	end
	local r = Probe.one(s.assetId)
	State.update(State.library, function(lib)
		for i, cur in lib.sounds do
			if cur.id == id and cur.assetId == s.assetId then
				local status = if r.Ok then Dict.None elseif r.Pending then "checking" else "unavailable"
				return Dict.merge(lib, {
					sounds = Dict.set(lib.sounds, i, Dict.merge(cur, { status = status, len = r.Len or Dict.None })),
				})
			end
		end
		return lib
	end)
end

function Probe.start()
	if Store.fixture or started then
		return -- the fixture's ids are made up; keep its statuses
	end
	started = true
	-- a slow background sweep: one track every 2 s, then again every 30 minutes
	janitor:Add(
		task.spawn(function()
			while true do
				for id in State.library().tracks do
					Probe.track(id)
					task.wait(2)
				end
				task.wait(1800)
			end
		end),
		true
	)
	-- anything that timed out (status "checking") is asked again every 5 minutes
	janitor:Add(
		task.spawn(function()
			while true do
				task.wait(PENDING_EVERY)
				for id, t in State.library().tracks do
					if t.status == "checking" then
						Probe.track(id)
						task.wait(2)
					end
				end
				for _, s in State.library().sounds do
					if s.status == "checking" then
						probeSound(s.id)
						task.wait(2)
					end
				end
			end
		end),
		true
	)
end

function Probe.stop()
	janitor:Cleanup()
	started = false
end

return Probe
