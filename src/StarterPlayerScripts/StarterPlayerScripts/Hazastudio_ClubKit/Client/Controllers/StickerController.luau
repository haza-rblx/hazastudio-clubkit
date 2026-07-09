--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local StickerController = {}
StickerController.__index = StickerController

local PANEL_TWEEN_INFO =
	TweenInfo.new(Config.Sticker.PANEL_TWEEN_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local MODAL_TWEEN_INFO = TweenInfo.new(Config.Sticker.MODAL_TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

type StickerRefs = {
	gui: ScreenGui,
	sidePanel: GuiObject,
	list: ScrollingFrame,
	template: ImageButton,
	uploadButton: ImageButton,
	modal: Frame,
	textBox: TextBox,
	previewImage: ImageLabel?,
	addButton: TextButton,
	cancelButton: TextButton,
}

local function normalizeImage(value: any): string
	if type(value) ~= "string" then
		return ""
	end

	local trimmed = value:match("^%s*(.-)%s*$") or ""
	local numericId = trimmed:match("^%d+$")
	if numericId and numericId ~= "0" then
		return "rbxassetid://" .. numericId
	end

	local assetId = trimmed:match("^rbxassetid://(%d+)$")
	if assetId and assetId ~= "0" then
		return "rbxassetid://" .. assetId
	end

	return ""
end

local function findChild(parent: Instance, name: string, className: string): Instance?
	local child = parent:FindFirstChild(name, true)
	if child and child:IsA(className) then
		return child
	end
	return nil
end

local function setSidePanelTransparency(panel: GuiObject, value: number): ()
	if panel:IsA("CanvasGroup") then
		(panel :: CanvasGroup).GroupTransparency = value
	end
end

local function findChildAnyClass(parent: Instance, name: string, ...: string): Instance?
	local child = parent:FindFirstChild(name, true)
	if not child then
		return nil
	end
	for _, className in ipairs({ ... }) do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end

local function ensureScale(parent: GuiObject, name: string): UIScale
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = name
	scale.Scale = 1
	scale.Parent = parent
	return scale
end

local function isPointInside(guiObject: GuiObject, point: Vector2): boolean
	if not guiObject.Visible then
		return false
	end

	local absolutePosition = guiObject.AbsolutePosition
	local absoluteSize = guiObject.AbsoluteSize
	return point.X >= absolutePosition.X
		and point.X <= absolutePosition.X + absoluteSize.X
		and point.Y >= absolutePosition.Y
		and point.Y <= absolutePosition.Y + absoluteSize.Y
end

local function ensureGuiObjectVisibleChain(inst: Instance): ()
	local current: Instance? = inst
	while current do
		if current:IsA("GuiObject") then
			(current :: GuiObject).Visible = true
		end
		current = current.Parent
	end
end

local function ensureStickerGui(playerGui: PlayerGui): ScreenGui?
	local existing = playerGui:FindFirstChild(Config.Sticker.GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing :: ScreenGui
	end

	local template = StarterGui:FindFirstChild(Config.Sticker.GUI_NAME)
	if template and template:IsA("ScreenGui") then
		local clone = template:Clone()
		clone.Parent = playerGui
		return clone :: ScreenGui
	end

	return nil
end

local function resolveRefs(playerGui: PlayerGui): StickerRefs?
	local gui = ensureStickerGui(playerGui)
		or playerGui:WaitForChild(Config.Sticker.GUI_NAME, Config.Sticker.REMOTE_READY_TIMEOUT)
	if not gui or not gui:IsA("ScreenGui") then
		return nil
	end

	local sidePanel = findChildAnyClass(gui, "SelectStickerSidePanel", "CanvasGroup", "Frame")
	local modal = findChildAnyClass(gui, "AddNewStickerModal", "Frame", "CanvasGroup")
	if not sidePanel or not modal then
		return nil
	end

	local list = findChild(sidePanel, "StickerListScrollingFrame", "ScrollingFrame")
	if not list then
		return nil
	end

	local template = findChildAnyClass(list, "StickerTemplate", "ImageButton", "TextButton", "GuiButton")
	local uploadButton = findChildAnyClass(list, "UploadNewStickerButton", "ImageButton", "TextButton", "GuiButton")
	local textBox = findChild(modal, "StickerIDTextBox", "TextBox")
	local addButton = findChildAnyClass(modal, "AddStickerButton", "TextButton", "ImageButton", "GuiButton")
	local cancelButton = findChildAnyClass(modal, "CancelButton", "TextButton", "ImageButton", "GuiButton")
	if not template or not uploadButton or not textBox or not addButton or not cancelButton then
		return nil
	end

	local preview = modal:FindFirstChild("StickerPreview", true)
	local previewImage = preview and preview:FindFirstChild("StickerImage", true)

	return {
		gui = gui,
		sidePanel = sidePanel :: GuiObject,
		list = list :: ScrollingFrame,
		template = template :: ImageButton,
		uploadButton = uploadButton :: ImageButton,
		modal = modal :: Frame,
		textBox = textBox :: TextBox,
		previewImage = if previewImage and previewImage:IsA("ImageLabel") then previewImage :: ImageLabel else nil,
		addButton = addButton :: TextButton,
		cancelButton = cancelButton :: TextButton,
	}
end

function StickerController.create(deps: {
	remotes: Folder,
	logger: any?,
}): any
	local self = setmetatable({}, StickerController)
	self._log = deps.logger or Logger.new("Client.StickerController")
	self._remotes = deps.remotes
	self._connections = {} :: { RBXScriptConnection }
	self._itemConnections = {} :: { RBXScriptConnection }
	self._refs = nil :: StickerRefs?
	self._setRemote = nil :: RemoteEvent?
	self._clearRemote = nil :: RemoteEvent?
	self._addRemote = nil :: RemoteEvent?
	self._requestRemote = nil :: RemoteEvent?
	self._syncRemote = nil :: RemoteEvent?
	self._isOpen = false
	self._isGuiBound = false
	self._isInputBound = false
	self._modalTween = nil :: Tween?
	self._modalScale = nil :: UIScale?
	self._anim = AnimationHelper.new()
	self._modalAnimationToken = 0
	self._openedAt = 0
	self._stickers = {} :: { string }
	self._selectedSticker = ""
	return self
end

function StickerController:_track(connection: RBXScriptConnection)
	table.insert(self._connections, connection)
end

function StickerController:_trackItem(connection: RBXScriptConnection)
	table.insert(self._itemConnections, connection)
end

function StickerController:_clearItems()
	for _, connection in ipairs(self._itemConnections) do
		connection:Disconnect()
	end
	table.clear(self._itemConnections)

	local refs = self._refs
	if not refs then
		return
	end

	for _, child in ipairs(refs.list:GetChildren()) do
		if child:IsA("ImageButton") and child.Name:match("^RuntimeStickerItem_") then
			child:Destroy()
		end
	end
end

function StickerController:_resolveRemotes()
	if self._setRemote and self._addRemote and self._requestRemote and self._syncRemote then
		return
	end

	self._setRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_SET, Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?
	self._clearRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_CLEAR, Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?
	self._addRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_ADD, Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?
	self._requestRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_REQUEST, Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?
	self._syncRemote =
		self._remotes:WaitForChild(Config.Sticker.REMOTE_SYNC, Config.Sticker.REMOTE_READY_TIMEOUT) :: RemoteEvent?
end

function StickerController:_bindGui(): boolean
	if self._isGuiBound and self._refs then
		return true
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	self._refs = resolveRefs(playerGui)
	if not self._refs then
		if Config.Sticker.DEBUG then
			local childNames = {}
			for _, child in ipairs(playerGui:GetChildren()) do
				table.insert(childNames, child.Name .. ":" .. child.ClassName)
			end

			self._log:warn("Sticker GUI resolve failed", {
				expected = Config.Sticker.GUI_NAME,
				playerGuiChildren = table.concat(childNames, ","),
			})
		end
		self._log:warn("Sticker GUI tree not found", {
			guiName = Config.Sticker.GUI_NAME,
			userId = Players.LocalPlayer.UserId,
		})
		return false
	end

	local refs = self._refs
	refs.gui.Enabled = true
	refs.gui.DisplayOrder = Config.Sticker.DISPLAY_ORDER
	refs.sidePanel.Visible = self._isOpen
	setSidePanelTransparency(refs.sidePanel, if self._isOpen then 0 else 1)
	if not self._isOpen then
		refs.sidePanel.Visible = false
	end
	refs.modal.Visible = false
	refs.template.Visible = false
	self._modalScale = ensureScale(refs.modal, "RuntimeStickerModalScale")
	self._modalScale.Scale = Config.Sticker.MODAL_CLOSED_SCALE

	self:_track(refs.uploadButton.Activated:Connect(function()
		self:_setModalOpen(true)
	end))
	self:_track(refs.cancelButton.Activated:Connect(function()
		self:_setModalOpen(false)
	end))
	self:_track(refs.addButton.Activated:Connect(function()
		self:_addStickerFromInput()
	end))
	self:_track(refs.textBox:GetPropertyChangedSignal("Text"):Connect(function()
		self:_setPreviewFromInput()
	end))
	self:_track(refs.textBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			self:_addStickerFromInput()
		end
	end))

	if not self._isInputBound then
		self:_track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if not self._isOpen then
				return
			end

			local currentRefs = self._refs
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				if os.clock() - self._openedAt < 0.2 then
					return
				end
				if currentRefs and not self:_isPointerInsidePanel(input) then
					self:closePanel()
				end
				return
			end

			if gameProcessed then
				return
			end

			if
				currentRefs
				and input.UserInputType == Enum.UserInputType.Keyboard
				and input.KeyCode == Enum.KeyCode.Escape
			then
				if currentRefs.modal.Visible then
					self:_setModalOpen(false)
					return
				end
				self:closePanel()
			end
		end))
		self._isInputBound = true
	end

	self._isGuiBound = true
	self:_render()

	self._log:info("Sticker controller GUI bound", {
		gui = refs.gui:GetFullName(),
	})
	return true
