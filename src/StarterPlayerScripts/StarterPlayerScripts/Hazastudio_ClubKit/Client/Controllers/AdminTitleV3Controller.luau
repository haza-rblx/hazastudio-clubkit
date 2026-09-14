--!strict
-- Client/Controllers/AdminTitleV3Controller.luau
-- Drives the v3 custom-title panel: resolves `04-AdminPanelv3`, binds it to the
-- admin title remotes, and (optionally) owns the topbar icon.
--
-- Kept apart from the classic AdminController the same way AdminHubController is:
-- v3 covers custom titles only, so the two can coexist while a place migrates,
-- and a place without the v3 GUI never loads any of this.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local AdminPanelV3UI = require(script.Parent.Parent.UI.AdminPanelV3UI)
-- Every client already receives an overhead payload per player (that is what
-- draws the nametags), and OverheadController caches it. Reading the target's
-- current title from there costs no extra remote and no server work — the same
-- source the classic admin panel reads for its title editor.
local OverheadController = require(script.Parent.OverheadController)

local AdminTitleV3Controller = {}

local connections: { RBXScriptConnection } = {}
-- OverheadController hands back a plain function, not an RBXScriptConnection.
local unsubscribers: { () -> () } = {}
local panel: any = nil

local function newRequestId(): string
	return string.format("%d-%d", os.time(), math.random(1, 1e6))
end

function AdminTitleV3Controller.init(deps: { remotes: Folder, icon: any?, bindTopbar: boolean? }): any?
	local log = Logger.new("AdminTitleV3Controller")
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui", Config.Admin.GUI_WAIT_TIMEOUT)
	if not playerGui then
		return nil
	end

	panel = AdminPanelV3UI.tryCreate(playerGui)
	if not panel then
		log:info("04-AdminPanelv3 not installed — v3 title panel skipped")
		return nil
	end

	local remotes = deps.remotes
	local timeout = Config.Shop.REMOTE_READY_TIMEOUT
	local setTitle = remotes:WaitForChild(Config.Admin.REMOTE_SET_TITLE, timeout) :: RemoteEvent?
	local setImage = remotes:WaitForChild(Config.Admin.REMOTE_SET_TITLE_IMAGE, timeout) :: RemoteEvent?
	local imageList = remotes:WaitForChild(Config.Admin.REMOTE_TITLE_IMAGE_LIST, timeout) :: RemoteEvent?
	local resetTitle = remotes:WaitForChild(Config.Admin.REMOTE_RESET_TITLE, timeout) :: RemoteEvent?
	if not (setTitle and setImage and imageList and resetTitle) then
		log:warn("Admin title remotes missing — v3 panel left unbound")
		return nil
	end

	panel:bindApplyTitle(function(form)
		setTitle:FireServer({
			targetUsername = form.targetUsername,
			title = form.title,
			titleSize = form.titleSize,
			presetMode = form.presetMode,
			titleFont = form.titleFont,
			requestId = newRequestId(),
		})
	end)

	panel:bindApplyImage(function(form)
		setImage:FireServer({
			targetUsername = form.targetUsername,
			imageId = form.imageId,
			requestId = newRequestId(),
		})
	end)

	panel:bindRemoveTitle(function(entry)
		-- On the image tab "Remove" clears the image; on the text tab it resets the
		-- title. Same button, whichever surface is showing.
		if panel:getTab() == "image" then
			setImage:FireServer({
				targetUsername = entry.username,
				imageId = "",
				requestId = newRequestId(),
			})
		else
			resetTitle:FireServer({
				targetUsername = entry.username,
				requestId = newRequestId(),
			})
		end
	end)

	panel:bindRequestImageList(function()
		imageList:FireServer()
	end)

	-- Picking a player loads what they currently have into the editor.
	panel:bindPlayerSelected(function(entry)
		panel:applyTargetSnapshot(OverheadController.getCachedPayload(entry.userId))
	end)

	-- The cache updates when a title is saved (or an admin elsewhere changes it),
	-- so the "current title" line follows along. Only that line: reloading the form
	-- here would wipe whatever the admin is typing.
	if type(OverheadController.subscribeOverheadCacheUpdated) == "function" then
		local unsubscribe = OverheadController.subscribeOverheadCacheUpdated(function(userId: number?)
			local selected = panel:getSelectedPlayer()
			if not selected or (userId ~= nil and userId ~= selected.userId) then
				return
			end
			local payload = OverheadController.getCachedPayload(selected.userId)
			panel:setCurrentTitle(if type(payload) == "table" then payload.specialTitle else nil)
		end)
		if type(unsubscribe) == "function" then
			table.insert(unsubscribers, unsubscribe)
		end
	end

	table.insert(connections, imageList.OnClientEvent:Connect(function(list: any)
		if type(list) == "table" then
			panel:setImageList(list)
		end
	end))

	local icon = deps.icon
	panel:bindClose(function()
		if icon then
			icon:deselect()
		end
	end)

	if deps.bindTopbar ~= false and icon then
		icon:setEnabled(false)
		table.insert(connections, icon.selected:Connect(function()
			panel:show()
			imageList:FireServer()
		end))
		table.insert(connections, icon.deselected:Connect(function()
			panel:hide()
		end))

		-- Show the icon only to players whose role may use the admin panel. The classic
		-- AdminController does this when it owns the icon; when v3 owns it that controller
		-- is not listening (a v3-only place has no 04-AdminPanelv2, so it returns before
		-- its role listener), and without this the icon stayed disabled for everyone.
		-- Same source as the classic panel: the local player's overhead payload role.
		local iconShown = false
		local function applyAdminAccess()
			local payload = OverheadController.getCachedPayload(localPlayer.UserId)
			local role = if type(payload) == "table" and payload.role ~= nil then tostring(payload.role) else nil
			local allowed = PermissionDomain.canUseAdminPanel(role, localPlayer.UserId)
			if allowed == iconShown then
				return
			end
			iconShown = allowed
			icon:setEnabled(allowed)
			if not allowed then
				icon:deselect()
				panel:hide()
			end
		end
		if type(OverheadController.subscribeOverheadCacheUpdated) == "function" then
			local unsubscribe = OverheadController.subscribeOverheadCacheUpdated(function(userId: number?)
				if userId == nil or userId == localPlayer.UserId then
					applyAdminAccess()
				end
			end)
			if type(unsubscribe) == "function" then
				table.insert(unsubscribers, unsubscribe)
			end
		end
		applyAdminAccess()
	end

	-- The GUI ships Enabled with its wrapper visible so it can be edited in Studio;
	-- start it closed so it does not sit on top of the game on join. Immediate: a
	-- dismissal here would play the close tween over a panel the player never saw.
	panel:hide(true)

	log:info("AdminTitleV3Controller initialized")
	return {
		show = function()
			panel:show()
			imageList:FireServer()
		end,
		hide = function()
			panel:hide()
		end,
	}
end

function AdminTitleV3Controller.destroy()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, unsubscribe in ipairs(unsubscribers) do
		pcall(unsubscribe)
	end
	table.clear(unsubscribers)
	if panel then
		panel:hide(true)
		panel = nil
	end
end

return AdminTitleV3Controller
