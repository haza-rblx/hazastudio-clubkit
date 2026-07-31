--!strict
-- Client/Controllers/AdminHubController.luau
-- Action-first Admin Hub → CommandLibraryService + Admin Panel (title).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)
local ShopDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local OverheadController = require(script.Parent.OverheadController)
local AdminHubUI = require(script.Parent.Parent.UI.AdminHubUI)
local createCommandLibraryService = require(script.Parent.Parent.Services.CommandLibraryService)
local NotifService = require(script.Parent.Parent.Services.NotifService)

type PlayerEntry = AdminHubUI.PlayerEntry

local SETROLE_OPTIONS = {
	{ key = "CoOwner", label = "Co-Owner", desc = "Leadership · admin panel" },
	{ key = "Staff", label = "Staff", desc = "Leadership · admin panel" },
	{ key = "Moderator", label = "Moderator", desc = "Moderation · announce · teleport" },
	{ key = "DJ", label = "DJ", desc = "Content · music" },
	{ key = "LeadDance", label = "Lead Dance", desc = "Content · music" },
	{ key = "Streamer", label = "Streamer", desc = "Content · music" },
	{ key = "Influencer", label = "Influencer", desc = "Content · music" },
}

local DONATE_IDR_CHIPS = { "10000", "20000", "50000", "100000", "200000", "500000", "1000000" }
local DONATE_ROBUX_CHIPS = { "10", "80", "150", "250", "500", "1000", "2000", "5000" }

local ACTIONS = {
	{ id = "bring", group = "utilities", gate = "mod", needsPlayer = true, title = "Bring here" },
	{ id = "to", group = "utilities", gate = "mod", needsPlayer = true, title = "Go to" },
	{ id = "announce", group = "utilities", gate = "mod", needsPlayer = false, title = "Announce" },
	{ id = "ungravity", group = "utilities", gate = "admin", needsPlayer = false, title = "Ungravity" },
	{ id = "gravity", group = "utilities", gate = "admin", needsPlayer = false, title = "Gravity" },
	{ id = "role", group = "access", gate = "admin", needsPlayer = true, title = "Set role" },
	{ id = "gift", group = "access", gate = "admin", needsPlayer = true, title = "Gift membership" },
	{ id = "title", group = "identity", gate = "admin", needsPlayer = true, title = "Custom title" },
	{ id = "donate", group = "donations", gate = "admin", needsPlayer = false, title = "Donations" },
	{ id = "refresh", group = "donations", gate = "owner", needsPlayer = false, title = "Reload boards" },
}

local _connections: { RBXScriptConnection } = {}
local _unsubs: { () -> () } = {}

local function notify(message: string, notifType: NotifService.NotifType?, dedupeKey: string?)
	NotifService.show({
		message = message,
		notifType = notifType or "INFO",
		domain = "admin",
		title = "Admin Panel",
		dedupeKey = dedupeKey,
	})
end

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function destroy()
	for _, unsub in ipairs(_unsubs) do
		unsub()
	end
	table.clear(_unsubs)
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
end

local function giftTierOptions(): { { key: string, label: string, desc: string? } }
	local out = {}
	for _, tier in ipairs(Config.Membership.SHOP_TIERS or { "Tier1", "Tier2", "Tier3" }) do
		local entry = ShopDomain.getCatalogEntry(tier)
		local label = if entry and type(entry.name) == "string" then entry.name else tier
		local cfg = Config.Membership.Tiers and Config.Membership.Tiers[tier]
		if type(cfg) == "table" and type(cfg.label) == "string" then
			label = cfg.label
		end
		table.insert(out, {
			key = tier,
			label = label,
			desc = tier .. " · membership gift",
		})
	end
	return out
end

