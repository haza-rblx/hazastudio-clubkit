--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type CarryControllerDeps = {
	config: any,
	logger: any,
	ui: any,
	store: any,
	domain: any,
}

local function createCarryController(deps: CarryControllerDeps)
	local config = deps.config
	local carryConfig = config.Carry
	local log = deps.logger
	local ui = deps.ui
	local store = deps.store
	local domain = deps.domain
	local connections: { RBXScriptConnection } = {}
	local remotesFolder: Folder? = nil
	local commandRemote: RemoteEvent? = nil
	local notifyRemote: RemoteEvent? = nil
	local controller = {}

	local function track(connection: RBXScriptConnection): ()
		table.insert(connections, connection)
	end

	local function clearSelection(): ()
		store:clear({ "selectedTargetUserId", "selectedTargetName", "lastError" })
	end

	local function clearPending(): ()
		store:clear({ "pendingCarrierUserId", "pendingCarrierName", "pendingStyle", "lastError" })
	end

	local function clearCarry(): ()
		store:clear({ "partnerUserId", "partnerName", "currentStyle", "lastError" })
	end

	local function sendCommand(commandType: string, payload: any): ()
		if commandRemote == nil then
			log:warn("Carry command remote belum siap", { commandType = commandType })
			return
		end

		commandRemote:FireServer({
			type = commandType,
			requestId = HttpService:GenerateGUID(false),
			payload = payload or {},
		})
	end

	local function handleNotification(notificationType: string, payload: any): ()
		if type(payload) ~= "table" then
			payload = {}
		end

		if notificationType == "RequestSent" then
			store:set({
				mode = "waiting",
				partnerUserId = payload.targetUserId,
				partnerName = payload.targetName,
				currentStyle = payload.style,
			})
			ui:hideStylePicker()
			clearSelection()
			return
		end

		if notificationType == "ShowRequest" then
			local styleName = if type(payload.style) == "string" then payload.style else ""
			store:set({
				mode = "pending",
				pendingCarrierUserId = payload.carrierUserId,
				pendingCarrierName = payload.carrierName,
				pendingStyle = styleName,
			})
			ui:showConfirmation(payload.carrierName or "Someone", domain.getStyleDisplayName(styleName))
			return
		end

		if notificationType == "CarryStarted" or notificationType == "BeingCarried" then
			clearPending()
			clearSelection()
			store:set({
				mode = "carrying",
				partnerUserId = payload.partnerUserId,
				partnerName = payload.partnerName,
				currentStyle = payload.style,
			})
			ui:hideStylePicker()
			ui:hideConfirmation()
			ui:showDropButton()
			return
		end

		if notificationType == "CarryEnded" then
			store:set({ mode = "idle" })
			clearPending()
			clearSelection()
			clearCarry()
			ui:hideAll()
			return
		end

		if notificationType == "RequestRejected" then
			store:set({ mode = "idle" })
			clearSelection()
			clearCarry()
			ui:hideAll()
			return
		end

		if notificationType == "RequestFailed" then
			store:set({ mode = "idle", lastError = tostring(payload.reason or "request_failed") })
			clearSelection()
			clearPending()
			clearCarry()
			ui:hideAll()
			log:warn("Carry request failed", { reason = payload.reason })
		end
	end

	function controller:init(): ()
		remotesFolder = ReplicatedStorage:WaitForChild(carryConfig.REMOTE_FOLDER, 10) :: Folder?
		if remotesFolder == nil then
			log:warn("Carry remotes folder tidak ditemukan")
			return
		end

		commandRemote = (remotesFolder :: Folder):WaitForChild(carryConfig.COMMAND_REMOTE, 10) :: RemoteEvent?
		notifyRemote = (remotesFolder :: Folder):WaitForChild(carryConfig.NOTIFY_REMOTE, 10) :: RemoteEvent?
		if commandRemote == nil or notifyRemote == nil then
			log:warn("Carry remotes tidak lengkap")
			return
		end

		ui:setStyles(domain.getStyles())
		ui:bindStyleSelected(function(styleName: string)
			local state = store:get()
			if state.selectedTargetUserId == nil then
				ui:hideStylePicker()
				return
			end

			sendCommand("REQUEST", {
				targetUserId = state.selectedTargetUserId,
				targetName = state.selectedTargetName,
				style = styleName,
			})
		end)

		ui:bindStyleClosed(function()
			store:set({ mode = "idle" })
			clearSelection()
		end)

		ui:bindAccept(function()
			ui:hideConfirmation()
			sendCommand("ACCEPT", {})
		end)

		ui:bindReject(function()
			ui:hideConfirmation()
			store:set({ mode = "idle" })
			clearPending()
			sendCommand("REJECT", {})
		end)

		ui:bindDrop(function()
			sendCommand("END", {})
		end)

		track((notifyRemote :: RemoteEvent).OnClientEvent:Connect(handleNotification))
		log:info("CarryController initialized")
	end

	function controller:requestCarryByUserId(targetUserId: number): boolean
		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		if targetPlayer == nil or targetPlayer == Players.LocalPlayer then
			return false
		end

		store:set({
			mode = "selecting",
			selectedTargetUserId = targetUserId,
			selectedTargetName = targetPlayer.Name,
		})
		store:clear({ "lastError" })
		ui:showStylePicker(targetPlayer.DisplayName)
		return true
	end

	function controller:destroy(): ()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
		if type(ui.destroy) == "function" then
			ui:destroy()
		end
	end

	return controller
end

return {
	create = createCarryController,
}
