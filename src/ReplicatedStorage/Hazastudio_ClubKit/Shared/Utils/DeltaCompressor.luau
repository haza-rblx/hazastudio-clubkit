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
-- See: Guidelines/REF_ARCHITECTURE.md (Network Transport section)

-- ── Constants ─────────────────────────────────────────────────

-- Sentinel value for fields that were removed (set to nil).
-- Using a unique string that won't collide with real data.
local NIL_SENTINEL = "__NIL__"

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
        local lastSnapshot = snapshots[key]

        -- First time: send full state, store snapshot
        if not lastSnapshot then
            snapshots[key] = table.clone(currentState)
            return currentState
        end

        -- Compute diff: check for changed or new fields
        local delta: { [string]: any } = {}
        local hasChanges = false

        for field, value in currentState do
            if lastSnapshot[field] ~= value then
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

        if not hasChanges then return nil end

        -- Update snapshot to current state
        snapshots[key] = table.clone(currentState)
        return delta
    end

    --- Apply a delta to reconstruct full state on the receiving end.
    --- Merges delta into the last known state for this key.
    --- @param key string -- Same key used in computeDelta
    --- @param delta {[string]: any} -- The delta received from network
    --- @return {[string]: any} -- Reconstructed full state (cloned, safe to modify)
    function self:applyDelta(key: string, delta: { [string]: any }): { [string]: any }
        local state = snapshots[key]
        if not state then
            -- First delta received — treat as full state
            state = {}
        else
            -- Clone to avoid mutating the stored snapshot
            state = table.clone(state)
        end

        for field, value in delta do
            if value == NIL_SENTINEL then
                state[field] = nil
            else
                state[field] = value
            end
        end

        -- Store the reconstructed state as new snapshot
        snapshots[key] = table.clone(state)
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

return { create = create, NIL_SENTINEL = NIL_SENTINEL }
