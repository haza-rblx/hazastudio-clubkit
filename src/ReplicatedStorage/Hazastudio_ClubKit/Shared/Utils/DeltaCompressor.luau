--!strict
-- DeltaCompressor — Computes and applies state deltas.
-- Only transmits fields that changed since the last snapshot.
-- Reduces payload size by 60-80% for periodic state broadcasts.
--
-- Usage pattern:
--   Server: computeDelta() to get changed fields only
--   Client: applyDelta() to reconstruct full state from partial update
--
-- Important: FIRST sync per key always returns full state (not delta).
-- Important: When player joins mid-session, call resetKey() to force full state.
--
-- When Config.NetworkPerf.DEEP_DELTA_NESTED is true, nested tables are compared
-- by deep equality (fixes shallow ~= false positives on visibleBadges / style tables).
--
-- See: Guidelines/REF_ARCHITECTURE.md (Network Transport section)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

-- ── Constants ─────────────────────────────────────────────────

-- Sentinel value for fields that were removed (set to nil).
-- Using a unique string that won't collide with real data.
local NIL_SENTINEL = "__NIL__"

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return false
	end
	local aTable = a :: { [any]: any }
	local bTable = b :: { [any]: any }
	for key, value in aTable do
		if not deepEqual(value, bTable[key]) then
			return false
		end
	end
	for key in bTable do
		if aTable[key] == nil then
			return false
		end
	end
	return true
end

local function deepClone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy: { [any]: any } = {}
	for key, child in value :: { [any]: any } do
		copy[key] = deepClone(child)
	end
	return copy
end

local function valuesEqual(a: any, b: any, deepNested: boolean): boolean
	if a == b then
		return true
	end
	if deepNested and type(a) == "table" and type(b) == "table" then
		return deepEqual(a, b)
	end
	return false
end

local function cloneState(state: { [string]: any }, deepNested: boolean): { [string]: any }
	if deepNested then
		return deepClone(state) :: { [string]: any }
	end
	return table.clone(state)
end

local function useDeepNested(): boolean
	local np = Config.NetworkPerf
	return type(np) == "table" and np.DEEP_DELTA_NESTED == true
end

-- ── Factory ───────────────────────────────────────────────────

