--!strict
-- PATH: ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MusicTransportPolicy.luau
-- Pure rules for the v3 transport actions (stage E). Timing stays one server clock: pause freezes
-- the elapsed seconds, resume and seek move startServerTime/expectedEndServerTime so every
-- listener, the auto-advance timer and the progress bar read the same numbers. No Roblox APIs.

local MusicTransportPolicy = {}

local PREVIOUS_RESTART_AFTER_SECONDS = 3
local SEEK_END_MARGIN_SECONDS = 1

export type Timing = {
	startServerTime: number,
	expectedEndServerTime: number,
	effectivePlaybackSpeed: number?,
	isPaused: boolean?,
	pausedElapsed: number?,
}

export type TimingResult = { ok: boolean, reason: string, timing: Timing? }

local function total(timing: Timing): number
	return math.max(0, timing.expectedEndServerTime - timing.startServerTime)
end

local function isStopped(timing: Timing): boolean
	return type(timing) ~= "table" or (tonumber(timing.startServerTime) or 0) <= 0
end

local function refuse(reason: string): TimingResult
	return { ok = false, reason = reason, timing = nil }
end

local function withClock(timing: Timing, startServerTime: number, paused: boolean, pausedElapsed: number?): Timing
	return {
		startServerTime = startServerTime,
		expectedEndServerTime = startServerTime + total(timing),
		effectivePlaybackSpeed = timing.effectivePlaybackSpeed,
		isPaused = paused,
		pausedElapsed = pausedElapsed,
	}
end

function MusicTransportPolicy.elapsed(timing: Timing, now: number): number
	if isStopped(timing) then
		return 0
	end
	if timing.isPaused == true then
		return math.clamp(tonumber(timing.pausedElapsed) or 0, 0, total(timing))
	end
	return math.clamp(now - timing.startServerTime, 0, total(timing))
end

function MusicTransportPolicy.pause(timing: Timing, now: number): TimingResult
	if isStopped(timing) then
		return refuse("not_playing")
	end
	if timing.isPaused == true then
		return refuse("already_paused")
	end
	local frozen = MusicTransportPolicy.elapsed(timing, now)
	local result = table.clone(timing)
	result.isPaused = true
	result.pausedElapsed = frozen
	return { ok = true, reason = "", timing = result }
end

function MusicTransportPolicy.resume(timing: Timing, now: number): TimingResult
	if isStopped(timing) then
		return refuse("not_playing")
	end
	if timing.isPaused ~= true then
		return refuse("not_paused")
	end
	local frozen = MusicTransportPolicy.elapsed(timing, now)
	return { ok = true, reason = "", timing = withClock(timing, now - frozen, false, nil) }
end

function MusicTransportPolicy.seek(timing: Timing, now: number, deltaSeconds: number): TimingResult
	if isStopped(timing) then
		return refuse("not_playing")
	end
	if type(deltaSeconds) ~= "number" or deltaSeconds ~= deltaSeconds then
		return refuse("invalid_delta")
	end
	local maxElapsed = math.max(0, total(timing) - SEEK_END_MARGIN_SECONDS)
	local target = math.clamp(MusicTransportPolicy.elapsed(timing, now) + deltaSeconds, 0, maxElapsed)
	local paused = timing.isPaused == true
	return {
		ok = true,
		reason = "",
		timing = withClock(timing, now - target, paused, if paused then target else nil),
	}
end

-- "restart": play the current song from 0. "pop": go back to the previously played song.
function MusicTransportPolicy.previous(elapsedSeconds: number, historyCount: number): string
	if elapsedSeconds > PREVIOUS_RESTART_AFTER_SECONDS or historyCount <= 0 then
		return "restart"
	end
	return "pop"
end

function MusicTransportPolicy.removeEntry(
	queue: { any },
	entryId: string,
	userId: number,
	canControlAll: boolean
): { ok: boolean, reason: string, queue: { any } }
	local remaining = {}
	local found = nil
	for _, entry in ipairs(queue) do
		if found == nil and entry.entryId == entryId then
			found = entry
		else
			table.insert(remaining, entry)
		end
	end
	if found == nil then
		return { ok = false, reason = "not_found", queue = queue }
	end
	if not canControlAll and found.requesterUserId ~= userId then
		return { ok = false, reason = "not_owner", queue = queue }
	end
	return { ok = true, reason = "", queue = remaining }
end

function MusicTransportPolicy.planRequestMany(
	trackIds: { any },
	opts: { cap: number, excluded: { [string]: boolean }, shuffle: boolean?, random: ((number) -> number)? }
): { string }
	local picked: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, trackId in ipairs(trackIds) do
		if type(trackId) == "string" and trackId ~= "" and not seen[trackId] and not opts.excluded[trackId] then
			seen[trackId] = true
			table.insert(picked, trackId)
		end
	end

	if opts.shuffle == true and opts.random then
		local random = opts.random
		for i = #picked, 2, -1 do
			local j = math.clamp(random(i), 1, i)
			picked[i], picked[j] = picked[j], picked[i]
		end
	end

	local cap = math.max(0, math.floor(opts.cap))
	while #picked > cap do
		table.remove(picked)
	end
	return picked
end

return MusicTransportPolicy
