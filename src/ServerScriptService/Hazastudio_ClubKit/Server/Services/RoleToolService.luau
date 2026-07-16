--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type ILogger = Types.ILogger
type OverheadPayload = Types.OverheadPayload

local RoleToolService = {}
RoleToolService.__index = RoleToolService

-- Per-UserId debounce for the tool-sync request remote. Without this a client
-- can spam the remote and churn backpack tool re-granting + countBackpackTools
-- iteration, causing client-side flicker. Keyed by UserId (number) to avoid
-- retaining Player objects after they leave.
local syncCooldownByUserId: { [number]: number } = {}
local SYNC_COOLDOWN_SEC = 2

local function notifyClientToolsSynced(player: Player, toolCount: number)
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		return
	end
	local remote = remotesFolder:FindFirstChild(Config.Hotbar.REMOTE_TOOLS_SYNCED)
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end
	(remote :: RemoteEvent):FireClient(player, toolCount)
end

local function findRoleToolFolder(toolsRoot: Instance, folderName: string): Folder?
	local direct = toolsRoot:FindFirstChild(folderName)
	if direct and direct:IsA("Folder") then
		return direct :: Folder
	end

	local targetUpper = string.upper(folderName)
	for _, child in ipairs(toolsRoot:GetChildren()) do
		if child:IsA("Folder") and string.upper(child.Name) == targetUpper then
			if child.Name ~= folderName then
				return child :: Folder
			end
		end
	end

	return nil
end

local function countToolsInFolder(folder: Instance): number
	local count = 0
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Tool") then
			count += 1
		end
	end
	return count
end

local function countBackpackTools(player: Player): number
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return 0
	end
	local count = 0
	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") then
			count += 1
		end
	end
	return count
end

local function addFolders(folderNames: { string }, names: { string }?)
	if type(names) ~= "table" then
		return
	end
	for _, name in ipairs(names) do
		if type(name) == "string" and name ~= "" and not table.find(folderNames, name) then
			table.insert(folderNames, name)
		end
	end
end

local function getContainer(player: Player, className: string): Instance?
	local found = player:FindFirstChildOfClass(className)
	if found then
		return found
	end
	return player:FindFirstChild(className)
end

local function removeGrantedTools(container: Instance?, grantAttribute: string)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute(grantAttribute) == true then
			child:Destroy()
		end
	end
end

type OverheadServiceRef = {
	buildPayload: (self: OverheadServiceRef, player: Player) -> Types.Result<OverheadPayload>,
}

function RoleToolService.new(deps: {
	logger: ILogger,
	eventBus: any?,
	overheadService: OverheadServiceRef?,
}): any
	local self = setmetatable({}, RoleToolService)
	self._log = deps.logger
	self._eventBus = deps.eventBus
	self._overheadService = deps.overheadService
	self._connections = {} :: { RBXScriptConnection }
	self._eventUnsubscribe = nil :: (() -> ())?
	self._latestPayloads = {} :: { [number]: OverheadPayload }
	self._lastSyncedRole = {} :: { [number]: string }
	return self
end

function RoleToolService:_resolveFolderNames(payload: OverheadPayload): { string }
	local cfg = Config.RoleTools
	local folderNames = {}
	local spenderRoles = Config.SpenderRoles

	addFolders(folderNames, cfg.FOLDERS_BY_ROLE[payload.role])
	addFolders(folderNames, cfg.FOLDERS_BY_MEMBERSHIP[payload.effectiveMembership])

	local function withinMaxRank(spenderType: string, rank: number?): boolean
		if rank == nil then
			return false
		end
		if type(spenderRoles) ~= "table" then
			return true
		end
		local spenderConfig = spenderRoles[spenderType]
		if type(spenderConfig) ~= "table" or spenderConfig.Enabled == false then
			return false
		end
		local maxRank = tonumber(spenderConfig.MaxRank) or 1
		return rank >= 1 and rank <= maxRank
	end

	if withinMaxRank("RobuxSpender", payload.topDonateRank) then
		local robuxConfig = if type(spenderRoles) == "table" then spenderRoles.RobuxSpender else nil
		local folder = if type(robuxConfig) == "table" and type(robuxConfig.ToolFolder) == "string"
			then robuxConfig.ToolFolder
			else (cfg.ROYALE_SPENDER_FOLDER or cfg.TOP_DONATE_FOLDER or "TOP ROBUX DONATOR")
		addFolders(folderNames, { folder })
	end
	if withinMaxRank("CashSpender", payload.topSpenderRank) then
		local cashConfig = if type(spenderRoles) == "table" then spenderRoles.CashSpender else nil
		local folder = if type(cashConfig) == "table" and type(cashConfig.ToolFolder) == "string"
			then cashConfig.ToolFolder
			else (cfg.TOP_SPENDER_FOLDER or "TOP RUPIAH SPENDER")
		addFolders(folderNames, { folder })
	end

	-- Multi-role / multi-folder: satu folder saja — yang prioritas tertinggi.
	local selectedFolder: string? = nil
	local selectedPriority = -math.huge
	local priorities = cfg.FOLDER_PRIORITY or {}
	for _, folderName in ipairs(folderNames) do
		local priority = tonumber(priorities[folderName]) or 0
		if priority > selectedPriority then
			selectedFolder = folderName
			selectedPriority = priority
		end
	end

	if selectedFolder then
		return { selectedFolder }
	end

	return {}