end

function StickerController:_animateSidePanel(isOpen: boolean)
	local refs = self._refs
	if not refs then
		return
	end

	if isOpen then
		refs.sidePanel.Visible = true
		setSidePanelTransparency(refs.sidePanel, 0)
		self._anim:presentCenterPanel(refs.sidePanel :: any, nil)
		return
	end

	self._anim:dismissCenterPanel(refs.sidePanel :: any, function()
		setSidePanelTransparency(refs.sidePanel, 1)
		refs.sidePanel.Visible = false
	end)
end

function StickerController:_animateModal(isOpen: boolean)
	local refs = self._refs
	if not refs then
		return
	end

	local scale = self._modalScale or ensureScale(refs.modal, "RuntimeStickerModalScale")
	self._modalScale = scale
	self._modalAnimationToken += 1
	local token = self._modalAnimationToken

	if self._modalTween then
		self._modalTween:Cancel()
		self._modalTween = nil
	end

	if isOpen then
		scale.Scale = Config.Sticker.MODAL_CLOSED_SCALE
		refs.modal.Visible = true
		self._modalTween = TweenService:Create(scale, MODAL_TWEEN_INFO, {
			Scale = 1,
		})
	else
		self._modalTween = TweenService:Create(scale, PANEL_TWEEN_INFO, {
			Scale = Config.Sticker.MODAL_CLOSED_SCALE,
		})
	end

	local tween = self._modalTween
	tween.Completed:Once(function()
		if self._modalAnimationToken ~= token then
			return
		end

		if not isOpen then
			refs.modal.Visible = false
		end

		if self._modalTween == tween then
			self._modalTween = nil
		end
	end)
	tween:Play()
