--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)

local EmoteListPanel = {}
EmoteListPanel.__index = EmoteListPanel

function EmoteListPanel.new(deps: {
	mainFrame: Frame,
	containerList: ScrollingFrame,
	template: Frame,
	searchBox: TextBox,
	controlBtns: { dance: GuiButton?, pose: GuiButton?, fav: GuiButton? },
	speedFrame: Frame,
})
	local self = setmetatable({} :: any, EmoteListPanel) :: any
	self.mainFrame = deps.mainFrame
	self.containerList = deps.containerList
	self.template = deps.template
	self.searchBox = deps.searchBox
	self.controlBtns = deps.controlBtns
	self.speedFrame = deps.speedFrame

	self._emoteSelected = nil
	self._favoriteToggled = nil
	self._speedChanged = nil
	self._activeRows = {}
	-- Rows are destroyed and rebuilt on every search keystroke; bindPress also connects to
	-- UserInputService, which would outlive the row, so those connections are owned here.
	self._rowMotionConns = {}
	self._lastRenderEmpty = false
	self._danceAnims = {}
	self._poseAnims = {}
	self._favoritedAnims = {}
	self._currentCategory = "Dance"
	self._currentSpeed = Config.Sync.DEFAULT_SPEED
	self._searchQuery = ""
	self._dragConn = nil
	self._connections = {}
	self._lastEmoteSelectionAt = 0
	self._lastSelectedAnimationName = nil
	self._defaultSearchPlaceholder = self.searchBox.PlaceholderText ~= "" and self.searchBox.PlaceholderText or "Search dance or pose..."
	self._preparingSearchPlaceholder = "Preparing dances..."

	table.insert(self._connections, self.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		self._searchQuery = string.lower(self.searchBox.Text)
		self:updateDisplay()
	end))

	local function bindCategoryButton(button: GuiButton?, category: string)
		if not button then
			return
		end
		local control = button :: GuiButton
		UIMotion.bindPress(control)
		UIMotion.bindHover(control)
		table.insert(self._connections, control.Activated:Connect(function()
			UIMotion.pop(UIMotion.scaleTargetOf(control))
			self:setCategory(category)
		end))
	end

	bindCategoryButton(self.controlBtns.dance, "Dance")
	bindCategoryButton(self.controlBtns.pose, "Pose")
	bindCategoryButton(self.controlBtns.fav, "Favorite")

	self:_setupSpeedSlider()
	return self
end

function EmoteListPanel:setPreparingState(isPreparing: boolean)
	self.searchBox.PlaceholderText = isPreparing and self._preparingSearchPlaceholder or self._defaultSearchPlaceholder
end

function EmoteListPanel:_setupSpeedSlider()
	local speedBar = self.speedFrame:FindFirstChild("speedBar")
	local speedPosition = speedBar and speedBar:FindFirstChild("speedPosition")
	local speedLabel = self.speedFrame:FindFirstChild("TextLabel")
	if not speedBar or not speedPosition or not speedPosition:IsA("Frame") then
		return
	end

	local dragButton = speedPosition:FindFirstChild("Button")
	if not dragButton or not dragButton:IsA("GuiButton") then
		return
	end

	local speedBarGui = (speedBar :: any) :: GuiObject
	local function apply(mouseX: number)
		local ratio = math.clamp((mouseX - speedBarGui.AbsolutePosition.X) / math.max(speedBarGui.AbsoluteSize.X, 1), 0, 1)
		local speed = Config.Sync.MIN_SPEED + ratio * (Config.Sync.MAX_SPEED - Config.Sync.MIN_SPEED)
		self._currentSpeed = speed
		speedPosition.Position = UDim2.new(ratio, -12, 0, -4)
		if speedLabel and speedLabel:IsA("TextLabel") then
			speedLabel.Text = string.format("Speed %.1fx", speed)
		end
		if self._speedChanged then
			self._speedChanged(speed)
		end
	end

	table.insert(self._connections, dragButton.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
	if self._dragConn then
		(self._dragConn :: RBXScriptConnection):Disconnect()
	end
		self._dragConn = RunService.RenderStepped:Connect(function()
			apply(UserInputService:GetMouseLocation().X)
		end)
	end))

	table.insert(self._connections, dragButton.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
	if self._dragConn then
		(self._dragConn :: RBXScriptConnection):Disconnect()
		local panelSelf = self :: any
		panelSelf._dragConn = nil
	end
	end))

	local ratio = (self._currentSpeed - Config.Sync.MIN_SPEED) / (Config.Sync.MAX_SPEED - Config.Sync.MIN_SPEED)
	apply(speedBarGui.AbsolutePosition.X + speedBarGui.AbsoluteSize.X * ratio)
end

function EmoteListPanel:setCategory(category: string)
	self._currentCategory = category
	self:updateDisplay()
end

function EmoteListPanel:setEmotes(danceAnims: { Animation }, poseAnims: { Animation })
	self._danceAnims = danceAnims
	self._poseAnims = poseAnims
	self:updateDisplay()
end

function EmoteListPanel:setFavorites(favorites: { [string]: boolean })
	self._favoritedAnims = favorites
	self:updateDisplay()
end

