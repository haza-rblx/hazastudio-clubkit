--!strict
-- The "cinematic" loading style's screen (CONTEXT.md "Loading style"), built on a clone of the
-- owner's StarterGui.00-LoadingScreen — every look and name stays theirs and LoadingScreenUI drives
-- title, tips and bar exactly as in classic. Two parts:
--   Part 1 (skippable, while the kit boots): full-screen artwork (ClubKitConfig.Loading.ArtworkVideo
--     or ArtworkImage, else the experience thumbnail) under a dark fade; the template's stack moves
--     to the bottom-left and gains one event card (a clone of the Event tab's Basic/Image
--     announcement template, painted as the tab paints it, button hidden).
--   Part 2 (no input): dip to black, the template goes back to its own centred layout with only
--     logo + title, letterbox bars come in, and the character intro camera plays.

local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.Constants.Config)
local DailyQuestDomain = require(script.Parent.Parent.Domain.DailyQuestDomain)
local EventBoardRelay = require(script.Parent.Parent.Utils.EventBoardRelay)

local Story = Config.Loading.STORY
local cfg = Config.EventBoard

local CinematicLoadingView = {}
CinematicLoadingView.__index = CinematicLoadingView

local GUI_NAME = "00-LoadingScreen"
local MENU_GUI = "07-MenuGUI"
local SIDE = 64 -- px, part 1 stack from the left edge
local STACK_WIDTH = 470 -- px before the template's own UIScale
local TITLE_LINES = 2
-- EventCardKit.tintHeader: the header takes a little of the card's accent.
local HEADER_BASE = Color3.fromRGB(32, 32, 32)
local HEADER_MIX = 0.12
local MONTHS = {
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
}

-- ── Text helpers (same output as EventCardKit) ───────────────

local function spaced(text: string): string
	local letters = {}
	for _, code in utf8.codes(string.upper(text)) do
		table.insert(letters, utf8.char(code))
	end
	return table.concat(letters, " ")
end

