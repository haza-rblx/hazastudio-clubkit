--!strict
-- Maps payload.boardStates → loading overlay message cycles for boards/posters.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

export type DisplayState = "ready" | "empty" | "not_configured" | "error"

local LeaderboardDisplayState = {}

local function hasEntries(entries: any): boolean
	if type(entries) ~= "table" then
		return false
	end
	for _, entry in ipairs(entries) do
		if entry ~= nil then
			return true
		end
	end
	for _, entry in pairs(entries) do
		if entry ~= nil then
			return true
		end
	end
	return false
end

local function normalizeLoadingText(message: string): string
	return (message:gsub("%.+$", ""):gsub("%s+$", ""))
end

local function resolveMessageCycle(primary: string?, cycles: { string }?): { string }
	local result: { string } = {}
	local seen: { [string]: boolean } = {}

	local function add(message: string?)
		if type(message) ~= "string" then
			return
		end
		local cleaned = normalizeLoadingText(message)
		if cleaned == "" or seen[cleaned] then
			return
		end
		seen[cleaned] = true
		table.insert(result, cleaned)
	end

	add(primary)
	if type(cycles) == "table" then
		for _, message in ipairs(cycles) do
			add(message)
		end
	end

	if #result == 0 then
		add(Config.Leaderboards.DEFAULT_LOADING_MESSAGE or "Loading leaderboard")
	end

	return result
end

local function readStateTable(group: string, dataKey: string): (string?, { string }?)
	local messages = Config.Leaderboards.EMPTY_STATE_MESSAGES
	local cycles = Config.Leaderboards.EMPTY_STATE_CYCLES
	if type(messages) ~= "table" or type(messages[group]) ~= "table" then
		return nil, nil
	end
	local primary = messages[group][dataKey]
	local cycle = if type(cycles) == "table" and type(cycles[group]) == "table" then cycles[group][dataKey] else nil
	return primary, cycle
end

function LeaderboardDisplayState.getBoardState(payload: any, dataKey: string, entries: any?): DisplayState
	if hasEntries(entries) then
		return "ready"
	end
	local states = if type(payload) == "table" then payload.boardStates else nil
	local state = if type(states) == "table" then states[dataKey] else nil
	if state == "not_configured" or state == "empty" or state == "error" or state == "ready" then
		return state
	end
	if type(entries) ~= "table" then
		return "error"
	end
	return "empty"
end

function LeaderboardDisplayState.getBoardMessageCycle(dataKey: string, state: DisplayState): { string }
	if state == "not_configured" then
		local messages = Config.Leaderboards.NOT_CONFIGURED_MESSAGES
		local cycles = Config.Leaderboards.NOT_CONFIGURED_CYCLES
		local primary = if type(messages) == "table" and type(messages.board) == "table"
			then messages.board[dataKey]
			else nil
		local cycle = if type(cycles) == "table" and type(cycles.board) == "table" then cycles.board[dataKey] else nil
		return resolveMessageCycle(primary or "API not configured yet", cycle)
	end

	if state == "error" then
		local messages = Config.Leaderboards.ERROR_STATE_MESSAGES
		local cycles = Config.Leaderboards.ERROR_STATE_CYCLES
		local boardMessages = if type(messages) == "table" then messages.board else nil
		local primary = if type(boardMessages) == "table" then boardMessages[dataKey] or boardMessages.default else nil
		local boardCycles = if type(cycles) == "table" and type(cycles.board) == "table" then cycles.board[dataKey] else nil
		return resolveMessageCycle(primary or "Could not load leaderboard", boardCycles)
	end

	if state == "empty" and dataKey == "saweria" then
		local waitingMessages = Config.Leaderboards.SAWERIA_WAITING_MESSAGES
		local waitingCycles = Config.Leaderboards.SAWERIA_WAITING_CYCLES
		local primary = if type(waitingMessages) == "table" then waitingMessages.board else nil
		local cycle = if type(waitingCycles) == "table" then waitingCycles.board else nil
		return resolveMessageCycle(primary, cycle)
	end

	local primary, cycle = readStateTable("board", dataKey)
	if primary then
		return resolveMessageCycle(primary, cycle)
	end

	return resolveMessageCycle("No data yet", { "Check back later" })
end

function LeaderboardDisplayState.getPosterMessageCycle(dataKey: string, state: DisplayState): { string }
	if state == "not_configured" then
		local messages = Config.Leaderboards.NOT_CONFIGURED_MESSAGES
		local cycles = Config.Leaderboards.NOT_CONFIGURED_CYCLES
		local primary = if type(messages) == "table" and type(messages.poster) == "table"
			then messages.poster[dataKey]
			else nil
		local cycle = if type(cycles) == "table" and type(cycles.poster) == "table" then cycles.poster[dataKey] else nil
		return resolveMessageCycle(primary or "API not configured yet", cycle)
	end

	if state == "error" then
		local messages = Config.Leaderboards.ERROR_STATE_MESSAGES
		local cycles = Config.Leaderboards.ERROR_STATE_CYCLES
		local posterMessages = if type(messages) == "table" then messages.poster else nil
		local primary = if type(posterMessages) == "table" then posterMessages[dataKey] or posterMessages.default else nil
		local posterCycles = if type(cycles) == "table" and type(cycles.poster) == "table" then cycles.poster[dataKey] else nil
		return resolveMessageCycle(primary or "Could not load poster", posterCycles)
	end

	if state == "empty" and dataKey == "saweria" then
		local waitingMessages = Config.Leaderboards.SAWERIA_WAITING_MESSAGES
		local waitingCycles = Config.Leaderboards.SAWERIA_WAITING_CYCLES
		local primary = if type(waitingMessages) == "table" then waitingMessages.poster else nil
		local cycle = if type(waitingCycles) == "table" then waitingCycles.poster else nil
		return resolveMessageCycle(primary, cycle)
	end

	local primary, cycle = readStateTable("poster", dataKey)
	if primary then
		return resolveMessageCycle(primary, cycle)
	end

	return resolveMessageCycle(
		Config.Leaderboards.DEFAULT_POSTER_LOADING_MESSAGE or "Loading poster",
		{ "Almost ready" }
	)
end

return LeaderboardDisplayState