local function init(deps: {
	remotes: Folder?,
	icon: any?,
	openTitlePanel: (() -> ())?,
})
	local log = Logger.new("Client.AdminHubController")
	local localPlayer = Players.LocalPlayer
	local topbarIcon = deps.icon
	local openTitlePanel = deps.openTitlePanel
	local commandService = createCommandLibraryService()

	local hubName = Config.Admin.HUB_GUI_NAME or "04-AdminHub"
	local gui = localPlayer.PlayerGui:FindFirstChild(hubName) :: ScreenGui?
	if not gui then
		gui = localPlayer.PlayerGui:WaitForChild(hubName, Config.Admin.GUI_WAIT_TIMEOUT or 30) :: ScreenGui?
	end
	if not gui then
		log:warn("Admin Hub GUI missing; controller skipped", { guiName = hubName })
		return {}
	end

	local ui = AdminHubUI.new(gui)
	local selectedPlayer: PlayerEntry? = nil
	local donateMode = "test"
	local floatSpeed = tonumber(Config.Gravity.DEFAULT_SPEED) or 3
	ui:setFloatSpeed(floatSpeed)

	local function resolveRole(): string?
		return OverheadController.getPlayerRole(localPlayer.UserId)
	end

	local function resolveMembership(): string?
		return OverheadController.getPlayerEffectiveMembership(localPlayer.UserId)
	end

	local function isOwnerLike(role: string?): boolean
		if PermissionDomain.isAdminUser(localPlayer.UserId) then
			return true
		end
		local key = RolesDomain.normalizeRoleKey(role)
		return key == "Owner" or key == "CoOwner"
	end

	local function canAccessHub(): boolean
		local role = resolveRole()
		local membership = resolveMembership()
		if PermissionDomain.isAdminUser(localPlayer.UserId) then
			return true
		end
		return PermissionDomain.canUseAdminPanel(role, localPlayer.UserId)
			or PermissionDomain.canAnnounce(role, membership)
			or PermissionDomain.canTeleport(role, membership)
	end

	local function gateAllows(gate: string): boolean
		local role = resolveRole()
		local membership = resolveMembership()
		if gate == "mod" then
			return PermissionDomain.canAnnounce(role, membership)
				or PermissionDomain.canTeleport(role, membership)
				or PermissionDomain.canUseAdminPanel(role, localPlayer.UserId)
				or PermissionDomain.isAdminUser(localPlayer.UserId)
		end
		if gate == "admin" then
			return PermissionDomain.canUseAdminPanel(role, localPlayer.UserId)
		end
		if gate == "owner" then
			return isOwnerLike(role)
		end
		return false
	end

	local function refreshAllowedActions()
		local allowed: { [string]: boolean } = {}
		for _, action in ipairs(ACTIONS) do
			allowed[action.id] = gateAllows(action.gate)
		end
		ui:setAllowedActions(allowed)
	end

	local function syncIconEnabled()
		if not topbarIcon then
			return
		end
		local enabled = canAccessHub()
		topbarIcon:setEnabled(enabled)
		if not enabled and ui:isVisible() then
			ui:hide()
			topbarIcon:deselect()
		end
	end

	local function runCommand(commandText: string)
		commandService:execute(commandText)
		log:info("AdminHub execute", { commandText = commandText })
	end

	local function refreshPlayers()
		local list: { PlayerEntry } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			table.insert(list, {
				userId = player.UserId,
				username = player.Name,
				displayName = player.DisplayName,
				role = OverheadController.getPlayerRole(player.UserId) or "Player",
			})
		end
		ui:setPlayers(list)
	end

	local function findAction(id: string)
		for _, action in ipairs(ACTIONS) do
			if action.id == id then
				return action
			end
		end
		return nil
	end

	local function askPlayer(title: string, thenDo: (PlayerEntry) -> ())
		refreshPlayers()
		ui:openPlayerPopup(title, function(entry)
			selectedPlayer = entry
			thenDo(entry)
		end)
	end

	local function openAnnounceSheet()
		ui:openSheet("announce", "Announce", function(body)
			local maxLen = tonumber(Config.Announcement.MAX_MESSAGE_LENGTH) or 180
			ui:addFieldLabel(body, "Message")
			local box = ui:addTextBox(body, "AnnounceMessage", "Say something to the server…", true)
			box.Text = "Welcome to the club!"
			ui:addHint(body, "Max " .. tostring(maxLen) .. " characters (Config.Announcement).")
			ui:setSheetFoot({
				{
					text = "Send announce",
					primary = true,
					onClick = function()
						local msg = string.gsub(box.Text, "^%s*(.-)%s*$", "%1")
						if msg == "" then
							notify("Message is empty", "WARNING")
							return
						end
						if #msg > maxLen then
							msg = string.sub(msg, 1, maxLen)
						end
						runCommand("/" .. Config.Announcement.CMD_ALIAS_ANNOUNCE .. " " .. msg)
						notify("Announce sent", "SUCCESS")
						ui:closeSheet()
					end,
				},
			})
		end)
	end

	local function openRoleSheet(entry: PlayerEntry)
		ui:openSheet("role", "Set role", function(body)
			ui:showSelectedPlayer(body, entry, function()
				ui:closeSheet(true)
				askPlayer("Set role — who?", function(nextPlayer)
					openRoleSheet(nextPlayer)
				end)
			end)
			ui:addCallout(
				body,
				"RoleCategories keys from ClubKitConfig. Not VIP membership (use Gift). Spenders are leaderboard-only.",
				"soft",
				"Staff role override"
			)
			local getPicked = ui:addPickGrid(body, SETROLE_OPTIONS, "Moderator", function() end)
			ui:setSheetFoot({
				{
					text = "Unset role",
					primary = false,
					onClick = function()
						runCommand("/" .. Config.SetRole.CMD_ALIAS_UNSET .. " " .. entry.username)
						notify("Role cleared on " .. entry.displayName, "SUCCESS")
						ui:closeSheet()
					end,
				},
				{
					text = "Apply role",
					primary = true,
					onClick = function()
						local roleKey = getPicked()
						runCommand("/" .. Config.SetRole.CMD_ALIAS_SET .. " " .. entry.username .. " " .. roleKey)
						notify(entry.displayName .. " → " .. roleKey, "SUCCESS")
						ui:closeSheet()
					end,
				},
			})
		end)
	end

	local function openGiftSheet(entry: PlayerEntry)
		local tiers = giftTierOptions()
		ui:openSheet("gift", "Gift membership", function(body)
			ui:showSelectedPlayer(body, entry, function()
				ui:closeSheet(true)
				askPlayer("Gift — who?", function(nextPlayer)
					openGiftSheet(nextPlayer)
				end)
			end)
			ui:addCallout(
				body,
				"Config.Gift Tier1 / Tier2 / Tier3 → labels from ClubKitConfig.Membership. Not a staff role.",
				"ok",
				"Membership gift"
			)
			local initial = if tiers[1] then tiers[1].key else "Tier1"
			local getPicked = ui:addPickGrid(body, tiers, initial, function() end)
			ui:setSheetFoot({
				{
					text = "Ungift",
					primary = false,
					onClick = function()
						runCommand("/" .. Config.Gift.CMD_ALIAS_UNGIFT .. " " .. entry.username .. " " .. getPicked())
						notify("Membership ungifted from " .. entry.displayName, "SUCCESS")
						ui:closeSheet()
					end,
				},
				{
					text = "Gift membership",
					primary = true,
					onClick = function()
						local tier = getPicked()
						runCommand("/" .. Config.Gift.CMD_ALIAS_GIFT .. " " .. entry.username .. " " .. tier)
						notify("Gifted " .. tier .. " → " .. entry.displayName, "SUCCESS")
						ui:closeSheet()
					end,
				},
			})
		end)
	end

	local function openFloatSpeedSheet()
		ui:openSheet("floatSpeed", "Float speed", function(body)
			local minS = tonumber(Config.Gravity.MIN_SPEED) or 1
			local maxS = tonumber(Config.Gravity.MAX_SPEED) or 10
			ui:addCallout(
				body,
				"Used when Ungravity floats everyone. Range " .. minS .. "–" .. maxS .. ".",
				"soft",
				"Float speed"
			)
			ui:addFieldLabel(body, "Float speed")
			local values = {}
			for n = minS, maxS do
				table.insert(values, tostring(n))
			end
			local getSpeed = ui:addChipRow(body, values, tostring(floatSpeed), function(value)
				floatSpeed = tonumber(value) or floatSpeed
				ui:setFloatSpeed(floatSpeed)
			end)
			ui:setSheetFoot({
				{
					text = "Done",
					primary = true,
					onClick = function()
						floatSpeed = tonumber(getSpeed()) or floatSpeed
						ui:setFloatSpeed(floatSpeed)
						notify("Float speed → " .. tostring(floatSpeed), "SUCCESS")
						ui:closeSheet()
					end,
				},
			})
		end)
	end

	local function openDonateSheet()
		ui:openSheet("donate", "Donations", function(body)
			local modes = {
				{ key = "test", label = "Fake donations", desc = "VFX only — player or everyone", ownerOnly = false },
				{ key = "credit", label = "Give credit", desc = "Real cash credit + FX", ownerOnly = true },
				{ key = "edit", label = "Edit score", desc = "Manual board correction", ownerOnly = true },
			}
			local ownerOk = isOwnerLike(resolveRole())
			if (donateMode == "credit" or donateMode == "edit") and not ownerOk then
				donateMode = "test"
			end

			local modeOptions = {}
			for _, m in ipairs(modes) do
				if not m.ownerOnly or ownerOk then
					table.insert(modeOptions, { key = m.key, label = m.label, desc = m.desc })
				end
			end

			local content = Instance.new("Frame")
			content.Name = "DonateContent"
			content.BackgroundTransparency = 1
			content.Size = UDim2.new(1, 0, 0, 0)
			content.AutomaticSize = Enum.AutomaticSize.Y
			content.Parent = body
			local contentLay = Instance.new("UIListLayout")
			contentLay.FillDirection = Enum.FillDirection.Vertical
			contentLay.Padding = UDim.new(0, 18)
			contentLay.Parent = content

			local kind = "cash"
			local fakeTarget = "player"
			local amountBox: TextBox? = nil
			local messageBox: TextBox? = nil

			local function rebuildContent(mode: string)
				for _, child in ipairs(content:GetChildren()) do
					if not child:IsA("UIListLayout") then
						child:Destroy()
					end
				end
				amountBox = nil
				messageBox = nil

				if mode == "test" then
					ui:addCallout(content, "Plays donate VFX only — board score unchanged.", "soft", "Does not save.")
					ui:addFieldLabel(content, "Target")
					local getTarget = ui:addChipRow(content, { "Player", "Everyone" }, if fakeTarget == "everyone" then "Everyone" else "Player", function(value)
						fakeTarget = if value == "Everyone" then "everyone" else "player"
						rebuildContent(mode)
					end)
					fakeTarget = if getTarget() == "Everyone" then "everyone" else "player"

					if fakeTarget == "player" then
						if selectedPlayer then
							ui:showSelectedPlayer(content, selectedPlayer, function()
								ui:closeSheet(true)
								askPlayer("Fake donations — who?", function(entry)
									selectedPlayer = entry
									openDonateSheet()
								end)
							end)
						else
							ui:addCallout(content, "Pick a player for per-player fake donations, or switch target to Everyone.", "soft", "Pick a player")
						end
					end

					ui:addFieldLabel(content, "Currency")
					local getKind = ui:addChipRow(content, { "Cash", "Robux" }, if kind == "robux" then "Robux" else "Cash", function(value)
						kind = if value == "Robux" then "robux" else "cash"
						rebuildContent(mode)
					end)
					kind = if getKind() == "Robux" then "robux" else "cash"

					local defaultAmt = if kind == "robux" then "100" else "10000"
					local preview = ui:addPreview(content, if kind == "robux" then "R$ 100" else "Rp 10000")
					ui:addFieldLabel(content, "Amount")
					amountBox = ui:addTextBox(content, "Amount", defaultAmt)
					amountBox.Text = defaultAmt
					local function syncPreview()
						local n = tonumber(amountBox and amountBox.Text) or 0
						preview.Text = if kind == "robux" then ("R$ " .. tostring(n)) else ("Rp " .. tostring(n))
					end
					amountBox:GetPropertyChangedSignal("Text"):Connect(syncPreview)
					syncPreview()
					local chips = if kind == "robux" then DONATE_ROBUX_CHIPS else DONATE_IDR_CHIPS
					ui:addChipRow(content, chips, amountBox.Text, function(value)
						if amountBox then
							amountBox.Text = value
						end
					end)
					ui:addFieldLabel(content, "Message")
					messageBox = ui:addTextBox(content, "Message", "Optional…", true)
					messageBox.Text = "Thanks!"

					if fakeTarget == "player" and not selectedPlayer then
						ui:setSheetFoot({
							{
								text = "Pick player",
								primary = true,
								onClick = function()
									ui:closeSheet(true)
									askPlayer("Fake donations — who?", function(entry)
										selectedPlayer = entry
										openDonateSheet()
									end)
								end,
							},
						})
					else
						ui:setSheetFoot({
							{
								text = "Play fake donations",
								primary = true,
								onClick = function()
									local amt = if amountBox then amountBox.Text else "0"
									local msg = if messageBox then string.gsub(messageBox.Text, "^%s*(.-)%s*$", "%1") else ""
									local cmd = if kind == "robux" then Config.Donation.CMD_FAKE_ROBUX else Config.Donation.CMD_FAKE_CASH
									local parts = { "/" .. cmd }
									if fakeTarget == "player" and selectedPlayer then
										table.insert(parts, selectedPlayer.username)
									end
									table.insert(parts, amt)
									if msg ~= "" then
										table.insert(parts, msg)
									end
									runCommand(table.concat(parts, " "))
									notify("Fake donations played", "SUCCESS")
									ui:closeSheet()
								end,
							},
						})
					end
					return
				end

				-- credit / edit — owner
				if not selectedPlayer then
					ui:addCallout(content, "This owner ledger action needs a target player before you can continue.", "soft", "Player required.")
					ui:setSheetFoot({
						{
							text = "Pick player",
							primary = true,
							onClick = function()
								ui:closeSheet(true)
								askPlayer("Donations — who?", function(entry)
									selectedPlayer = entry
									openDonateSheet()
								end)
							end,
						},
					})
					return
				end

				ui:showSelectedPlayer(content, selectedPlayer, function()
					ui:closeSheet(true)
					askPlayer("Donations — who?", function(entry)
						selectedPlayer = entry
						openDonateSheet()
					end)
				end)

				if mode == "credit" then
					ui:addCallout(content, "Adds a real cash credit for this player and plays donate FX.", "ok", "Saves to the board.")
					ui:addFieldLabel(content, "Cash amount (IDR)")
					amountBox = ui:addTextBox(content, "Amount", "10000")
					amountBox.Text = "10000"
					ui:addChipRow(content, DONATE_IDR_CHIPS, "10000", function(value)
						if amountBox then
							amountBox.Text = value
						end
					end)
					ui:addFieldLabel(content, "Message")
					messageBox = ui:addTextBox(content, "Message", "Optional…", true)
					ui:setSheetFoot({
						{
							text = "Give credit",
							primary = true,
							onClick = function()
								local amt = if amountBox then amountBox.Text else "0"
								local msg = if messageBox then string.gsub(messageBox.Text, "^%s*(.-)%s*$", "%1") else ""
								local parts = { "/" .. Config.Donation.CMD_DONATE_CASH, selectedPlayer.username, amt }
								if msg ~= "" then
									table.insert(parts, msg)
								end
								runCommand(table.concat(parts, " "))
								notify("Credit sent to " .. selectedPlayer.displayName, "SUCCESS")
								ui:closeSheet()
							end,
						},
					})
				else
					ui:addCallout(content, "Changes the board number directly — no donate FX.", "warn", "Manual fix.")
					ui:addFieldLabel(content, "Amount (IDR)")
					amountBox = ui:addTextBox(content, "Amount", "10000")
					amountBox.Text = "10000"
					ui:addChipRow(content, DONATE_IDR_CHIPS, "10000", function(value)
						if amountBox then
							amountBox.Text = value
						end
					end)
					ui:setSheetFoot({
						{
							text = "Apply score edit",
							primary = true,
							onClick = function()
								local amt = if amountBox then amountBox.Text else "0"
								runCommand("/" .. Config.Donation.CMD_ADD_CASH .. " " .. selectedPlayer.username .. " " .. amt)
								notify("Score updated for " .. selectedPlayer.displayName, "SUCCESS")
								ui:closeSheet()
							end,
						},
					})
				end
			end

			ui:addPickGrid(body, modeOptions, donateMode, function(key)
				donateMode = key
				rebuildContent(key)
			end, 1)
			-- Move content below mode list: reparent after pick grid
			content.Parent = body
			rebuildContent(donateMode)
		end)
	end

	local function runInstant(actionId: string, entry: PlayerEntry?)
		if actionId == "bring" and entry then
			runCommand("/" .. Config.Session.CMD_ALIAS_BRING .. " " .. entry.username)
			notify("Brought " .. entry.displayName, "SUCCESS")
		elseif actionId == "to" and entry then
			runCommand("/" .. Config.Session.CMD_ALIAS_TO .. " " .. entry.username)
			notify("Went to " .. entry.displayName, "SUCCESS")
		elseif actionId == "ungravity" then
			runCommand("/" .. Config.Gravity.CMD_ALIAS_UNGRAVITY .. " " .. tostring(floatSpeed))
			notify("Ungravity — speed " .. tostring(floatSpeed), "SUCCESS")
		elseif actionId == "gravity" then
			runCommand("/" .. Config.Gravity.CMD_ALIAS)
			notify("Gravity restored", "SUCCESS")
		elseif actionId == "refresh" then
			runCommand("/" .. Config.Leaderboards.CMD_REFRESH .. " all")
			notify("Boards reloaded", "SUCCESS")
		elseif actionId == "title" and entry then
			notify("Opening title editor…", "INFO")
			ui:hide()
			if topbarIcon then
				topbarIcon:deselect()
			end
			if openTitlePanel then
				openTitlePanel()
			end
		end
	end

	local function handleAction(actionId: string)
		local action = findAction(actionId)
		if not action then
			return
		end
		if not gateAllows(action.gate) then
			notify("Not available for your role", "WARNING")
			return
		end

		if actionId == "announce" then
			openAnnounceSheet()
			return
		end
		if actionId == "donate" then
			openDonateSheet()
			return
		end
		if actionId == "ungravity" or actionId == "gravity" or actionId == "refresh" then
			runInstant(actionId, nil)
			return
		end

		local function afterPlayer(entry: PlayerEntry)
			selectedPlayer = entry
			if actionId == "role" then
				openRoleSheet(entry)
			elseif actionId == "gift" then
				openGiftSheet(entry)
			elseif actionId == "title" then
				runInstant("title", entry)
			else
				runInstant(actionId, entry)
			end
		end

		if action.needsPlayer then
			if selectedPlayer then
				-- Always re-pick for clarity (action-first); sticky optional later
				askPlayer(action.title .. " — who?", afterPlayer)
			else
				askPlayer(action.title .. " — who?", afterPlayer)
			end
			return
		end
	end

	ui:bindClose(function()
		ui:hide()
		if topbarIcon then
			topbarIcon:deselect()
		end
	end)
	ui:bindAction(handleAction)
	ui:bindGear(function(_actionId: string)
		if not gateAllows("admin") then
			notify("Not available for your role", "WARNING")
			return
		end
		openFloatSpeedSheet()
	end)

	if topbarIcon then
		topbarIcon:setEnabled(false)
		track(topbarIcon.selected:Connect(function()
			refreshAllowedActions()
			refreshPlayers()
			ui:show()
		end))
		track(topbarIcon.deselected:Connect(function()
			ui:hide()
		end))
	end

	track(Players.PlayerAdded:Connect(function()
		if ui:isVisible() then
			refreshPlayers()
		end
	end))
	track(Players.PlayerRemoving:Connect(function()
		if ui:isVisible() then
			refreshPlayers()
		end
	end))

	table.insert(_unsubs, OverheadController.subscribeRoleChanged(function(userId: number, _role: string?)
		if userId == localPlayer.UserId then
			refreshAllowedActions()
			syncIconEnabled()
		end
	end))
	table.insert(_unsubs, OverheadController.subscribeOverheadCacheUpdated(function(userId: number?)
		if userId == nil or userId == localPlayer.UserId then
			refreshAllowedActions()
			syncIconEnabled()
		end
	end))

	refreshAllowedActions()
	syncIconEnabled()
	-- Late settle: role often arrives after group rank settle
	task.delay(2, function()
		refreshAllowedActions()
		syncIconEnabled()
	end)
	task.delay(8, function()
		refreshAllowedActions()
		syncIconEnabled()
	end)

	log:info("AdminHubController initialized")
	return {
		show = function()
			refreshAllowedActions()
			refreshPlayers()
			ui:show()
		end,
		hide = function()
			ui:hide()
		end,
		destroy = function()
			ui:destroy()
			if commandService.destroy then
				commandService:destroy()
			end
			destroy()
		end,
	}
end

return { init = init, destroy = destroy }