local function momentText(unix: number): string
	local wib = math.floor(unix) + 7 * 3600
	local y, m, d = DailyQuestDomain.toCivil(wib // 86400)
	local minutes = (wib % 86400) // 60
	return string.format("%s %d, %d · %02d:%02d WIB", MONTHS[m], d, y, minutes // 60, minutes % 60)
end

local function publishedText(iso: any): string
	if type(iso) ~= "string" then
		return ""
	end
	local y, mo, d, h, mi, s = string.match(iso, "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):?(%d*)")
	if not y then
		return ""
	end
	local day = DailyQuestDomain.parseWibDate(string.format("%s-%s-%s", y, mo, d))
	if not day then
		return ""
	end
	return momentText(day * 86400 + (tonumber(h) :: number) * 3600 + (tonumber(mi) :: number) * 60 + (tonumber(s) or 0))
end

local function setText(root: Instance?, name: string, text: string)
	local label = root and root:FindFirstChild(name)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label.Text = text
	end
end

local function setVisible(root: Instance?, name: string, visible: boolean)
	local node = root and root:FindFirstChild(name)
	if node and node:IsA("GuiObject") then
		node.Visible = visible
	end
end

-- EventReminderUI.clampLines: trim to `lines`, ending in "…"; TextFits settles a frame later.
local function clampLines(label: TextLabel, lines: number)
	local full = label.Text
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(1, 0, 0, math.ceil(label.TextSize * 1.25) * lines)
	task.spawn(function()
		RunService.Heartbeat:Wait()
		if not label.Parent or label.TextFits then
			label.AutomaticSize = Enum.AutomaticSize.Y
			label.Size = UDim2.new(1, 0, 0, 0)
			return
		end
		local words = string.split(full, " ")
		local lo, hi = 1, #words
		while lo < hi do
			local mid = (lo + hi + 1) // 2
			label.Text = table.concat(words, " ", 1, mid) .. "…"
			RunService.Heartbeat:Wait()
			if not label.Parent then
				return
			end
			if label.TextFits then
				lo = mid
			else
				hi = mid - 1
			end
		end
		label.Text = table.concat(words, " ", 1, lo) .. "…"
	end)
end

-- The show-on-join post, else the newest post (countdowns last).
local function pickPost(state: { [string]: any }): { [string]: any }?
	local best = nil
	for _, post in ipairs(state.posts) do
		if type(post) ~= "table" then
			continue
		end
		if state.joinPostId ~= nil and post.id == state.joinPostId then
			return post
		end
		local isCountdown = post.kind == "countdown"
		local bestCountdown = best ~= nil and best.kind == "countdown"
		if
			best == nil
			or (bestCountdown and not isCountdown)
			or (isCountdown == bestCountdown and tostring(post.publishedAt or "") > tostring(best.publishedAt or ""))
		then
			best = post
		end
	end
	return best
end

-- ── Construction ─────────────────────────────────────────────

-- Every property part 1 changes on the template, so part 2 can put the owner's layout back.
type Saved = { inst: Instance, prop: string, value: any }

--- nil when the place has no 00-LoadingScreen template (the caller falls back to classic).
function CinematicLoadingView.create(): any?
	local template = StarterGui:WaitForChild(GUI_NAME, Config.Loading.TEMPLATE_WAIT_TIMEOUT)
	if not (template and template:IsA("ScreenGui")) then
		return nil
	end
	local self = setmetatable({}, CinematicLoadingView) :: any
	local root = template:Clone()
	root.Enabled = false
	self.root = root
	self._bar = Story.LETTERBOX_SCALE
	self._saved = {} :: { Saved }
	self._unsubscribe = nil :: (() -> ())?
	self._card = nil :: GuiObject?
	self._cardPostId = nil :: any
	self._stopped = false

	local wrapper = root:FindFirstChild("ContentWrapper")
	local content = wrapper and wrapper:FindFirstChild("Content")
	self._wrapper = if wrapper and wrapper:IsA("GuiObject") then wrapper else nil
	self._content = if content and content:IsA("GuiObject") then content else nil
	if self._wrapper then
		self._wrapper.ZIndex = math.max(self._wrapper.ZIndex, 3)
	end

	-- Part 1 backdrop: artwork + dark fade, under the template's content.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Part1Backdrop"
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = root
	local video = Config.Loading.ARTWORK_VIDEO
	local art: GuiObject
	if type(video) == "string" and video ~= "" then
		local frame = Instance.new("VideoFrame")
		frame.Video = video
		frame.Looped = true
		frame.Volume = 0
		art = frame
	else
		local image = Instance.new("ImageLabel")
		local artwork = Config.Loading.ARTWORK_IMAGE
		image.Image = if type(artwork) == "string" and artwork ~= ""
			then artwork
			else string.format("rbxthumb://type=GameThumbnail&id=%d&w=768&h=432", game.PlaceId)
		image.ScaleType = Enum.ScaleType.Crop
		art = image
	end
	art.Name = "Artwork"
	art.BackgroundTransparency = 1
	art.Size = UDim2.fromScale(1, 1)
	art.Parent = backdrop
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.Parent = backdrop
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	gradient.Parent = shade
	self._backdrop = backdrop
	self._art = art

	local function letterbox(name: string, bottom: boolean): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0, if bottom then 1 else 0)
		frame.Position = UDim2.fromScale(0, if bottom then 1 else 0)
		frame.Size = UDim2.new(1, 0, 0, 0)
		frame.ZIndex = 2
		frame.Parent = root
		return frame
	end
	self._top = letterbox("LetterboxTop", false)
	self._bottom = letterbox("LetterboxBottom", true)

	-- Dip-to-black between the parts, above everything.
	local dip = Instance.new("Frame")
	dip.Name = "Dip"
	dip.BackgroundColor3 = Color3.new(0, 0, 0)
	dip.BackgroundTransparency = 1
	dip.BorderSizePixel = 0
	dip.Size = UDim2.fromScale(1, 1)
	dip.ZIndex = 60
	dip.Parent = root
	self._dip = dip

	self:_applyPart1Layout()
	return self
end

function CinematicLoadingView:_set(inst: Instance?, prop: string, value: any)
	if not inst then
		return
	end
	table.insert(self._saved, { inst = inst, prop = prop, value = (inst :: any)[prop] })
	;(inst :: any)[prop] = value
end

function CinematicLoadingView:_find(name: string): Instance?
	return if self._content then self._content:FindFirstChild(name) else nil
end

-- Template stack → bottom-left column, left-aligned text, full-width rows.
function CinematicLoadingView:_applyPart1Layout()
	local wrapper, content = self._wrapper, self._content
	if not (wrapper and content) then
		return
	end
	self:_set(wrapper, "AnchorPoint", Vector2.new(0, 1))
	self:_set(wrapper, "Position", UDim2.new(0, SIDE, 1, 0))
	self:_set(wrapper, "Size", UDim2.new(0, STACK_WIDTH, wrapper.Size.Y.Scale, wrapper.Size.Y.Offset))
	self:_set(content, "AnchorPoint", Vector2.new(0, 1))
	self:_set(content, "Position", UDim2.fromScale(0, 1))
	local list = content:FindFirstChildOfClass("UIListLayout")
	self:_set(list, "HorizontalAlignment", Enum.HorizontalAlignment.Left)
	for _, name in ipairs({ "TitleWrapper", "TipsWrapper" }) do
		local row = self:_find(name)
		if row and row:IsA("GuiObject") then
			self:_set(row, "Size", UDim2.new(1, 0, row.Size.Y.Scale, row.Size.Y.Offset))
			local label = row:FindFirstChildWhichIsA("TextLabel")
			if label then
				self:_set(label, "AnchorPoint", Vector2.new(0, 0))
				self:_set(label, "Position", UDim2.new())
				self:_set(label, "TextXAlignment", Enum.TextXAlignment.Left)
			end
		end
	end
	local logo = self:_find("LogoWrapper")
	local logoImage = logo and logo:FindFirstChildWhichIsA("ImageLabel")
	if logoImage then
		self:_set(logoImage, "AnchorPoint", Vector2.new(0, 1))
		self:_set(logoImage, "Position", UDim2.fromScale(0, 1))
	end
	local bar = self:_find("LoadingBarWrapper")
	self:_set(bar, "Size", UDim2.new(1, 0, 0, 5))
	-- The card sits between the title and the tips.
	local tips = self:_find("TipsWrapper")
	if tips and tips:IsA("GuiObject") then
		self:_set(tips, "LayoutOrder", 3)
	end
	local slot = Instance.new("Frame")
	slot.Name = "EventCardSlot"
	slot.BackgroundTransparency = 1
	slot.LayoutOrder = 2
	slot.Size = UDim2.fromScale(1, 0)
	slot.AutomaticSize = Enum.AutomaticSize.Y
	slot.Visible = false
	slot.Parent = content
	self._slot = slot
end

function CinematicLoadingView:_restoreLayout()
	for i = #self._saved, 1, -1 do
		local entry = self._saved[i]
		pcall(function()
			(entry.inst :: any)[entry.prop] = entry.value
		end)
	end
	self._saved = {}
end

-- ── Event card ───────────────────────────────────────────────

local function findCardTemplate(name: string): GuiObject?
	local menu = StarterGui:FindFirstChild(MENU_GUI)
	local template = menu and menu:FindFirstChild(name, true)
	if template and template:IsA("GuiObject") then
		return template
	end
	return nil
end

function CinematicLoadingView:_showPost(post: { [string]: any })
	if self._stopped or self._cardPostId == post.id then
		return
	end
	local image = if type(post.imageAssetId) == "string" then post.imageAssetId else ""
	local isCountdown = post.kind == "countdown" and type(post.startsAt) == "number"
	local template = (image ~= "" and findCardTemplate(cfg.TEMPLATES.IMAGE)) or findCardTemplate(cfg.TEMPLATES.BASIC)
	if not template then
		return
	end
	if self._card then
		self._card:Destroy()
	end
	local card = template:Clone()
	card.Name = "EventCard"
	card.Visible = true
	card.Position = UDim2.new()
	card.Size = UDim2.new(1, 0, 0, 0)
	local header = card:FindFirstChild("Header")
	setText(header, "Label", if isCountdown then cfg.HEADER_LABELS.countdown else cfg.HEADER_LABELS.announcement)
	local body = card:FindFirstChild("Body")
	local category = body and body:FindFirstChild("Category")
	if header and header:IsA("GuiObject") and category and category:IsA("TextLabel") then
		header.BackgroundColor3 = HEADER_BASE:Lerp(category.TextColor3, HEADER_MIX)
	end
	local categoryText = if type(post.category) == "string" then post.category else ""
	setText(body, "Category", if categoryText ~= "" then spaced(categoryText) else "")
	setVisible(body, "Category", categoryText ~= "")
	setText(body, "Title", if type(post.title) == "string" then post.title else "")
	setText(body, "Date", if isCountdown then momentText(post.startsAt) else publishedText(post.publishedAt))
	local text = if type(post.body) == "string" and not isCountdown then post.body else ""
	setText(body, "Text", text)
	setVisible(body, "Text", text ~= "")
	local banner = body and body:FindFirstChild("Banner")
	if banner and banner:IsA("ImageLabel") then
		banner.Image = if image ~= "" then "rbxassetid://" .. image else ""
		banner.ScaleType = Enum.ScaleType.Crop
		banner.Visible = image ~= ""
	end
	-- No button during loading (a tap skips), and no gap left where it was.
	setVisible(body, "ButtonSlot", false)
	setVisible(body, "Gap10", false)
	card.Parent = self._slot
	local title = body and body:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		clampLines(title, TITLE_LINES)
	end
	local textLabel = body and body:FindFirstChild("Text")
	if text ~= "" and textLabel and textLabel:IsA("TextLabel") then
		clampLines(textLabel, Story.CARD_TEXT_LINES)
	end
	self._slot.Visible = true
	self._card = card
	self._cardPostId = post.id
end

-- ── Public ───────────────────────────────────────────────────

--- Phones: part 1 stack closer to the left edge (the bootstrap shrinks the template's UIScale).
--- Writes the live value only, so part 2's restore still brings back the owner's layout.
function CinematicLoadingView:applyPhoneLayout(side: number)
	local wrapper = self._wrapper
	if wrapper then
		local position = wrapper.Position
		wrapper.Position = UDim2.new(position.X.Scale, side, position.Y.Scale, position.Y.Offset)
	end
end

--- Part 1 on screen: artwork plays, the card appears once a board snapshot is in.
function CinematicLoadingView:startPart1()
	if self._art:IsA("VideoFrame") then
		pcall(function()
			(self._art :: VideoFrame):Play()
		end)
	end
	EventBoardRelay.start()
	self._unsubscribe = EventBoardRelay.subscribe(function(state)
		local post = pickPost(state)
		if post then
			self:_showPost(post)
		end
	end)
end

--- Part 1 → part 2: dip to black, swap to the owner's centred layout (logo + title only) with
--- letterbox bars, call `atBlack` (camera + grade start there), then lift the dip.
function CinematicLoadingView:enterPart2(atBlack: () -> ())
	if self._unsubscribe then
		self._unsubscribe()
		self._unsubscribe = nil
	end
	local half = Story.PART1_FADE / 2
	local toBlack = TweenService:Create(self._dip, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 0,
	})
	toBlack:Play()
	task.delay(half, function()
		if self._stopped then
			return
		end
		if self._art:IsA("VideoFrame") then
			pcall(function()
				(self._art :: VideoFrame):Pause()
			end)
		end
		self._backdrop.Visible = false
		if self._slot then
			self._slot.Visible = false
		end
		self:_restoreLayout()
		for _, name in ipairs({ "TipsWrapper", "LoadingBarWrapper", "Separator" }) do
			local row = self:_find(name)
			if row and row:IsA("GuiObject") then
				row.Visible = false
			end
		end
		self._top.Size = UDim2.new(1, 0, self._bar, 0)
		self._bottom.Size = UDim2.new(1, 0, self._bar, 0)
		if self._wrapper then
			-- Logo + title sit just above the bottom bar.
			local rest = self._wrapper.Position
			self._wrapper.Position = UDim2.new(rest.X, UDim.new(rest.Y.Scale - self._bar, rest.Y.Offset))
			local padding = self._content and self._content:FindFirstChildOfClass("UIPadding")
			if padding then
				padding.PaddingBottom = UDim.new(0, Story.PART2_BOTTOM_GAP)
			end
		end
		atBlack()
		TweenService:Create(self._dip, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end)
end

--- End of part 2: bars open and logo + title fade while the camera lands on gameplay.
function CinematicLoadingView:playReveal(duration: number)
	self:stop()
	local info = TweenInfo.new(math.max(duration, 0.05), Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(self._top, info, { Size = UDim2.new(1, 0, 0, 0) }):Play()
	TweenService:Create(self._bottom, info, { Size = UDim2.new(1, 0, 0, 0) }):Play()
	-- No black dip any more (the orbit hands over in the open), so the title must fade itself.
	if self._wrapper then
		for _, node in ipairs(self._wrapper:GetDescendants()) do
			if node:IsA("TextLabel") or node:IsA("TextButton") then
				TweenService:Create(node, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			elseif node:IsA("ImageLabel") or node:IsA("ImageButton") then
				TweenService:Create(node, info, { ImageTransparency = 1 }):Play()
			elseif node:IsA("UIStroke") then
				TweenService:Create(node, info, { Transparency = 1 }):Play()
			end
		end
	end
end

function CinematicLoadingView:stop()
	self._stopped = true
	if self._unsubscribe then
		self._unsubscribe()
		self._unsubscribe = nil
	end
end

function CinematicLoadingView:destroy()
	self:stop()
end

return CinematicLoadingView
