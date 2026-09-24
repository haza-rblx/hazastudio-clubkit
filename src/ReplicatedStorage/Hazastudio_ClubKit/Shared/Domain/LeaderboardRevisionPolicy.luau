--!strict
-- Shared/Domain/LeaderboardRevisionPolicy.luau
--
-- Workspace leaderboard revision broadcast (production hardening P4, H10). Pure; spec
-- .tmp/leaderboard-revision-spec.luau.
--
-- Server: on every board change it fires `message(rev)` ({ kind = "lb_rev", rev }, < 64 B) to all
-- clients instead of the 15–40 KB payload. The server still paints the SurfaceGui boards
-- (Config.Leaderboards.SERVER_PAINT_WORKSPACE), so a client needs the payload only for what it
-- draws itself (daily showcase loops; everything when CLIENT_PAINT_DATA).
-- Client: `observe` each revision; `shouldFetch` is true only while a board it draws is visible,
-- no fetch is in flight (or it timed out), and `minIntervalSec` passed since the last fetch
-- started (the server's snapshot limiter allows 2 per 15 s). The fetched payload settles the
-- revision it carries, or the one known when the request left.

export type Config = {
	minIntervalSec: number,
	timeoutSec: number,
}

export type State = {
	latestRev: number,
	fetchedRev: number,
	requestedRev: number,
	inFlightSince: number?,
	lastFetchAt: number,
}

export type Message = { kind: string, rev: number }

local MESSAGE_KIND = "lb_rev"

local LeaderboardRevisionPolicy = {}

LeaderboardRevisionPolicy.MESSAGE_KIND = MESSAGE_KIND

function LeaderboardRevisionPolicy.message(rev: number): Message
	return { kind = MESSAGE_KIND, rev = rev }
end

--- (true, rev) for a revision message; (false, nil) for anything else (e.g. a legacy full payload).
function LeaderboardRevisionPolicy.parse(raw: any): (boolean, number?)
	if type(raw) ~= "table" or raw.kind ~= MESSAGE_KIND or type(raw.rev) ~= "number" then
		return false, nil
	end
	return true, raw.rev
end

function LeaderboardRevisionPolicy.new(): State
	return {
		latestRev = -1,
		fetchedRev = -1,
		requestedRev = -1,
		inFlightSince = nil,
		lastFetchAt = -math.huge,
	}
end

--- Records a broadcast revision; true when it is newer than any revision known so far.
function LeaderboardRevisionPolicy.observe(state: State, rev: number): boolean
	if rev > state.latestRev then
		state.latestRev = rev
		return true
	end
	return false
end

function LeaderboardRevisionPolicy.isStale(state: State): boolean
	return state.latestRev > state.fetchedRev
end

function LeaderboardRevisionPolicy.shouldFetch(state: State, now: number, visible: boolean, cfg: Config): boolean
	if not visible or state.latestRev <= state.fetchedRev then
		return false
	end
	local since = state.inFlightSince
	if since ~= nil and now - since < cfg.timeoutSec then
		return false
	end
	return now - state.lastFetchAt >= cfg.minIntervalSec
end

function LeaderboardRevisionPolicy.markFetchStarted(state: State, now: number)
	state.inFlightSince = now
	state.lastFetchAt = now
	state.requestedRev = state.latestRev
end

--- A fetched payload arrived. `rev` = the revision it carries (nil = unknown: the one requested).
function LeaderboardRevisionPolicy.applyFetched(state: State, rev: number?, _now: number)
	state.inFlightSince = nil
	local settled = if type(rev) == "number" then rev else state.requestedRev
	if settled > state.latestRev then
		state.latestRev = settled
	end
	if settled > state.fetchedRev then
		state.fetchedRev = settled
	end
end

return LeaderboardRevisionPolicy