local function create()
	-- Last known state per key (e.g., per channel or per player)
	local snapshots: { [string]: { [string]: any } } = {}

	local self = {}

	--- Compute delta between current state and last known snapshot.
	--- Returns only the fields that changed. Returns nil if nothing changed.
	--- First call for a key always returns the full state.
	--- @param key string -- Unique key for this state stream (e.g., "sync:group_abc")
	--- @param currentState {[string]: any} -- Full current state
	--- @return {[string]: any}? -- Delta (changed fields only), or nil if no changes
	function self:computeDelta(key: string, currentState: { [string]: any }): { [string]: any }?
		local deepNested = useDeepNested()
		local lastSnapshot = snapshots[key]

		-- First time: send full state, store snapshot
		if not lastSnapshot then
			snapshots[key] = cloneState(currentState, deepNested)
			return currentState
		end

		-- Compute diff: check for changed or new fields
		local delta: { [string]: any } = {}
		local hasChanges = false

		for field, value in currentState do
			if not valuesEqual(lastSnapshot[field], value, deepNested) then
				delta[field] = value
				hasChanges = true
			end
		end

		-- Check for removed fields (present in snapshot but not in current)
		for field in lastSnapshot do
			if currentState[field] == nil then
				delta[field] = NIL_SENTINEL
				hasChanges = true
			end
		end

		if not hasChanges then
			return nil
		end

		-- Update snapshot to current state
		snapshots[key] = cloneState(currentState, deepNested)
		return delta
	end

	--- Apply a delta to reconstruct full state on the receiving end.
	--- Merges delta into the last known state for this key.
	--- @param key string -- Same key used in computeDelta
	--- @param delta {[string]: any} -- The delta received from network
	--- @return {[string]: any} -- Reconstructed full state (cloned, safe to modify)
	function self:applyDelta(key: string, delta: { [string]: any }): { [string]: any }
		local deepNested = useDeepNested()
		local state = snapshots[key]
		if not state then
			-- First delta received — treat as full state
			state = {}
		else
			-- Clone to avoid mutating the stored snapshot
			state = cloneState(state, deepNested)
		end

		for field, value in delta do
			if value == NIL_SENTINEL then
				state[field] = nil
			else
				state[field] = value
			end
		end

		-- Store the reconstructed state as new snapshot
		snapshots[key] = cloneState(state, deepNested)
		return state
	end

	--- Force a full state reset for a key.
	--- Use when a new player joins mid-session and needs full state.
	--- Next computeDelta() for this key will return full state.
	function self:resetKey(key: string)
		snapshots[key] = nil
	end

	--- Remove all snapshots matching a key prefix.
	--- Useful for cleaning up all state for a channel or player.
	--- @param keyPrefix string -- Prefix to match (e.g., "sync:group_abc")
	function self:cleanup(keyPrefix: string)
		for key in snapshots do
			if string.sub(key, 1, #keyPrefix) == keyPrefix then
				snapshots[key] = nil
			end
		end
	end

	--- Full cleanup — remove all snapshots.
	function self:destroy()
		table.clear(snapshots)
	end

	return self
end

-- ── Versioned baselines (production hardening P4, plan H2; ADR 0016) ─────
--
-- `create()` above keeps a copy of the last state per KEY; the overhead used one key per
-- viewer-subject pair, i.e. up to n² deep copies (~40k at 200 dense players) and an O(n²)
-- prefix scan on every leave. The versioned store keeps ONE baseline per subject plus a
-- version number per field; a pair stores only the version that viewer last received.
--   commit(subject, payload)  diff against the subject's previous commit ONCE, bump versions
--   deltaFor(subject, viewer) fields newer than the viewer's version (full on first send)
-- Every viewer that is one commit behind shares one delta table (computed once).
-- `selfOnlyFields` (e.g. xp) are sent to other viewers only in full snapshots or riding along
-- another changed field: a change made only of those fields goes to the subject alone, and
-- the other viewers' versions stay put so the field rides along later (plan H1, broadcast side).

export type VersionedOptions = {
	deepNested: boolean?,
	selfOnlyFields: { [string]: boolean }?,
}

type SubjectState = {
	baseline: { [string]: any },
	payload: { [string]: any },
	version: number,
	fieldVersion: { [string]: number },
	sent: { [number]: number },
	-- fromVersion -> shared delta (or false = nothing a non-self viewer may receive)
	deltaCache: { [number]: any },
}

local function createVersioned(options: VersionedOptions?)
	local opts = options or {}
	local selfOnly = opts.selfOnlyFields
	local function deepNested(): boolean
		if opts.deepNested ~= nil then
			return opts.deepNested == true
		end
		return useDeepNested()
	end

	local subjects: { [number]: SubjectState } = {}
	-- viewer -> set of subjects it holds a version for (O(k) viewer cleanup)
	local viewerIndex: { [number]: { [number]: boolean } } = {}
	local pairCount = 0
	local sharedHits = 0

	local function forgetPair(subjectId: number, viewerId: number)
		local state = subjects[subjectId]
		if state and state.sent[viewerId] ~= nil then
			state.sent[viewerId] = nil
			pairCount -= 1
		end
		local set = viewerIndex[viewerId]
		if set then
			set[subjectId] = nil
			if next(set) == nil then
				viewerIndex[viewerId] = nil
			end
		end
	end

	local function markSent(state: SubjectState, subjectId: number, viewerId: number)
		if state.sent[viewerId] == nil then
			pairCount += 1
			local set = viewerIndex[viewerId]
			if not set then
				set = {}
				viewerIndex[viewerId] = set
			end
			set[subjectId] = true
		end
		state.sent[viewerId] = state.version
	end

	-- Fields newer than `from`, plus whether every one of them is self-only.
	local function buildDelta(state: SubjectState, from: number): ({ [string]: any }?, boolean)
		local delta: { [string]: any } = {}
		local any = false
		local onlySelf = true
		local payload = state.payload
		for field, version in state.fieldVersion do
			if version > from then
				local value = payload[field]
				delta[field] = if value == nil then NIL_SENTINEL else value
				any = true
				if not (selfOnly and selfOnly[field]) then
					onlySelf = false
				end
			end
		end
		if not any then
			return nil, false
		end
		return delta, onlySelf
	end

	local store = {}

	--- Record the subject's current payload. Returns true when any field differs from the
	--- previous commit (a first commit counts as a change).
	function store:commit(subjectId: number, payload: { [string]: any }): boolean
		local deep = deepNested()
		local state = subjects[subjectId]
		if not state then
			local fieldVersion: { [string]: number } = {}
			for field in payload do
				fieldVersion[field] = 1
			end
			subjects[subjectId] = {
				baseline = cloneState(payload, deep),
				payload = payload,
				version = 1,
				fieldVersion = fieldVersion,
				sent = {},
				deltaCache = {},
			}
			return true
		end
		local baseline = state.baseline
		local nextVersion = state.version + 1
		local changed = false
		for field, value in payload do
			if not valuesEqual(baseline[field], value, deep) then
				state.fieldVersion[field] = nextVersion
				changed = true
			end
		end
		for field in baseline do
			if payload[field] == nil then
				state.fieldVersion[field] = nextVersion
				changed = true
			end
		end
		state.payload = payload
		if not changed then
			return false
		end
		state.version = nextVersion
		state.baseline = cloneState(payload, deep)
		table.clear(state.deltaCache)
		return true
	end

	--- What `viewerId` must receive for `subjectId`: the full payload on the first send (or
	--- after resetPair), the changed fields after that, nil when it is up to date.
	function store:deltaFor(subjectId: number, viewerId: number): { [string]: any }?
		local state = subjects[subjectId]
		if not state then
			return nil
		end
		local from = state.sent[viewerId]
		if from == nil then
			markSent(state, subjectId, viewerId)
			return state.payload
		end
		if from >= state.version then
			return nil
		end
		local isSelf = viewerId == subjectId
		local cached = state.deltaCache[from]
		local delta: { [string]: any }?
		local onlySelf: boolean
		if cached ~= nil then
			sharedHits += 1
			delta = cached.delta
			onlySelf = cached.onlySelf
		else
			delta, onlySelf = buildDelta(state, from)
			state.deltaCache[from] = { delta = delta, onlySelf = onlySelf }
		end
		if delta == nil then
			state.sent[viewerId] = state.version
			return nil
		end
		if onlySelf and not isSelf and selfOnly ~= nil then
			-- Nothing this viewer may see yet; keep its version so the change rides along later.
			return nil
		end
		state.sent[viewerId] = state.version
		return delta
	end

	--- True when `viewerId` has been sent `subjectId`'s payload and not reset since.
	function store:hasPair(subjectId: number, viewerId: number): boolean
		local state = subjects[subjectId]
		return state ~= nil and state.sent[viewerId] ~= nil
	end

	--- Forget what `viewerId` has for `subjectId`; its next deltaFor is a full payload.
	function store:resetPair(subjectId: number, viewerId: number)
		forgetPair(subjectId, viewerId)
	end

	--- Subject left: O(k) in the number of viewers it had.
	function store:removeSubject(subjectId: number)
		local state = subjects[subjectId]
		if not state then
			return
		end
		for viewerId in state.sent do
			pairCount -= 1
			local set = viewerIndex[viewerId]
			if set then
				set[subjectId] = nil
				if next(set) == nil then
					viewerIndex[viewerId] = nil
				end
			end
		end
		subjects[subjectId] = nil
	end

	--- Viewer left: O(k) in the number of subjects it held.
	function store:removeViewer(viewerId: number)
		local set = viewerIndex[viewerId]
		if not set then
			return
		end
		viewerIndex[viewerId] = nil
		for subjectId in set do
			local state = subjects[subjectId]
			if state and state.sent[viewerId] ~= nil then
				state.sent[viewerId] = nil
				pairCount -= 1
			end
		end
	end

	function store:stats(): { subjects: number, pairs: number, sharedDeltaHits: number }
		local n = 0
		for _ in subjects do
			n += 1
		end
		return { subjects = n, pairs = pairCount, sharedDeltaHits = sharedHits }
	end

	function store:destroy()
		table.clear(subjects)
		table.clear(viewerIndex)
		pairCount = 0
	end

	return store
end

return { create = create, createVersioned = createVersioned, NIL_SENTINEL = NIL_SENTINEL }
