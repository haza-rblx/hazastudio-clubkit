--!strict
-- Lightweight per-character Attachment for Roblox bubble chat AdorneeName.
-- Event-driven only (no Heartbeat): schedule after OverheadUI apply.
-- Studio/admin tune: /bh | /height | /bubbleheight

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Config = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local ChatBubbleAdornee = {}

type PendingArgs = {
	gui: BillboardGui,
	wrapper: GuiObject?,
	overheadVisible: boolean,
}

type RuntimeOverrides = {
	HEIGHT_FACTOR: number?,
	EXTRA_STUDS: number?,
	NUDGE_STUDS: number?,
}

local lastStudsByUserId: { [number]: number } = {}
local scheduledByUserId: { [number]: boolean } = {}
local pendingArgsByUserId: { [number]: PendingArgs } = {}
local lastSyncByUserId: { [number]: PendingArgs } = {}
local runtimeOverrides: RuntimeOverrides = {}
local tuneCommandsBound = false

local function getCfg()
	local cfg = Config.ChatBubble
	if type(cfg) ~= "table" then
		return nil
	end
	return cfg
end

local function findListLayout(wrapper: GuiObject): UIListLayout?
	local direct = wrapper:FindFirstChildWhichIsA("UIListLayout")
	if direct and direct:IsA("UIListLayout") then
		return direct
	end
	local nested = wrapper:FindFirstChildWhichIsA("UIListLayout", true)
	if nested and nested:IsA("UIListLayout") then
		return nested
	end
	return nil
end

local function resolveHead(gui: BillboardGui): BasePart?
	local parent = gui.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end
	local adornee = gui.Adornee
	if adornee and adornee:IsA("BasePart") then
		return adornee
	end
	return nil
end

local function ensureAttachment(head: BasePart, name: string): Attachment
	local existing = head:FindFirstChild(name)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = head
	return attachment
end

local function effectiveNumber(overrideValue: number?, cfgValue: any, fallback: number): number
	if type(overrideValue) == "number" then
		return overrideValue
	end
	if type(cfgValue) == "number" then
		return cfgValue
	end
	return fallback
end

function ChatBubbleAdornee.getEffective(): {
	HEIGHT_FACTOR: number,
	EXTRA_STUDS: number,
	NUDGE_STUDS: number,
	ENABLED: boolean,
}
	local cfg = getCfg()
	return {
		HEIGHT_FACTOR = effectiveNumber(runtimeOverrides.HEIGHT_FACTOR, cfg and cfg.HEIGHT_FACTOR, 0.25),
		EXTRA_STUDS = effectiveNumber(runtimeOverrides.EXTRA_STUDS, cfg and cfg.EXTRA_STUDS, 0),
		NUDGE_STUDS = effectiveNumber(runtimeOverrides.NUDGE_STUDS, cfg and cfg.NUDGE_STUDS, 0),
		ENABLED = if cfg then cfg.ENABLED == true else false,
	}
end

local function measureStuds(gui: BillboardGui, wrapper: GuiObject?, overheadVisible: boolean): number
	local cfg = getCfg()
	local minStuds = if cfg and type(cfg.MIN_STUDS) == "number" then cfg.MIN_STUDS else 0.8
	local maxStuds = if cfg and type(cfg.MAX_STUDS) == "number" then cfg.MAX_STUDS else 6
	local extra = effectiveNumber(runtimeOverrides.EXTRA_STUDS, cfg and cfg.EXTRA_STUDS, 0)
	local pxToStuds = if cfg and type(cfg.PX_TO_STUDS) == "number" then cfg.PX_TO_STUDS else 0.018
	local heightFactor = effectiveNumber(runtimeOverrides.HEIGHT_FACTOR, cfg and cfg.HEIGHT_FACTOR, 0.25)
	local nudge = effectiveNumber(runtimeOverrides.NUDGE_STUDS, cfg and cfg.NUDGE_STUDS, 0)

	-- BillboardGui.StudsOffset is the center of the billboard, not the bottom.
	-- Top of stack ≈ center + (contentHeight * HEIGHT_FACTOR).
	local baseY = gui.StudsOffset.Y + gui.StudsOffsetWorldSpace.Y
	if not overheadVisible or not wrapper then
		return math.clamp(baseY + extra + nudge, minStuds, maxStuds)
	end

	local listLayout = findListLayout(wrapper)
	local contentY = if listLayout then listLayout.AbsoluteContentSize.Y else wrapper.AbsoluteSize.Y
	local absY = gui.AbsoluteSize.Y
	local sizeYStuds = gui.Size.Y.Scale
	local contentStuds: number
	if absY > 1 and sizeYStuds > 0 then
		contentStuds = (contentY / absY) * sizeYStuds
	else
		contentStuds = contentY * pxToStuds
	end

	return math.clamp(baseY + contentStuds * heightFactor + extra + nudge, minStuds, maxStuds)
