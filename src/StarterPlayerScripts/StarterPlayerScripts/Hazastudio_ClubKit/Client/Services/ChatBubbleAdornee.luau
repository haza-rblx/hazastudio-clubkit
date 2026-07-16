--!strict
-- Lightweight per-character Attachment for Roblox bubble chat AdorneeName.
-- Event-driven only (no Heartbeat): schedule after OverheadUI apply.

local Config = require(game.ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local ChatBubbleAdornee = {}

type PendingArgs = {
	gui: BillboardGui,
	wrapper: GuiObject?,
	overheadVisible: boolean,
}

local lastStudsByUserId: { [number]: number } = {}
local scheduledByUserId: { [number]: boolean } = {}
local pendingArgsByUserId: { [number]: PendingArgs } = {}

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

local function measureStuds(gui: BillboardGui, wrapper: GuiObject?, overheadVisible: boolean): number
	local cfg = getCfg()
	local minStuds = if cfg and type(cfg.MIN_STUDS) == "number" then cfg.MIN_STUDS else 0.8
	local maxStuds = if cfg and type(cfg.MAX_STUDS) == "number" then cfg.MAX_STUDS else 6
	local extra = if cfg and type(cfg.EXTRA_STUDS) == "number" then cfg.EXTRA_STUDS else 0.12
	local pxToStuds = if cfg and type(cfg.PX_TO_STUDS) == "number" then cfg.PX_TO_STUDS else 0.018
	local heightFactor = if cfg and type(cfg.HEIGHT_FACTOR) == "number" then cfg.HEIGHT_FACTOR else 0.5

	-- BillboardGui.StudsOffset is the center of the billboard, not the bottom.
	-- Top of stack ≈ center + (contentHeight * HEIGHT_FACTOR). Old formula used
	-- center + full height and floated the bubble roughly one stack too high.
	local baseY = gui.StudsOffset.Y + gui.StudsOffsetWorldSpace.Y
	if not overheadVisible or not wrapper then
		return math.clamp(baseY + extra, minStuds, maxStuds)
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

	return math.clamp(baseY + contentStuds * heightFactor + extra, minStuds, maxStuds)
end

local function applyNow(userId: number, gui: BillboardGui, wrapper: GuiObject?, overheadVisible: boolean)
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
	if last and math.abs(last - studs) < skipDelta then
		return
	end

	local attachment = ensureAttachment(head, name)
	attachment.Position = Vector3.new(0, studs, 0)
	lastStudsByUserId[userId] = studs
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
		applyNow(userId, args.gui, args.wrapper, args.overheadVisible)
	end)
end

function ChatBubbleAdornee.clear(userId: number)
	lastStudsByUserId[userId] = nil
	scheduledByUserId[userId] = nil
	pendingArgsByUserId[userId] = nil
end

return ChatBubbleAdornee
