--!strict
-- HotbarInventoryService (client Service)
--
-- Owns hotbar order, backpack split, and equip state in InventoryStore.
-- Initial hotbar fill runs once; empty hotbar after user moves tools to backpack is preserved.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local InventoryStore = require(script.Parent.Parent.State.InventoryStore)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type HotbarSlotViewModel = InventoryStore.HotbarSlotViewModel
type ILogger = Types.ILogger

type ToolEntry = {
	tool: Tool,
	key: string,
	displayName: string,
	iconAsset: string,
	isEquipped: boolean,
	scanIndex: number,
}

type Store = {
	set: (self: Store, changes: { [string]: any }) -> (),
}

local HotbarInventoryService = {}
HotbarInventoryService.__index = HotbarInventoryService

local function normalizeAsset(value: string): string
	if value == "" or value == "rbxassetid://0" then
		return ""
	end
	return value
end

local function resolveToolIcon(tool: Tool): string
	local textureId = normalizeAsset(tool.TextureId)
	if textureId ~= "" then
		return textureId
	end

	local attributeIcon = tool:GetAttribute(Config.Hotbar.TOOL_ICON_ATTRIBUTE)
	if type(attributeIcon) == "string" then
		local icon = normalizeAsset(attributeIcon)
		if icon ~= "" then
			return icon
		end
	end

	local handle = tool:FindFirstChild(Config.Hotbar.TOOL_HANDLE_NAME)
	if handle then
		local decal = handle:FindFirstChildWhichIsA("Decal", true)
		if decal then
			local decalTexture = normalizeAsset(decal.Texture)
			if decalTexture ~= "" then
				return decalTexture
			end
		end

		if handle:IsA("MeshPart") then
			local meshTexture = normalizeAsset(handle.TextureID)
			if meshTexture ~= "" then
				return meshTexture
			end
		end
	end

	return ""
end

local function resolveToolDisplayName(tool: Tool): string
	local displayName = tool:GetAttribute(Config.Hotbar.TOOL_DISPLAY_NAME_ATTRIBUTE)
	if type(displayName) == "string" and displayName ~= "" then
		return displayName
	end

	return tool.Name
end

local function findKeyIndex(keys: { string }, key: string): number?
	for index, existingKey in ipairs(keys) do
		if existingKey == key then
			return index
		end
	end

	return nil
end