end

function StickerController:_setOpen(isOpen: boolean)
	if not self:_bindGui() then
		if isOpen then
			task.defer(function()
				self._isGuiBound = false
				if self:_bindGui() then
					self:_setOpen(true)
				end
			end)
		end
		return
	end

	local refs = self._refs
	if not refs then
		return
	end

	self._isOpen = isOpen
	if isOpen then
		self._openedAt = os.clock()
	end
	refs.gui.Enabled = true
	refs.gui.DisplayOrder = math.max(Config.Sticker.DISPLAY_ORDER, refs.gui.DisplayOrder)
	ensureGuiObjectVisibleChain(refs.sidePanel)
	self:_animateSidePanel(isOpen)
	if not isOpen then
		self:_animateModal(false)
	end
end

function StickerController:_setModalOpen(isOpen: boolean)
	local refs = self._refs
	if not refs then
		return
	end

	self:_animateModal(isOpen)
	if isOpen then
		refs.textBox.Text = ""
		if refs.previewImage then
			refs.previewImage.Image = ""
		end
		refs.textBox:CaptureFocus()
	end
end

function StickerController:_isPointerInsidePanel(input: InputObject): boolean
	local refs = self._refs
	if not refs then
		return false
	end

	local point = if input.UserInputType == Enum.UserInputType.Touch
		then Vector2.new(input.Position.X, input.Position.Y)
		else UserInputService:GetMouseLocation()
	return isPointInside(refs.sidePanel, point) or isPointInside(refs.modal, point)