function EmoteListPanel:updateDisplay()
	for _, connection in ipairs(self._rowMotionConns) do
		connection:Disconnect()
	end
	self._rowMotionConns = {}
	for _, row in ipairs(self._activeRows) do
		row:Destroy()
	end
	self._activeRows = {}

	local function bindRowFeel(button: GuiButton)
		for _, connection in ipairs(UIMotion.bindPress(button)) do
			table.insert(self._rowMotionConns, connection)
		end
		for _, connection in ipairs(UIMotion.bindHover(button)) do
			table.insert(self._rowMotionConns, connection)
		end
	end

	local source = {}
	if self._currentCategory == "Pose" then
		source = self._poseAnims
	elseif self._currentCategory == "Favorite" then
		for _, anim in ipairs(self._danceAnims) do
			if self._favoritedAnims[anim.Name] then
				table.insert(source, anim)
			end
		end
		for _, anim in ipairs(self._poseAnims) do
			if self._favoritedAnims[anim.Name] then
				table.insert(source, anim)
			end
		end
	else
		source = self._danceAnims
	end

	for index, animation in ipairs(source) do
		if self._searchQuery == "" or string.find(string.lower(animation.Name), self._searchQuery, 1, true) then
			local row = self.template:Clone()
			row.Name = animation.Name
			row.LayoutOrder = index
			row.Visible = true

			local mainButton = row:FindFirstChild("TemplateBtn")
			if mainButton and mainButton:IsA("TextButton") then
				mainButton.Text = animation.Name
				bindRowFeel(mainButton)
				mainButton.Activated:Connect(function()
					local now = os.clock()
					-- Wutwut: same-emote spam must beat WUTWUT_CHAIN_WINDOW (0.45s).
					-- SWITCH_INPUT_COOLDOWN (often 0.55) would make restarts unreachable.
					local cooldown = Config.Sync.SWITCH_INPUT_COOLDOWN or 0.15
					if Config.Sync.WUTWUT_ENABLED == true and animation.Name == self._lastSelectedAnimationName then
						cooldown = Config.Sync.WUTWUT_CLIENT_MIN_FIRE_INTERVAL or 0.04
					end
					if now - self._lastEmoteSelectionAt < cooldown then
						return
					end
					self._lastEmoteSelectionAt = now
					self._lastSelectedAnimationName = animation.Name
					-- Row is laid out by containerList, so the squash lands on the label.
					UIMotion.pop(UIMotion.scaleTargetOf(mainButton))
					if self._emoteSelected then
						self._emoteSelected(animation)
					end
				end)
			end

			local favoriteButton = row:FindFirstChild("FavoriteBtn")
			if favoriteButton and favoriteButton:IsA("GuiButton") then
					(favoriteButton :: any).Text = self._favoritedAnims[animation.Name] and "*" or "o"
				bindRowFeel(favoriteButton)
				favoriteButton.Activated:Connect(function()
					UIMotion.pop(UIMotion.scaleTargetOf(favoriteButton))
					if self._favoriteToggled then
						self._favoriteToggled(animation.Name)
					end
				end)
			end

			row.Parent = self.containerList
			table.insert(self._activeRows, row)
		end
	end

	-- Every call here is a real re-render (search, category, favourites, emote load), never a
	-- scroll: the rows above were just cloned, so the cascade cannot fire on scrolling.
	local bases: { [GuiObject]: number } = {}
	for _, row in ipairs(self._activeRows) do
		local elements: { GuiObject } = { row }
		for _, descendant in ipairs(row:GetDescendants()) do
			if descendant:IsA("GuiObject") then
				table.insert(elements, descendant)
			end
		end
		UIMotion.captureBases(elements, bases)
	end
	UIMotion.stagger(self._activeRows, bases)

	local isEmpty = #self._activeRows == 0
	if isEmpty and not self._lastRenderEmpty and self._searchQuery ~= "" then
		UIMotion.wiggle(self.searchBox, 5)
	end
	self._lastRenderEmpty = isEmpty
end

function EmoteListPanel:bindEmoteSelected(callback: (Animation) -> ())
	self._emoteSelected = callback
end

function EmoteListPanel:bindFavoriteToggle(callback: (string) -> ())
	self._favoriteToggled = callback
end

function EmoteListPanel:bindSpeedChanged(callback: (number) -> ())
	self._speedChanged = callback
end

function EmoteListPanel:destroy()
	-- Stop the drag RenderStepped loop in case the panel is destroyed mid-drag.
	if self._dragConn then
		(self._dragConn :: RBXScriptConnection):Disconnect()
		self._dragConn = nil
	end
	-- Disconnect all tracked connections: searchBox, category buttons, slider inputs.
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	table.clear(self._connections)
	-- Disconnect per-row UIMotion connections.
	for _, conn in ipairs(self._rowMotionConns) do
		conn:Disconnect()
	end
	table.clear(self._rowMotionConns)
	-- Destroy all cloned rows.
	for _, row in ipairs(self._activeRows) do
		row:Destroy()
	end
	table.clear(self._activeRows)
	-- Clear callbacks to avoid holding references after destroy.
	self._emoteSelected = nil
	self._favoriteToggled = nil
	self._speedChanged = nil
end

return EmoteListPanel
