--!strict
-- Shared/Domain/AvatarLikePolicy.luau
-- Pure functions only. Zero Roblox service calls.
--
-- Owns the rule for "a like resets every WIB day". The stored entry per (target, giver) stays ONE
-- number, so a target's shard does not grow when the same people like every day:
--
--   nil               never interacted
--   0                 legacy: liked once, then unliked
--   1                 legacy: a standing like from before daily mode existed
--   >= MIN_DAY_STAMP  the WIB day number of that giver's most recent like
--
-- Legacy 0/1 stay readable because a real WIB day number is ~20700 today and MIN_DAY_STAMP is a day
-- in 1997 — one the kit could never have written. This is what lets daily mode ship without a
-- DataStore key change or a migration pass: old entries keep their meaning, new ones carry a date.
--
-- A legacy standing like counts as "liked on a day nobody recorded", so its holder may like again
-- today. Reading it as "already liked today" would instead lock every existing liker out until
-- tomorrow, for a day that never happened.
local AvatarLikePolicy = {}

-- WIB day 10000 = 1997-05-19. Any stored number at or above this is a date, not a legacy state.
AvatarLikePolicy.MIN_DAY_STAMP = 10000

export type LikeEntryKind = "none" | "legacy_unliked" | "legacy_liked" | "day"

export type LikeEntry = {
	kind: LikeEntryKind,
	day: number?,
}

export type LikeOutcome = {
	nextValue: number?,
	delta: number,
	transition: string,
	alreadyLikedToday: boolean,
}

--- Read a stored entry. Anything unreadable is "never interacted" rather than a guess: at worst
--- that grants one extra like, where guessing the other way could wipe a total.
function AvatarLikePolicy.classify(value: any): LikeEntry
	if type(value) ~= "number" then
		return { kind = "none" }
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return { kind = "none" }
	end
	if value % 1 ~= 0 then
		return { kind = "none" }
	end
	if value == 0 then
		return { kind = "legacy_unliked" }
	end
	if value == 1 then
		return { kind = "legacy_liked" }
	end
	if value >= AvatarLikePolicy.MIN_DAY_STAMP then
		return { kind = "day", day = value }
	end
	return { kind = "none" }
end

--- What `activeCount` counts: this giver currently holds a like on this target.
function AvatarLikePolicy.hasActiveLike(value: any): boolean
	local kind = AvatarLikePolicy.classify(value).kind
	return kind == "legacy_liked" or kind == "day"
end

function AvatarLikePolicy.likedOnDay(value: any, day: number): boolean
	local entry = AvatarLikePolicy.classify(value)
	return entry.kind == "day" and entry.day == day
end

--- What the profile panel's button reads. In daily mode "liked" means "liked today" — a legacy
--- standing like is spent, not today's, so its holder is offered the button again.
function AvatarLikePolicy.viewerHasLiked(value: any, nowDay: number, dailyEnabled: boolean): boolean
	if dailyEnabled then
		return AvatarLikePolicy.likedOnDay(value, nowDay)
	end
	return AvatarLikePolicy.hasActiveLike(value)
end

local function canonical(entry: LikeEntry): number?
	if entry.kind == "day" then
		return entry.day
	elseif entry.kind == "legacy_liked" then
		return 1
	elseif entry.kind == "legacy_unliked" then
		return 0
	end
	return nil
end

--- Decide what one like/unlike request does.
---
--- `dailyEnabled = false` reproduces the pre-2.12 toggle exactly, including for entries written
--- while daily mode was on — a buyer who switches the flag back off must not find a venue full of
--- likes that cannot be toggled.
function AvatarLikePolicy.evaluate(previous: any, action: string, nowDay: number, dailyEnabled: boolean): LikeOutcome
	local entry = AvatarLikePolicy.classify(previous)
	local current = canonical(entry)

	if dailyEnabled then
		if action ~= "like" then
			-- One-way per day. The client stops offering unlike in daily mode; a crafted remote must
			-- not be able to spend the day's like and then take the count back down.
			return { nextValue = current, delta = 0, transition = "noop", alreadyLikedToday = entry.day == nowDay }
		end

		if entry.kind == "day" and entry.day == nowDay then
			return { nextValue = current, delta = 0, transition = "noop", alreadyLikedToday = true }
		end

		local transition = "first_like"
		if entry.kind == "legacy_unliked" then
			transition = "reliked"
		elseif entry.kind == "legacy_liked" or entry.kind == "day" then
			transition = "daily_like"
		end

		return { nextValue = nowDay, delta = 1, transition = transition, alreadyLikedToday = false }
	end

	local liked = entry.kind == "legacy_liked" or entry.kind == "day"

	if action == "like" then
		if liked then
			return { nextValue = current, delta = 0, transition = "noop", alreadyLikedToday = false }
		end
		local transition = if entry.kind == "legacy_unliked" then "reliked" else "first_like"
		return { nextValue = 1, delta = 1, transition = transition, alreadyLikedToday = false }
	end

	if liked then
		return { nextValue = 0, delta = -1, transition = "unliked", alreadyLikedToday = false }
	end
	if entry.kind == "legacy_unliked" then
		return { nextValue = 0, delta = 0, transition = "noop", alreadyLikedToday = false }
	end
	return { nextValue = nil, delta = 0, transition = "noop", alreadyLikedToday = false }
end

--- A target's total is rebuilt by summing its shards. That used to mean counting standing likes,
--- which is only correct while one giver can contribute at most 1 — with daily likes each shard has
--- to carry its own running total. A shard written before this change has none, and falls back to
--- the count that WAS its total, so a reconcile can never zero a venue's likes.
function AvatarLikePolicy.resolveShardTotal(storedTotal: any, activeCount: number): number
	if
		type(storedTotal) == "number"
		and storedTotal == storedTotal
		and storedTotal >= 0
		and storedTotal ~= math.huge
	then
		return math.floor(storedTotal)
	end
	local fallback = if type(activeCount) == "number" and activeCount == activeCount then activeCount else 0
	return math.max(0, math.floor(fallback))
end

return AvatarLikePolicy