end

local function applyNow(userId: number, gui: BillboardGui, wrapper: GuiObject?, overheadVisible: boolean, force: boolean?)
	local cfg = getCfg()
	if not cfg or cfg.ENABLED ~= true then
		return
	end
	if not gui.Parent then
		return
	end

	local head = resolveHead(gui)
	if not head then
		return
	end

	local name = if type(cfg.ADORNEE_NAME) == "string" and cfg.ADORNEE_NAME ~= ""
		then cfg.ADORNEE_NAME
		else "ClubKitChatBubble"
	local studs = measureStuds(gui, wrapper, overheadVisible)
	local skipDelta = if type(cfg.SKIP_DELTA_STUDS) == "number" then cfg.SKIP_DELTA_STUDS else 0.05
	local last = lastStudsByUserId[userId]
	if not force and last and math.abs(last - studs) < skipDelta then
		return
	end

	local attachment = ensureAttachment(head, name)
	attachment.Position = Vector3.new(0, studs, 0)
	lastStudsByUserId[userId] = studs
	lastSyncByUserId[userId] = {
		gui = gui,
		wrapper = wrapper,
		overheadVisible = overheadVisible,
	}
end

function ChatBubbleAdornee.scheduleSync(
	userId: number,
	gui: BillboardGui,
	wrapper: GuiObject?,
	overheadVisible: boolean
)
	local cfg = getCfg()
	if not cfg or cfg.ENABLED ~= true then
		return
	end
	if type(userId) ~= "number" then
		return
	end

	pendingArgsByUserId[userId] = {
		gui = gui,
		wrapper = wrapper,
		overheadVisible = overheadVisible,
	}
	if scheduledByUserId[userId] then
		return
	end
	scheduledByUserId[userId] = true
	-- Defer one frame so UIListLayout.AbsoluteContentSize settles after apply.
	task.defer(function()
		scheduledByUserId[userId] = nil
		local args = pendingArgsByUserId[userId]
		pendingArgsByUserId[userId] = nil
		if not args then
			return
		end
		applyNow(userId, args.gui, args.wrapper, args.overheadVisible, false)
	end)
end

function ChatBubbleAdornee.clear(userId: number)
	lastStudsByUserId[userId] = nil
	scheduledByUserId[userId] = nil
	pendingArgsByUserId[userId] = nil
	lastSyncByUserId[userId] = nil
end

function ChatBubbleAdornee.resyncAll()
	for userId, args in pairs(lastSyncByUserId) do
		lastStudsByUserId[userId] = nil
		if args.gui and args.gui.Parent then
			applyNow(userId, args.gui, args.wrapper, args.overheadVisible, true)
		else
			lastSyncByUserId[userId] = nil
		end
	end
end

function ChatBubbleAdornee.setOverride(key: string, value: number?)
	if key == "HEIGHT_FACTOR" then
		runtimeOverrides.HEIGHT_FACTOR = value
	elseif key == "EXTRA_STUDS" then
		runtimeOverrides.EXTRA_STUDS = value
	elseif key == "NUDGE_STUDS" then
		runtimeOverrides.NUDGE_STUDS = value
	end
	ChatBubbleAdornee.resyncAll()
end

function ChatBubbleAdornee.clearOverrides()
	runtimeOverrides.HEIGHT_FACTOR = nil
	runtimeOverrides.EXTRA_STUDS = nil
	runtimeOverrides.NUDGE_STUDS = nil
	ChatBubbleAdornee.resyncAll()
end