end

function StickerController:_setPreviewFromInput()
	local refs = self._refs
	if not refs or not refs.previewImage then
		return
	end

	local image = normalizeImage(refs.textBox.Text)
	refs.previewImage.Image = image
end

function StickerController:_selectSticker(image: string)
	local normalized = normalizeImage(image)
	if normalized == "" then
		return
	end

	if self._setRemote then
		self._setRemote:FireServer({ image = normalized })
	end
	self._selectedSticker = normalized
	self:_render()
end

function StickerController:_addStickerFromInput()
	local refs = self._refs
	if not refs then
		return
	end

	local image = normalizeImage(refs.textBox.Text)
	if image == "" then
		self._log:warn("Sticker input ignored, invalid asset id")
		return
	end

	if self._addRemote then
		self._addRemote:FireServer({ image = image })
	end
	self:_setModalOpen(false)
end

function StickerController:_applySync(payload: any)
	if type(payload) ~= "table" then
		return
	end

	local nextStickers = {}
	if type(payload.stickers) == "table" then
		for _, image in ipairs(payload.stickers) do
			local normalized = normalizeImage(image)
			if normalized ~= "" then
				table.insert(nextStickers, normalized)
			end
		end
	end

	self._stickers = nextStickers
	self._selectedSticker = normalizeImage(payload.selectedSticker)
	self:_render()
end

function StickerController:_render()
	local refs = self._refs
	if not refs then
		return
	end

	self:_clearItems()
	refs.template.Visible = false
	refs.uploadButton.LayoutOrder = 100000

	for index, image in ipairs(self._stickers) do
		local button = refs.template:Clone()
		button.Name = "RuntimeStickerItem_" .. tostring(index)
		button.Image = image
		button.Visible = true
		button.LayoutOrder = index
		button.Parent = refs.list

		local stroke = button:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = if image == self._selectedSticker
				then Color3.fromRGB(255, 255, 255)
				else Color3.fromRGB(30, 30, 30)
			stroke.Thickness = if image == self._selectedSticker then 2 else 1
		end

		self:_trackItem(button.Activated:Connect(function()
			self:_selectSticker(image)
		end))
	end
end

function StickerController:init()
	self:_resolveRemotes()

	if self._syncRemote then
		self:_track(self._syncRemote.OnClientEvent:Connect(function(payload: any)
			self:_applySync(payload)
		end))
	end

	if self._requestRemote then
		self._requestRemote:FireServer()
	end

	self:_bindGui()
	self._log:info("Sticker controller initialized")
end

function StickerController:isOpen(): boolean
	return self._isOpen
end

function StickerController:togglePanel()
	self:_setOpen(not self._isOpen)
end

function StickerController:openPanel()
	self:_setOpen(true)
end

function StickerController:closePanel()
	self:_setOpen(false)
end

function StickerController:destroy()
	self:_clearItems()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._refs = nil
	self._setRemote = nil
	self._clearRemote = nil
	self._addRemote = nil
	self._requestRemote = nil
	self._syncRemote = nil
	self._isOpen = false
end

return StickerController
