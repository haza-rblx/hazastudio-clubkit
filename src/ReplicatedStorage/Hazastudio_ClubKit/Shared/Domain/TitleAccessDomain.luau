--!strict
-- Shared/Domain/TitleAccessDomain.luau
-- May this player edit their own overhead title, and on whose authority?
--
-- Four ways in, checked in this order — the order matters, because the caller
-- burns the free slot only when `reason` says the free slot is what paid:
--
--   "admin"  they hold a title an admin gave them (or a legacy title with no
--            source recorded — every title predating self-service was an admin
--            grant, so old players must not lose access when this rule ships)
--   "level"  they reached CustomTitle.MinLevel
--   "event"  they qualify for the Free Title event
--   "free"   the buyer offers one free title and this player has not spent it
--
-- Anything else is "locked". Removing a title never refunds the free slot: the
-- slot is spent by the act of creating, not by the title still existing.
--
-- Pure: no Roblox services, no Config require — the caller passes the facts in.

local TitleAccessDomain = {}

export type AccessInput = {
	-- Features.SelfCustomTitle. With it off nothing here can open the panel.
	selfServiceOn: boolean?,
	hasTitle: boolean?,
	-- nil on a legacy record = treat as an admin grant (see above).
	fromAdmin: boolean?,
	freeUsed: boolean?,
	freeEnabled: boolean?,
	meetsLevel: boolean?,
	meetsEvent: boolean?,
}

export type AccessState = {
	canEdit: boolean,
	-- "admin" | "level" | "event" | "free" | "locked"
	reason: string,
}

local LOCKED: AccessState = { canEdit = false, reason = "locked" }

-- Strictly booleans: these arrive from stored data and payloads, and a value of
-- the wrong type is a bug upstream, not a licence to open the panel.
local function isTrue(value: any): boolean
	return value == true
end

function TitleAccessDomain.evaluate(input: AccessInput?): AccessState
	if type(input) ~= "table" or not isTrue(input.selfServiceOn) then
		return LOCKED
	end

	-- A title with no recorded source is a legacy admin grant; only a title
	-- explicitly marked as self-made loses the shield.
	if isTrue(input.hasTitle) and input.fromAdmin ~= false then
		return { canEdit = true, reason = "admin" }
	end
	if isTrue(input.meetsLevel) then
		return { canEdit = true, reason = "level" }
	end
	if isTrue(input.meetsEvent) then
		return { canEdit = true, reason = "event" }
	end
	if isTrue(input.freeEnabled) and not isTrue(input.freeUsed) then
		return { canEdit = true, reason = "free" }
	end
	return LOCKED
end

-- True only when the write about to happen is the one the free slot paid for.
-- A player who qualifies by level, event or an admin grant keeps their slot.
function TitleAccessDomain.shouldSpendFree(state: AccessState?): boolean
	return type(state) == "table" and state.canEdit == true and state.reason == "free"
end

return TitleAccessDomain
