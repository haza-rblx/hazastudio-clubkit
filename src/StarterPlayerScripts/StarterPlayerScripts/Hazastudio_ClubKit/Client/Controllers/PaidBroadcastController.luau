--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local OverheadController = require(script.Parent.OverheadController)
local PaidBroadcastGuiRefs = require(script.Parent.Parent.UI.PaidBroadcastGuiRefs)
local PaidBroadcastUI = require(script.Parent.Parent.UI.PaidBroadcastUI)

local PaidBroadcastController = {}
local log = Logger.new("PaidBroadcastController")

local function localPlayerCanAnnounce(): boolean
	local localPlayer = Players.LocalPlayer
	local role = OverheadController.getPlayerRole(localPlayer.UserId)
	local membership = OverheadController.getPlayerEffectiveMembership(localPlayer.UserId)
	return PermissionDomain.canAnnounce(role, membership)
end

local ui: PaidBroadcastUI.UI? = nil
local iconRef: any = nil
local waitingForResult = false
local resultConnection: RBXScriptConnection? = nil
local iconSelectedConnection: RBXScriptConnection? = nil
local iconDeselectedConnection: RBXScriptConnection? = nil

local function fetchProductPrice(productId: number): number?
	if productId <= 0 then
		return nil
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
		return info.PriceInRobux
	end
	return nil
end

local function isValidUi(candidate: any): boolean
	return type(candidate) == "table" and type((candidate :: any).show) == "function"
end

local function deselectIcon()
	if iconRef and type(iconRef.deselect) == "function" then
		pcall(function()
			iconRef:deselect()
		end)
	end
end

local function handleResult(raw: any)
	if not waitingForResult then
		return
	end
	if type(raw) ~= "table" then
		waitingForResult = false
		return
	end
	waitingForResult = false

	if raw.ok ~= true then
		return
	end

	local mode = raw.mode
	-- "sent" = free canAnnounce path; "purchased" = after Robux receipt.
	if mode == "purchased" or mode == "sent" then
		local bound = ui
		if bound and type((bound :: any).hide) == "function" then
			bound:hide()
		end
		deselectIcon()
		return
	end

	if mode == "purchase_required" then
		local productId = Config.PaidBroadcast.PRODUCT_ID
		if productId <= 0 then
			return
		end
		task.delay(Config.PaidBroadcast.PROMPT_DELAY, function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
		end)
	end
end

local function onConfirm(message: string)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		return
	end
	local submitRemote = remotes:FindFirstChild(Config.PaidBroadcast.REMOTE_SUBMIT)
	if not submitRemote or not submitRemote:IsA("RemoteEvent") then
		log:warn("PaidBroadcastSubmit remote missing")
		return
	end

	waitingForResult = true
	(submitRemote :: RemoteEvent):FireServer({
		message = message,
	})
end

local function ensurePanelUi(): PaidBroadcastUI.UI?
	if isValidUi(ui) then
		return ui
	end

	ui = nil
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if not playerGui then
		playerGui = localPlayer:WaitForChild("PlayerGui", 10) :: PlayerGui?
	end
	if not playerGui then
		log:warn("Paid broadcast PlayerGui missing")
		return nil
	end

	local guiName = Config.PaidBroadcast.GUI_NAME
	local gui = playerGui:FindFirstChild(guiName)
	if not gui then
		local template = StarterGui:FindFirstChild(guiName)
		if template and template:IsA("ScreenGui") then
			gui = template:Clone()
			gui.Parent = playerGui
		end
	end
	if not gui then
		gui = playerGui:WaitForChild(guiName, 8)
	end
	if not gui then
		log:warn("Paid broadcast GUI not found", { name = guiName })
		return nil
	end

	local refsOk, refsOrErr = pcall(function()
		return PaidBroadcastGuiRefs.resolve(playerGui, guiName)
	end)
	if not refsOk then
		log:warn("Paid broadcast GUI refs failed", { error = tostring(refsOrErr) })
		return nil
	end

	local uiOk, uiOrErr = pcall(function()
		return PaidBroadcastUI.new(refsOrErr)
	end)
	if not uiOk or not isValidUi(uiOrErr) then
		log:warn("Paid broadcast UI failed", { error = tostring(uiOrErr) })
		return nil
	end

	local bound = uiOrErr :: PaidBroadcastUI.UI
	bound:setOnConfirm(onConfirm)
	bound:setOnClosed(function()
		deselectIcon()
	end)
	ui = bound
	return bound
end

local function showPanel()
	local bound = ensurePanelUi()
	if not bound then
		log:warn("Paid broadcast panel could not open (UI not bound)")
		deselectIcon()
		return
	end

	local bypassPayment = localPlayerCanAnnounce()
	PaidBroadcastUI.show(bound, {
		bypassPayment = bypassPayment,
		priceRobux = if bypassPayment then nil else fetchProductPrice(Config.PaidBroadcast.PRODUCT_ID),
		player = Players.LocalPlayer,
	})
end

local function hidePanel()
	local bound = ui
	if bound and type((bound :: any).hide) == "function" then
		PaidBroadcastUI.hide(bound)
	end
end

local function wireResultRemote(remotes: Folder)
	local resultRemote = remotes:WaitForChild(Config.PaidBroadcast.REMOTE_RESULT, 15)
	if resultRemote and resultRemote:IsA("RemoteEvent") then
		if resultConnection then
			resultConnection:Disconnect()
		end
		resultConnection = (resultRemote :: RemoteEvent).OnClientEvent:Connect(handleResult)
	end
end

function PaidBroadcastController.init(deps: { icon: any, remotes: Folder? })
	iconRef = deps.icon

	if iconSelectedConnection then
		iconSelectedConnection:Disconnect()
		iconSelectedConnection = nil
	end
	if iconDeselectedConnection then
		iconDeselectedConnection:Disconnect()
		iconDeselectedConnection = nil
	end

	if not ensurePanelUi() then
		log:warn("Paid broadcast UI not ready at init; will retry when icon is opened")
	else
		log:debug("Paid broadcast UI bound at init")
	end

	local remotes = deps.remotes or ReplicatedStorage:WaitForChild("Remotes", 15)
	if remotes and remotes:IsA("Folder") then
		wireResultRemote(remotes)
	end

	if deps.icon and deps.icon.selected and type(deps.icon.selected.Connect) == "function" then
		iconSelectedConnection = deps.icon.selected:Connect(function()
			showPanel()
		end)
	end
	if deps.icon and deps.icon.deselected and type(deps.icon.deselected.Connect) == "function" then
		iconDeselectedConnection = deps.icon.deselected:Connect(function()
			hidePanel()
		end)
	end

	log:info("PaidBroadcastController initialized", { uiReady = isValidUi(ui) })
end

function PaidBroadcastController.destroy()
	if resultConnection then
		resultConnection:Disconnect()
		resultConnection = nil
	end
	if iconSelectedConnection then
		iconSelectedConnection:Disconnect()
		iconSelectedConnection = nil
	end
	if iconDeselectedConnection then
		iconDeselectedConnection:Disconnect()
		iconDeselectedConnection = nil
	end
end

return PaidBroadcastController
