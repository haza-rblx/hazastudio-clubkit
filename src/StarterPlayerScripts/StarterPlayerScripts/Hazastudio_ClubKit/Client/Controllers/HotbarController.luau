--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
type ILogger = Types.ILogger

local Players = game:GetService("Players")

local HotbarController = {}
HotbarController.__index = HotbarController

local function findBackpackPanelWrapper(): Frame?
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = playerGui:FindFirstChild(Config.Backpack.GUI_NAME)
		or playerGui:FindFirstChild(Config.Backpack.GUI_NAME, true)
	if not gui then
		return nil
	end
	local wrapper = gui:FindFirstChild(Config.Backpack.WRAPPER_NAME, true)
	if wrapper and wrapper:IsA("Frame") then
		return wrapper :: Frame
	end
	return nil
end

local function setBackpackCoreGuiEnabled(enabled: boolean): (boolean, string?)
	local ok, err = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
	end)
	if ok then
		return true, nil
	end

	return false, tostring(err)
end

function HotbarController.new(deps: {
	logger: ILogger,
	service: any,
	binder: any,
	backpackBinder: any?,
	backpackButton: GuiButton?,
	inventoryDrag: any?,
}): any
	local self = setmetatable({}, HotbarController)

	self._log = deps.logger
	self._service = deps.service
	self._binder = deps.binder
	self._backpackBinder = deps.backpackBinder
	self._backpackButton = deps.backpackButton
	self._inventoryDrag = deps.inventoryDrag
	self._isDestroyed = false

	return self
end

function HotbarController:_applyBackpackCoreGuiState(): ()
	task.spawn(function()
		local lastError = nil :: string?
		for _ = 1, 10 do
			local ok, err = setBackpackCoreGuiEnabled(false)
			if ok then
				return
			end

			lastError = err
			task.wait(0.2)
		end

		self._log:warn("Backpack CoreGui disable failed", {
			error = lastError or "unknown",
		})
	end)
end

function HotbarController:onStart(): ()
	self:_applyBackpackCoreGuiState()
	self._binder:bindReorderRequested(function(fromToolKey: string, toSlotIndex: number)
		self._service:reorder(fromToolKey, toSlotIndex)
	end)
	self._binder:bindEquipRequested(function(toolKey: string)
		self._service:equip(toolKey)
	end)

	if self._backpackButton then
		local backpackButton = self._backpackButton
		for _, descendant in ipairs(backpackButton:GetDescendants()) do
			if descendant:IsA("UIDragDetector") then
				descendant.Enabled = false
			end
		end
		local directDetector = backpackButton:FindFirstChildWhichIsA("UIDragDetector")
		if directDetector and directDetector:IsA("UIDragDetector") then
			directDetector.Enabled = false
		end

		local lastToggleAt = 0
		local function toggleBackpack()
			local now = os.clock()
			if now - lastToggleAt < 0.2 then
				return
			end
			lastToggleAt = now

			self._service:toggleBackpackOpen()
			local isOpen = self._service:isBackpackOpen()
			if Config.Hotbar.AUDIT_COMMAND_ENABLED == true then
				self._log:warn("Backpack toggle", {
					userId = Players.LocalPlayer.UserId,
					action = "toggle_backpack",
					success = true,
					isOpen = isOpen,
					hasBinder = self._backpackBinder ~= nil,
				})
			end
			if not self._backpackBinder then
				local wrapper = findBackpackPanelWrapper()
				if wrapper then
					wrapper.Visible = isOpen
				end
				local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
				if gui then
					local backpackGui = gui:FindFirstChild(Config.Backpack.GUI_NAME)
						or gui:FindFirstChild(Config.Backpack.GUI_NAME, true)
					if backpackGui and backpackGui:IsA("ScreenGui") then
						(backpackGui :: ScreenGui).Enabled = true
					end
				end
			end
		end
		-- TextButton fires both Activated and MouseButton1Click; dual handlers cancel the toggle.
		backpackButton.Activated:Connect(toggleBackpack)
	end

	self._service:onStart()
end

function HotbarController:destroy(): ()
	if self._isDestroyed then
		return
	end

	self._isDestroyed = true
	self._service:destroy()
	self._binder:destroy()
	if self._backpackBinder then
		self._backpackBinder:destroy()
	end
	if self._inventoryDrag then
		self._inventoryDrag:destroy()
	end
	local ok, err = setBackpackCoreGuiEnabled(true)
	if not ok then
		self._log:warn("Backpack CoreGui restore failed", {
			error = err or "unknown",
		})
	end
end

return HotbarController
