--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

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
	self._danceAnims = {}
	self._poseAnims = {}
	self._favoritedAnims = {}
	self._currentCategory = "Dance"
	self._currentSpeed = Config.Sync.DEFAULT_SPEED
	self._searchQuery = ""
	self._dragConn = nil
	self._lastEmoteSelectionAt = 0
	self._lastSelectedAnimationName = nil
	self._defaultSearchPlaceholder = self.searchBox.PlaceholderText ~= "" and self.searchBox.PlaceholderText or "Search dance or pose..."
	self._preparingSearchPlaceholder = "Preparing dances..."

	self.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		self._searchQuery = string.lower(self.searchBox.Text)
		self:updateDisplay()
	end)

	if self.controlBtns.dance then
		self.controlBtns.dance.Activated:Connect(function()
			self:setCategory("Dance")
		end)
	end
	if self.controlBtns.pose then
		self.controlBtns.pose.Activated:Connect(function()
			self:setCategory("Pose")
		end)
	end
	if self.controlBtns.fav then
		self.controlBtns.fav.Activated:Connect(function()
			self:setCategory("Favorite")
		end)
	end

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

	dragButton.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
	if self._dragConn then
		(self._dragConn :: RBXScriptConnection):Disconnect()
	end
		self._dragConn = RunService.RenderStepped:Connect(function()
			apply(UserInputService:GetMouseLocation().X)
		end)
	end)

	dragButton.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
	if self._dragConn then
		(self._dragConn :: RBXScriptConnection):Disconnect()
		local panelSelf = self :: any
		panelSelf._dragConn = nil
	end
	end)

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
	for _, row in ipairs(self._activeRows) do
		row:Destroy()
	end
	self._activeRows = {}

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
				mainButton.Activated:Connect(function()
					local now = os.clock()
					if now - self._lastEmoteSelectionAt < (Config.Sync.SWITCH_INPUT_COOLDOWN or 0.15) then
						return
					end
					self._lastEmoteSelectionAt = now
					self._lastSelectedAnimationName = animation.Name
					if self._emoteSelected then
						self._emoteSelected(animation)
					end
				end)
			end

			local favoriteButton = row:FindFirstChild("FavoriteBtn")
			if favoriteButton and favoriteButton:IsA("GuiButton") then
					(favoriteButton :: any).Text = self._favoritedAnims[animation.Name] and "*" or "o"
				favoriteButton.Activated:Connect(function()
					if self._favoriteToggled then
						self._favoriteToggled(animation.Name)
					end
				end)
			end

			row.Parent = self.containerList
			table.insert(self._activeRows, row)
		end
	end
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

return EmoteListPanel