end

function RoleToolService:_cloneFolderTools(
	target: Instance,
	folder: Instance,
	grantAttribute: string,
	sourceAttribute: string
): number
	local cloned = 0
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Tool") then
			local clone = descendant:Clone()
			clone:SetAttribute(grantAttribute, true)
			clone:SetAttribute(sourceAttribute, folder.Name)
			clone.Parent = target
			cloned += 1
		end
	end
	return cloned
end

function RoleToolService:_resolvePayload(player: Player): OverheadPayload?
	local cached = self._latestPayloads[player.UserId]
	if cached then
		return cached
	end

	local overheadService = self._overheadService
	if overheadService and type(overheadService.buildPayload) == "function" then
		local result = overheadService:buildPayload(player)
		if type(result) == "table" and result.ok == true and result.value then
			self._latestPayloads[player.UserId] = result.value
			return result.value
		end
	end

	return nil
end

function RoleToolService:syncPlayer(player: Player, payload: OverheadPayload?)
	if not player.Parent then
		return
	end

	local effectivePayload = payload or self:_resolvePayload(player)
	if not effectivePayload then
		self._log:warn("Role tools sync skipped — no overhead payload", {
			userId = player.UserId,
			action = "sync_role_tools",
			success = false,
		})
		notifyClientToolsSynced(player, countBackpackTools(player))
		return
	end

	-- GUARD 1: Skip sync if role hasn't changed (prevents unnecessary tool destroy/re-clone)
	local lastSyncedRole = self._lastSyncedRole[player.UserId]
	local newRole = effectivePayload.role
	if lastSyncedRole and newRole == lastSyncedRole then
		return
	end

	-- GUARD 2: Reject stale "Guest" payload when player had a valid role before
	if newRole == "Guest" or newRole == "" or newRole == nil then
		local lkg = player:GetAttribute("_LKG_Role")
		if lkg and lkg ~= "Guest" and lkg ~= "" then
			self._log:debug("Role tools sync skipped — ignoring stale Guest payload", {
				player = player.Name,
				lkgRole = lkg,
			})
			return
		end
	end

	self._latestPayloads[player.UserId] = effectivePayload

	local cfg = Config.RoleTools
	local toolsRoot = ServerStorage:FindFirstChild(cfg.ROOT_FOLDER)
	if not toolsRoot then
		self._log:warn("Role tools: missing ServerStorage folder", { folder = cfg.ROOT_FOLDER })
		return
	end

	local backpack = getContainer(player, "Backpack") or player:FindFirstChild("Backpack")
	local starterGear = getContainer(player, "StarterGear") or player:FindFirstChild("StarterGear")
	if not backpack then
		local ok, waited = pcall(function()
			return player:WaitForChild("Backpack", 12)
		end)
		if ok and waited and waited:IsA("Backpack") then
			backpack = waited
		end
	end
	if not starterGear then
		local ok, waited = pcall(function()
			return player:WaitForChild("StarterGear", 12)
		end)
		if ok and waited then
			starterGear = waited
		end
	end
	local character = player.Character

	-- FIX: Unequip tools before destroying to prevent orphaned pose/animation
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
	end

	removeGrantedTools(backpack, cfg.GRANT_ATTRIBUTE)
	removeGrantedTools(starterGear, cfg.GRANT_ATTRIBUTE)
	removeGrantedTools(character, cfg.GRANT_ATTRIBUTE)

	if not backpack or not starterGear then
		self._log:warn("Role tools sync skipped — Backpack/StarterGear not ready", {
			player = player.Name,
			hasBackpack = backpack ~= nil,
			hasStarterGear = starterGear ~= nil,
		})
		return
	end

	local folderNames = self:_resolveFolderNames(effectivePayload)
	if #folderNames == 0 then
		-- Downgrade to debug for Guest role (expected behavior, not an error)
		local role = tostring(effectivePayload.role)
		local isGuest = role == "Guest" or role == "" or role == nil
		local logFn = if isGuest then self._log.debug else self._log.warn
		logFn(self._log, "Role tools sync skipped — no folder for role", {
			userId = player.UserId,
			action = "sync_role_tools",
			success = false,
			role = role,
			effectiveMembership = tostring(effectivePayload.effectiveMembership or ""),
		})
		notifyClientToolsSynced(player, countBackpackTools(player))
		return
	end

	local selectedFolderName = folderNames[1]
	local folderToolCount = 0
	local clonedCount = 0

	for _, folderName in ipairs(folderNames) do
		local folder = findRoleToolFolder(toolsRoot, folderName)
		if not folder then
			-- Downgrade to debug: folder mismatch adalah config issue, bukan runtime error.
			-- Warning hanya sekali per session untuk mengurangi log spam.
			local warnKey = "RoleToolsFolderMissing_" .. folderName
			if not player:GetAttribute(warnKey) then
				player:SetAttribute(warnKey, true)
				self._log:debug("Role tools folder not found (config mismatch)", {
					player = player.Name,
					folder = folderName,
					root = cfg.ROOT_FOLDER,
				})
			end
			continue
		end

		folderToolCount = countToolsInFolder(folder)
		clonedCount += self:_cloneFolderTools(backpack, folder, cfg.GRANT_ATTRIBUTE, cfg.SOURCE_ATTRIBUTE)
		clonedCount += self:_cloneFolderTools(starterGear, folder, cfg.GRANT_ATTRIBUTE, cfg.SOURCE_ATTRIBUTE)
		if folder.Name ~= folderName then
			self._log:warn("Role tools folder matched with different casing", {
				player = player.Name,
				configFolder = folderName,
				actualFolder = folder.Name,
			})
		end
	end

	local toolCount = countBackpackTools(player)
	player:SetAttribute("RoleToolsSourceFolder", selectedFolderName)
	player:SetAttribute("RoleToolsFolderToolCount", folderToolCount)
	player:SetAttribute("RoleToolsGrantedCount", toolCount)
	self._lastSyncedRole[player.UserId] = newRole
	notifyClientToolsSynced(player, toolCount)
