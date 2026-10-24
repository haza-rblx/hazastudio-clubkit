--!strict
-- Deck clock: where a deck is in its track, how fast it moves, and when it ends. Pure, so the server
-- (which anchors `pos` at server time `at`) and every client draw the same time.
local Types = require(script.Parent.Types)

local DeckClock = {}

-- track seconds per real second: the track's speed times the pitch fader
function DeckClock.rate(deck: Types.Deck, track: Types.Track?): number
	return (if track then track.speed else 1) * (1 + deck.pitch)
end

-- track position at server time `now`; a stopped deck holds `pos`
function DeckClock.position(deck: Types.Deck, track: Types.Track?, now: number): number
	if deck.playing and track then
		return math.max(0, deck.pos + (now - deck.at) * DeckClock.rate(deck, track))
	end
	return math.max(0, deck.pos)
end

-- the track's length, else the fallback (e.g. the length the server has seen); nil if neither is known
function DeckClock.length(track: Types.Track?, fallback: number?): number?
	if track and track.len and track.len > 0 then
		return track.len
	end
	if fallback and fallback > 0 then
		return fallback
	end
	return nil
end

-- real seconds until the end at the current rate; nil if the length is unknown
function DeckClock.timeLeft(deck: Types.Deck, track: Types.Track?, now: number, fallback: number?): number?
	local len = DeckClock.length(track, fallback)
	if not len then
		return nil
	end
	local rate = DeckClock.rate(deck, track)
	if rate <= 0 then
		return nil
	end
	return math.max(0, (len - DeckClock.position(deck, track, now)) / rate)
end

-- playing and within 50 ms of the end
function DeckClock.ended(deck: Types.Deck, track: Types.Track?, now: number, fallback: number?): boolean
	local len = DeckClock.length(track, fallback)
	return deck.playing and len ~= nil and DeckClock.position(deck, track, now) >= len - 0.05
end

-- a Sound's own position against the expected one: true when the gap is past the tolerance (default 1.5 s)
function DeckClock.drifted(soundPos: number, expected: number, tolerance: number?): boolean
	return math.abs(soundPos - expected) > (tolerance or 1.5)
end

return DeckClock
