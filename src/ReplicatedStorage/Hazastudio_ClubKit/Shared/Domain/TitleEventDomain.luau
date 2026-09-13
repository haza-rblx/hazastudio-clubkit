--!strict
-- Shared/Domain/TitleEventDomain.luau
-- Who qualifies for the Free Title event (ClubKitConfig.FreeTitleEvent).
--
-- The event is an *alternative* door to a custom title: meeting it unlocks the
-- self-service panel for a player who has not reached `CustomTitle.MinLevel`. It
-- never takes access away — a player already past MinLevel, or holding a title an
-- admin gave them, keeps it whatever this says.
--
-- Three axes can be required: level, Robux donated, Cash donated. **A threshold
-- above zero is what turns an axis on**, so there is no second list of switches to
-- keep in agreement with the numbers. `Mode` then says how the active axes
-- combine: "Any" (meet one) or "All" (meet every one), with "Disabled" as the off
-- switch.
--
-- Pure: no Roblox services and no Config require. The caller passes the buyer's
-- `ClubKitConfig.FreeTitleEvent` in, so the same decision runs on the server (the
-- authority), in the client card (to paint locked vs open) and in a headless
-- harness.

local TitleEventDomain = {}

export type EventConfig = {
	Mode: string?,
	RequiredLevel: number?,
	MinDonationRobux: number?,
	MinDonationCash: number?,
}

export type PlayerStats = {
	level: number?,
	robuxTotal: number?,
	cashTotal: number?,
}

export type Requirement = {
	-- "level" | "robux" | "cash"
	axis: string,
	requirement: number,
	progress: number,
	met: boolean,
}

export type EventState = {
	-- The buyer is running an event *and* configured something to require.
	active: boolean,
	-- "disabled" | "any" | "all". Never a raw buyer string.
	mode: string,
	-- Qualifies right now.
	met: boolean,
	-- Every configured axis, in a stable order, whether met or not.
	requirements: { Requirement },
}

local MODE_DISABLED = "disabled"
local MODE_ANY = "any"
local MODE_ALL = "all"

local AXIS_LEVEL = "level"
local AXIS_ROBUX = "robux"
local AXIS_CASH = "cash"

-- Order matters: it decides which single line the card shows when several
-- requirements are unmet, and it is the order a player most likely reads them in.
local AXES: { { axis: string, configKey: string, statKey: string } } = {
	{ axis = AXIS_LEVEL, configKey = "RequiredLevel", statKey = "level" },
	{ axis = AXIS_ROBUX, configKey = "MinDonationRobux", statKey = "robuxTotal" },
	{ axis = AXIS_CASH, configKey = "MinDonationCash", statKey = "cashTotal" },
}

local DISABLED_STATE: EventState = {
	active = false,
	mode = MODE_DISABLED,
	met = false,
	requirements = {},
}

-- Player stats only. Strictly numbers: this is a gate, so a value arriving as the
-- wrong type is a bug somewhere upstream and must read as "no progress" rather
-- than be coerced into a pass. NaN and negatives are refused for the same reason —
-- both would otherwise sail past a `>=` check.
local function progressValue(value: any): number
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return math.floor(value)
end

-- A threshold is what switches an axis on, so anything that is not a usable
-- positive number means "not required" rather than "required, with a default".
local function thresholdValue(value: any): number?
	local n = tonumber(value)
	if n == nil or n ~= n or n < 1 then
		return nil
	end
	return math.floor(n)
end

-- Buyer config is hand-edited: accept case and stray spaces, refuse anything else.
function TitleEventDomain.normalizeMode(raw: any): string
	if type(raw) ~= "string" then
		return MODE_DISABLED
	end
	local trimmed = string.lower(raw:match("^%s*(.-)%s*$") or "")
	if trimmed == MODE_ANY then
		return MODE_ANY
	elseif trimmed == MODE_ALL then
		return MODE_ALL
	end
	return MODE_DISABLED
end

function TitleEventDomain.evaluate(config: EventConfig?, stats: PlayerStats?): EventState
	local cfg: any = if type(config) == "table" then config else {}
	local mode = TitleEventDomain.normalizeMode(cfg.Mode)
	if mode == MODE_DISABLED then
		return DISABLED_STATE
	end

	local player: any = if type(stats) == "table" then stats else {}
	local requirements: { Requirement } = {}
	for _, axis in ipairs(AXES) do
		local threshold = thresholdValue(cfg[axis.configKey])
		if threshold then
			local progress = progressValue(player[axis.statKey])
			table.insert(requirements, {
				axis = axis.axis,
				requirement = threshold,
				progress = progress,
				met = progress >= threshold,
			})
		end
	end

	-- A mode with nothing configured is not an event, it is a typo. Reporting it as
	-- inactive keeps "All over an empty list" from vacuously unlocking everybody.
	if #requirements == 0 then
		return DISABLED_STATE
	end

	local met: boolean
	if mode == MODE_ALL then
		met = true
		for _, entry in ipairs(requirements) do
			if not entry.met then
				met = false
				break
			end
		end
	else
		met = false
		for _, entry in ipairs(requirements) do
			if entry.met then
				met = true
				break
			end
		end
	end

	return {
		active = true,
		mode = mode,
		met = met,
		requirements = requirements,
	}
end

-- Every way a locked player could get in, so a panel can spell them out.
--
-- A route is one alternative; entries inside a route must all be met. The plain
-- level gate (`CustomTitle.MinLevel`) is always a route, because the event only
-- ever adds doors. In "Any" each configured axis is its own route; in "All" the
-- event is a single compound route standing beside the level gate.
--
-- Single-axis routes on the same axis collapse to the cheapest one, so a place
-- whose event level sits under MinLevel prints "Lv 25" instead of the nonsense
-- "Lv 50, or Lv 25" — and an event threshold set *above* MinLevel disappears,
-- which is correct: it was never a way in.
function TitleEventDomain.describeRoutes(state: EventState?, minLevel: any): { { Requirement } }
	local gate = thresholdValue(minLevel) or 1
	local routes: { { Requirement } } = {
		{ { axis = AXIS_LEVEL, requirement = gate, progress = 0, met = false } },
	}

	if type(state) == "table" and state.active and type(state.requirements) == "table" then
		if state.mode == MODE_ALL then
			local compound: { Requirement } = {}
			for _, entry in ipairs(state.requirements) do
				table.insert(compound, entry)
			end
			if #compound > 0 then
				table.insert(routes, compound)
			end
		else
			for _, entry in ipairs(state.requirements) do
				table.insert(routes, { entry })
			end
		end
	end

	-- Collapse same-axis single-entry routes to their cheapest requirement, keeping
	-- the position of the first one seen.
	local result: { { Requirement } } = {}
	local singleIndexByAxis: { [string]: number } = {}
	for _, route in ipairs(routes) do
		if #route == 1 then
			local axis = route[1].axis
			local existing = singleIndexByAxis[axis]
			if existing then
				if route[1].requirement < result[existing][1].requirement then
					result[existing] = route
				end
			else
				table.insert(result, route)
				singleIndexByAxis[axis] = #result
			end
		else
			table.insert(result, route)
		end
	end
	return result
end

-- The one requirement worth showing on the card: the first the player has not
-- reached, in the order above. nil once they qualify.
function TitleEventDomain.nextUnmet(state: EventState?): Requirement?
	if type(state) ~= "table" or state.met or type(state.requirements) ~= "table" then
		return nil
	end
	for _, entry in ipairs(state.requirements) do
		if not entry.met then
			return entry
		end
	end
	return nil
end

return TitleEventDomain