local function moveKeyToIndex(keys: { string }, fromKey: string, toIndex: number): { string }
	local nextKeys = table.clone(keys)
	local fromIndex = findKeyIndex(nextKeys, fromKey)
	if not fromIndex then
		return nextKeys
	end

	local clampedToIndex = math.clamp(toIndex, 1, #nextKeys)
	if fromIndex == clampedToIndex then
		return nextKeys
	end

	local value = table.remove(nextKeys, fromIndex)
	table.insert(nextKeys, clampedToIndex, value)
	return nextKeys
end

local function insertKeyAtIndex(keys: { string }, key: string, toIndex: number): { string }
	local nextKeys = table.clone(keys)
	local existingIndex = findKeyIndex(nextKeys, key)
	if existingIndex then
		table.remove(nextKeys, existingIndex)
	end

	local clamped = math.clamp(toIndex, 1, #nextKeys + 1)
	table.insert(nextKeys, clamped, key)
	return nextKeys
end

function HotbarInventoryService.new(deps: {
	store: Store,
	logger: ILogger,
	slotCount: number,
}): any
	local self = setmetatable({}, HotbarInventoryService)

	self._store = deps.store
	self._log = deps.logger
	self._slotCount = deps.slotCount
	self._player = Players.LocalPlayer
	self._backpack = nil :: Backpack?
	self._character = nil :: Model?
	self._connections = {} :: { RBXScriptConnection }
	self._boundBackpacks = {} :: { [Backpack]: boolean }
	self._order = {} :: { string }
	self._entriesByKey = {} :: { [string]: ToolEntry }
	self._toolIds = {} :: { [Tool]: number }
	self._nextToolId = 0
	self._refreshToken = 0
	self._isBackpackOpen = false
	self._lastRoleToolsSourceFolder = nil :: string?
	self._initialHotbarSeeded = false

	return self
end

function HotbarInventoryService:_track(connection: RBXScriptConnection): ()
	table.insert(self._connections, connection)
end

function HotbarInventoryService:_clearConnections(): ()
	for index = #self._connections, 1, -1 do
		self._connections[index]:Disconnect()
	end
	table.clear(self._connections)
end

function HotbarInventoryService:_getToolKey(tool: Tool): string
	local existingId = self._toolIds[tool]
	if existingId then
		return tostring(existingId)
	end

	self._nextToolId += 1
	self._toolIds[tool] = self._nextToolId
	return tostring(self._nextToolId)
end

function HotbarInventoryService:_addTool(
	rawEntries: { ToolEntry },
	tool: Instance,
	isEquipped: boolean,
	scanIndex: number
): ()
	if not tool:IsA("Tool") then
		return
	end

	local displayName = resolveToolDisplayName(tool)
	local iconAsset = resolveToolIcon(tool)

	table.insert(rawEntries, {
		tool = tool :: Tool,
		key = self:_getToolKey(tool :: Tool),
		displayName = displayName,
		iconAsset = iconAsset,
		isEquipped = isEquipped,
		scanIndex = scanIndex,
	})
end

function HotbarInventoryService:_collectEntries(): { ToolEntry }
	local rawEntries = {} :: { ToolEntry }
	local scanIndex = 0

	if self._backpack then
		for _, child in ipairs(self._backpack:GetChildren()) do
			scanIndex += 1
			self:_addTool(rawEntries, child, false, scanIndex)
		end
	end

	if self._character then
		for _, child in ipairs(self._character:GetChildren()) do
			scanIndex += 1
			self:_addTool(rawEntries, child, true, scanIndex)
		end
	end

	return rawEntries
end

function HotbarInventoryService:_seedInitialHotbarOrder(entries: { ToolEntry }): { string }
	local sorted = table.clone(entries)
	table.sort(sorted, function(left: ToolEntry, right: ToolEntry): boolean
		return left.scanIndex < right.scanIndex
	end)

	local nextOrder = table.create(math.min(#sorted, self._slotCount))
	for index, entry in ipairs(sorted) do
		if index > self._slotCount then
			break
		end
		table.insert(nextOrder, entry.key)
	end
	return nextOrder
end

function HotbarInventoryService:_reconcileOrder(entries: { ToolEntry }): { string }
	local previousOrderLen = #self._order
	local present = {} :: { [string]: boolean }
	for _, entry in ipairs(entries) do
		present[entry.key] = true
	end

	local nextOrder = {} :: { string }
	for _, key in ipairs(self._order) do
		if present[key] then
			table.insert(nextOrder, key)
			present[key] = false
		end
	end

	-- Tool instances were replaced (server resync) — old keys are stale; refill hotbar once.
	if #nextOrder == 0 and self._initialHotbarSeeded and previousOrderLen > 0 then
		for key in pairs(present) do
			if present[key] then
				return self:_seedInitialHotbarOrder(entries)
			end
		end
	end

	-- First tool batch: fill hotbar up to slot cap; remainder goes to backpack.
	-- Do not re-seed after the user intentionally empties the hotbar.
	if #nextOrder == 0 and not self._initialHotbarSeeded then
		local hasUnassigned = false
		for key in pairs(present) do
			if present[key] then
				hasUnassigned = true
				break
			end
		end
		if hasUnassigned then
			self._initialHotbarSeeded = true
			return self:_seedInitialHotbarOrder(entries)
		end
	end

	-- After initial seed, new tools stay in the backpack until assigned (drag or API).
	return nextOrder
end

function HotbarInventoryService:_publish(entries: { ToolEntry }): ()
	self._entriesByKey = {}
	for _, entry in ipairs(entries) do
		self._entriesByKey[entry.key] = entry
	end

	self._order = self:_reconcileOrder(entries)

	local sortedEntries = table.clone(entries)
	table.sort(sortedEntries, function(left: ToolEntry, right: ToolEntry): boolean
		return left.scanIndex < right.scanIndex
	end)

	-- Emit view models only for assigned tools (no empty padding slots; dynamic hotbar).
	local slots = {} :: { HotbarSlotViewModel }
	local limit = math.min(#self._order, self._slotCount)
	for index = 1, limit do
		local key = self._order[index]
		local entry = self._entriesByKey[key]
		if entry then
			table.insert(slots, {
				slotId = tostring(index),
				index = index,
				toolKey = entry.key,
				displayName = entry.displayName,
				iconAsset = entry.iconAsset,
				isEquipped = entry.isEquipped,
				isEmpty = false,
			})
		end
	end

	local hotbarKeys = {} :: { [string]: boolean }
	for _, key in ipairs(self._order) do
		hotbarKeys[key] = true
	end

	local backpackSlots = {} :: { HotbarSlotViewModel }
	local backpackIndex = 0
	for _, entry in ipairs(sortedEntries) do
		if hotbarKeys[entry.key] then
			continue
		end
		backpackIndex += 1
		table.insert(backpackSlots, {
			slotId = "bp_" .. tostring(backpackIndex),
			index = backpackIndex,
			toolKey = entry.key,
			displayName = entry.displayName,
			iconAsset = entry.iconAsset,
			isEquipped = entry.isEquipped,
			isEmpty = false,
		})
	end

	local hasTools = #slots > 0 or #backpackSlots > 0
	self._store:set({
		hotbarSlots = slots,
		backpackSlots = backpackSlots,
		isBackpackOpen = self._isBackpackOpen,
		hasTools = hasTools,
	})

end

--- On role kit folder change, clear hotbar order and allow initial seed again without rejoin.
function HotbarInventoryService:_applyRoleToolsFolderChange(): ()
	local folderAttr = self._player:GetAttribute("RoleToolsSourceFolder")
	local folderName = if type(folderAttr) == "string" and folderAttr ~= "" then folderAttr else nil
	if not folderName then
		return
	end

	if self._lastRoleToolsSourceFolder ~= nil and self._lastRoleToolsSourceFolder ~= folderName then
		table.clear(self._order)
		self._initialHotbarSeeded = false
		if Config.Hotbar.AUDIT_COMMAND_ENABLED == true then
			self._log:warn("Role tools folder changed; hotbar order reset", {
				userId = self._player.UserId,
				action = "role_tools_folder_changed",
				success = true,
				previousFolder = self._lastRoleToolsSourceFolder,
				nextFolder = folderName,
			})
		end
	end

	self._lastRoleToolsSourceFolder = folderName
end

function HotbarInventoryService:refresh(): ()
	self:_applyRoleToolsFolderChange()
	self:_publish(self:_collectEntries())
end

function HotbarInventoryService:_scheduleRefresh(delaySeconds: number?)
	self._refreshToken += 1
	local token = self._refreshToken
	task.delay(delaySeconds or 0.05, function()
		if token ~= self._refreshToken then
			return
		end
		self:refresh()
	end)
end

function HotbarInventoryService:_bindBackpack(backpack: Backpack?)
	if not backpack or self._boundBackpacks[backpack] then
		return
	end

	self._boundBackpacks[backpack] = true
	self._backpack = backpack
	self:_track(backpack.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:_scheduleRefresh()
		end
	end))
	self:_track(backpack.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") then
			self:_scheduleRefresh()
		end
	end))
	self:_scheduleRefresh(0)
end

function HotbarInventoryService:_scheduleToolSyncPoll(): ()
	local delays = Config.Hotbar.TOOL_SYNC_REFRESH_DELAYS
	if type(delays) ~= "table" then
		return
	end

	for _, delaySeconds in ipairs(delays) do
		self:_scheduleRefresh(tonumber(delaySeconds) or 0)
	end
end

function HotbarInventoryService:reorder(fromToolKey: string, toSlotIndex: number): ()
	self._order = moveKeyToIndex(self._order, fromToolKey, toSlotIndex)
	self:refresh()
end

function HotbarInventoryService:toggleBackpackOpen(): ()
	self._isBackpackOpen = not self._isBackpackOpen
	self._store:set({ isBackpackOpen = self._isBackpackOpen })
end

function HotbarInventoryService:isBackpackOpen(): boolean
	return self._isBackpackOpen
end

function HotbarInventoryService:snapshotOrder(): { string }
	local snapshot = table.create(#self._order)
	for _, key in ipairs(self._order) do
		table.insert(snapshot, key)
	end
	return snapshot
end

function HotbarInventoryService:restoreOrder(snapshot: { string }): ()
	local nextOrder = table.create(#snapshot)
	for _, key in ipairs(snapshot) do
		if self._entriesByKey[key] then
			table.insert(nextOrder, key)
		end
	end
	self._order = nextOrder
	self:refresh()
end

function HotbarInventoryService:assignToolToHotbar(toolKey: string, toIndex: number): boolean
	if not self._entriesByKey[toolKey] then
		return false
	end

	local existingIndex = findKeyIndex(self._order, toolKey)
	if existingIndex then
		self._order = moveKeyToIndex(self._order, toolKey, toIndex)
		self:refresh()
		return true
	end

	if #self._order >= self._slotCount then
		self._log:warn("Hotbar full; tool remains in backpack", {
			userId = self._player.UserId,
			action = "assign_tool_to_hotbar",
			success = false,
			toolKey = toolKey,
			slotCount = self._slotCount,
		})
		return false
	end

	self._order = insertKeyAtIndex(self._order, toolKey, toIndex)
	self:refresh()
	return true
end

function HotbarInventoryService:removeToolFromHotbar(toolKey: string): ()
	local existingIndex = findKeyIndex(self._order, toolKey)
	if not existingIndex then
		return
	end

	table.remove(self._order, existingIndex)
	self:refresh()
end

function HotbarInventoryService:equip(toolKey: string): ()
	local entry = self._entriesByKey[toolKey]
	if not entry then
		return
	end

	local character = self._player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if entry.tool.Parent == character then
		humanoid:UnequipTools()
		self:_scheduleRefresh()
		return
	end

	local ok, err = pcall(function()
		humanoid:EquipTool(entry.tool)
	end)
	if not ok then
		self._log:warn("Tool equip failed", {
			tool = entry.displayName,
			error = tostring(err),
		})
	else
		self:_scheduleRefresh()
	end
end

function HotbarInventoryService:onStart(): ()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 30)
	if remotesFolder then
		local syncedRemote = remotesFolder:WaitForChild(Config.Hotbar.REMOTE_TOOLS_SYNCED, 15)
		if syncedRemote and syncedRemote:IsA("RemoteEvent") then
			self:_track((syncedRemote :: RemoteEvent).OnClientEvent:Connect(function(toolCount: any)
				self:refresh()
				local state = self._store:get()
				if Config.Hotbar.AUDIT_COMMAND_ENABLED == true then
					self._log:warn("HotbarToolsSynced received", {
						userId = self._player.UserId,
						action = "tools_synced_remote",
						success = true,
						toolCount = tonumber(toolCount) or 0,
						roleToolsSourceFolder = self._player:GetAttribute("RoleToolsSourceFolder"),
						roleToolsFolderToolCount = self._player:GetAttribute("RoleToolsFolderToolCount"),
						hotbarMaxSlots = self._slotCount,
						storeHotbarSlotCount = #state.hotbarSlots,
						storeBackpackSlotCount = #state.backpackSlots,
					})
				end
				self:_scheduleToolSyncPoll()
			end))
		end
		local requestRemote = remotesFolder:FindFirstChild(Config.Hotbar.REMOTE_TOOLS_REQUEST_SYNC)
		if requestRemote and requestRemote:IsA("RemoteEvent") then
			local fireRequest = function()
				(requestRemote :: RemoteEvent):FireServer()
			end
			fireRequest()
			task.delay(1.5, fireRequest)
			task.delay(5, fireRequest)
		end
	end

	self._backpack = self._player:WaitForChild("Backpack") :: Backpack
	self._character = self._player.Character
	self:_bindBackpack(self._backpack)
	self:_scheduleToolSyncPoll()

		self:_track(self._player:GetAttributeChangedSignal("RoleToolsSourceFolder"):Connect(function()
			self:_applyRoleToolsFolderChange()
			self:_scheduleRefresh(0)
		end))

		self:_track(self._player.CharacterAdded:Connect(function(character: Model)
		self._character = character
		self:_bindBackpack(self._player:WaitForChild("Backpack") :: Backpack)
		self:refresh()
		self:_scheduleToolSyncPoll()
		task.delay(0.5, function()
			self:_bindBackpack(self._player:FindFirstChildOfClass("Backpack"))
			self:refresh()
		end)

		self:_track(character.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:_scheduleRefresh()
			end
		end))
		self:_track(character.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:_scheduleRefresh()
			end
		end))
	end))

	if self._character then
		self:_track(self._character.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:_scheduleRefresh()
			end
		end))
		self:_track(self._character.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Tool") then
				self:_scheduleRefresh()
			end
		end))
	end

	self:refresh()
end

function HotbarInventoryService:destroy(): ()
	self:_clearConnections()
end

return HotbarInventoryService