end

function RoleToolService:onStart()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if remotesFolder then
		local requestRemote = remotesFolder:FindFirstChild(Config.Hotbar.REMOTE_TOOLS_REQUEST_SYNC)
		if requestRemote and requestRemote:IsA("RemoteEvent") then
			table.insert(
				self._connections,
				(requestRemote :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
					-- Debounce: a client can otherwise spam this remote to churn
					-- backpack tool re-grants. Largely idempotent, but the spam
					-- causes client-side flicker + server-side countBackpackTools.
					local now = os.clock()
					local last = syncCooldownByUserId[player.UserId]
					if last and (now - last) < SYNC_COOLDOWN_SEC then
						return
					end
					syncCooldownByUserId[player.UserId] = now
					self:syncPlayer(player, self:_resolvePayload(player))
				end)
			)
		end
	end

	if self._eventBus and type(self._eventBus.on) == "function" then
		self._eventUnsubscribe = self._eventBus:on("Overhead:Payload", function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			local userId = tonumber(payload.userId)
			local player = if userId then Players:GetPlayerByUserId(userId) else nil
			if player then
				self:syncPlayer(player, payload :: OverheadPayload)
			end
		end)
	end

	local function bindPlayer(player: Player)
		table.insert(
			self._connections,
			player.CharacterAdded:Connect(function()
				-- Reset so tools are re-granted on respawn (new character has no tools)
				self._lastSyncedRole[player.UserId] = nil
				task.defer(function()
					self:syncPlayer(player)
				end)
			end)
		)
	end

	table.insert(self._connections, Players.PlayerAdded:Connect(bindPlayer))

	table.insert(
		self._connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			self._latestPayloads[player.UserId] = nil
			self._lastSyncedRole[player.UserId] = nil
		end)
	)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
		if player.Character then
			task.defer(function()
				self:syncPlayer(player)
			end)
		end
	end
end

function RoleToolService:destroy()
	if self._eventUnsubscribe then
		self._eventUnsubscribe()
		self._eventUnsubscribe = nil
	end
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._latestPayloads)
	table.clear(self._lastSyncedRole)
end

return RoleToolService
