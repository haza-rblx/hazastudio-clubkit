--!strict
-- Decides whether a client's measured track duration may move the server's end-of-song timer.
-- Pure. DoS sweep D1: a report must never end the song. A song that really is that short ends
-- through the PlaybackFinished quorum, where one client cannot decide for everyone.

local MusicDurationPolicy = {}

MusicDurationPolicy.MAX_DURATION_SECONDS = 4 * 3600

local DEFAULT_MIN_REMAINING_SECONDS = 45
local MIN_REMAINING_FLOOR_SECONDS = 15
local UNCHANGED_TOLERANCE_SECONDS = 0.5
local LIBRARY_SHRINK_TOLERANCE_SECONDS = 1

export type Input = {
	isCurrentTrack: boolean,
	isPlaying: boolean,
	reportedDuration: any,
	libraryDuration: number?,
	startServerTime: number,
	expectedEndServerTime: number,
	now: number,
	minRemainingSeconds: number?,
}

-- reason: "accepted" | "not_current" | "invalid" | "too_soon" | "shrinks_library" | "unchanged"
export type Decision = {
	accept: boolean,
	reason: string,
	expectedEnd: number?,
}

local function refuse(reason: string): Decision
	return { accept = false, reason = reason }
end

function MusicDurationPolicy.evaluate(input: Input): Decision
	if input.isCurrentTrack ~= true or input.isPlaying ~= true then
		return refuse("not_current")
	end

	local duration = input.reportedDuration
	if
		type(duration) ~= "number"
		or duration ~= duration -- NaN
		or duration <= 0
		or duration > MusicDurationPolicy.MAX_DURATION_SECONDS
	then
		return refuse("invalid")
	end

	local newEnd = input.startServerTime + duration
	local configured = input.minRemainingSeconds
	local minRemaining =
		math.max(MIN_REMAINING_FLOOR_SECONDS, if type(configured) == "number" then configured else DEFAULT_MIN_REMAINING_SECONDS)
	if newEnd <= input.now + minRemaining then
		return refuse("too_soon")
	end

	local library = if type(input.libraryDuration) == "number" then input.libraryDuration else 0
	if library > 0 and duration < library - LIBRARY_SHRINK_TOLERANCE_SECONDS then
		return refuse("shrinks_library")
	end

	if math.abs(newEnd - input.expectedEndServerTime) < UNCHANGED_TOLERANCE_SECONDS then
		return refuse("unchanged")
	end

	return { accept = true, reason = "accepted", expectedEnd = newEnd }
end

return MusicDurationPolicy