local function systemMessage(text: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = if channels then channels:FindFirstChild("RBXGeneral") else nil
	if general and general:IsA("TextChannel") then
		pcall(function()
			(general :: TextChannel):DisplaySystemMessage(text)
		end)
		return
	end
	print(text)
end

local function formatStatus(): string
	local e = ChatBubbleAdornee.getEffective()
	local localId = if Players.LocalPlayer then Players.LocalPlayer.UserId else nil
	local measured = if localId then lastStudsByUserId[localId] else nil
	return string.format(
		"[BubbleHeight] factor=%.3f extra=%.3f nudge=%.3f%s | /height -0.5 | /height factor 0.2 | /height reset",
		e.HEIGHT_FACTOR,
		e.EXTRA_STUDS,
		e.NUDGE_STUDS,
		if measured then string.format(" measuredY=%.2f", measured) else ""
	)
end

local function handleTuneCommand(_player: Player, unfilteredText: string)
	local raw = unfilteredText:match("^%s*(.-)%s*$") or ""
	-- Strip leading /alias
	local body = raw:gsub("^/%S+%s*", "")
	if body == "" then
		systemMessage(formatStatus())
		return
	end

	local lower = string.lower(body)
	if lower == "reset" or lower == "clear" then
		ChatBubbleAdornee.clearOverrides()
		systemMessage("[BubbleHeight] overrides cleared → " .. formatStatus())
		return
	end

	local key, numStr = body:match("^(%S+)%s+([%+%-]?%d*%.?%d+)%s*$")
	if key and numStr then
		local value = tonumber(numStr)
		if not value then
			systemMessage("[BubbleHeight] invalid number. " .. formatStatus())
			return
		end
		local keyLower = string.lower(key)
		if keyLower == "factor" or keyLower == "f" or keyLower == "h" then
			ChatBubbleAdornee.setOverride("HEIGHT_FACTOR", math.clamp(value, 0, 1.5))
			systemMessage("[BubbleHeight] HEIGHT_FACTOR set. " .. formatStatus())
			return
		end
		if keyLower == "nudge" or keyLower == "n" or keyLower == "offset" then
			ChatBubbleAdornee.setOverride("NUDGE_STUDS", value)
			systemMessage("[BubbleHeight] NUDGE_STUDS set. " .. formatStatus())
			return
		end
		if keyLower == "extra" or keyLower == "e" then
			ChatBubbleAdornee.setOverride("EXTRA_STUDS", value)
			systemMessage("[BubbleHeight] EXTRA_STUDS set. " .. formatStatus())
			return
		end
	end

	-- Bare number → NUDGE_STUDS (supports /height -0.5 / /height 0).
	-- Factor only via explicit: /height factor 0.25
	local bare = tonumber(body)
	if bare then
		ChatBubbleAdornee.setOverride("NUDGE_STUDS", bare)
		systemMessage("[BubbleHeight] NUDGE_STUDS set. " .. formatStatus())
		return
	end

	systemMessage("[BubbleHeight] usage: /height | /height -0.5 | /height factor 0.25 | /height reset")
end

function ChatBubbleAdornee.bindTuneCommands()
	if tuneCommandsBound then
		return
	end
	tuneCommandsBound = true

	local cfg = getCfg()
	if cfg and cfg.TUNE_COMMAND_ENABLED == false then
		return
	end

	local aliases = { "bh", "height", "bubbleheight" }
	for _, alias in ipairs(aliases) do
		local existing = TextChatService:FindFirstChild("ClubKitBubbleTune_" .. alias)
		local command: TextChatCommand
		if existing and existing:IsA("TextChatCommand") then
			command = existing
		else
			if existing then
				existing:Destroy()
			end
			local created = Instance.new("TextChatCommand")
			created.Name = "ClubKitBubbleTune_" .. alias
			created.PrimaryAlias = "/" .. alias
			created.Parent = TextChatService
			command = created
		end

		command.Triggered:Connect(function(source: TextSource, unfilteredText: string)
			local localPlayer = Players.LocalPlayer
			if not localPlayer or source.UserId ~= localPlayer.UserId then
				return
			end
			handleTuneCommand(localPlayer, unfilteredText)
		end)
	end
end

return ChatBubbleAdornee
