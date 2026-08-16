--!strict
-- Client/Controllers/AdminHubController.luau
-- Action-first Admin Hub → CommandLibraryService + Admin Panel (title).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local PermissionDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.PermissionDomain)
local RolesDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.RolesDomain)
local ShopDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local CashCurrencyDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.CashCurrencyDomain)
local DonationAmountFormat = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DonationAmountFormat)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local OverheadController = require(script.Parent.OverheadController)
local AdminHubUI = require(script.Parent.Parent.UI.AdminHubUI)
local MobileScaleService = require(script.Parent.Parent.Services.MobileScaleService)
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

	MobileScaleService.applyAdminHubLayout(gui)
	local ui = AdminHubUI.new(gui)
	local selectedPlayer: PlayerEntry? = nil
	local donateMode = "test"
	local floatSpeed = tonumber(Config.Gravity.DEFAULT_SPEED) or 3
	local restoreSpeed = tonumber(Config.Gravity.DEFAULT_SPEED) or 3
	ui:setFloatSpeed(floatSpeed)
	ui:setRestoreSpeed(restoreSpeed)

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
		ui:setGreetingRole(resolveRole() or "Player")
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
			local box: TextBox
			if ui:usesActionTemplate(body) then
				local found = body:FindFirstChild("AnnounceMessage", true)
				if found and found:IsA("TextBox") then
					box = found
				else
					ui:addFieldLabel(body, "Message")
					box = ui:addTextBox(body, "AnnounceMessage", "Say something to the server…", true)
				end
				local hint = body:FindFirstChild("Hint", true)
				if hint and hint:IsA("TextLabel") then
					hint.Text = "Max " .. tostring(maxLen) .. " characters (Config.Announcement)."
				end
			else
				ui:addFieldLabel(body, "Message")
				box = ui:addTextBox(body, "AnnounceMessage", "Say something to the server…", true)
				ui:addHint(body, "Max " .. tostring(maxLen) .. " characters (Config.Announcement).")
			end
			-- No default message: leave the box empty so the placeholder shows.
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
			local getPicked: () -> string
			if ui:usesActionTemplate(body) then
				local pickHost = body:FindFirstChild("PickGrid", true) or body
				ui:applyPickCardLabels(pickHost, SETROLE_OPTIONS)
				getPicked = ui:bindPickCards(pickHost, "Moderator", function() end)
			else
				ui:addCallout(
					body,
					"RoleCategories keys from ClubKitConfig. Not VIP membership (use Gift). Spenders are leaderboard-only.",
					"soft",
					"Staff role override"
				)
				getPicked = ui:addPickGrid(body, SETROLE_OPTIONS, "Moderator", function() end)
			end
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
			local initial = if tiers[1] then tiers[1].key else "Tier1"
			local getPicked: () -> string
			if ui:usesActionTemplate(body) then
				local pickHost = body:FindFirstChild("PickGrid", true) or body
				ui:applyPickCardLabels(pickHost, tiers)
				local allowed: { [string]: boolean } = {}
				for _, tier in ipairs(tiers) do
					allowed[tier.key] = true
				end
				getPicked = ui:bindPickCards(pickHost, initial, function() end, allowed)
			else
				ui:addCallout(
					body,
					"Config.Gift Tier1 / Tier2 / Tier3 → labels from ClubKitConfig.Membership. Not a staff role.",
					"ok",
					"Membership gift"
				)
				getPicked = ui:addPickGrid(body, tiers, initial, function() end)
			end
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

	local function openGearSpeedSheet(chromeFromActionId: string?)
		local isDropDial = chromeFromActionId == "gravity"
		local sheetTitle = if isDropDial then "Drop speed" else "Float speed"
		local currentSpeed = if isDropDial then restoreSpeed else floatSpeed

		local function applySpeed(nextSpeed: number, closeAfter: boolean?)
			local clamped = math.clamp(
				math.floor(nextSpeed + 0.5),
				tonumber(Config.Gravity.MIN_SPEED) or 1,
				tonumber(Config.Gravity.MAX_SPEED) or 10
			)
			if isDropDial then
				restoreSpeed = clamped
				ui:setRestoreSpeed(restoreSpeed)
				notify("Drop speed → " .. tostring(restoreSpeed), "SUCCESS")
			else
				floatSpeed = clamped
				ui:setFloatSpeed(floatSpeed)
				-- Rise dial applies immediately while floating / for next Ungravity.
				runCommand("/" .. Config.Gravity.CMD_ALIAS_UNGRAVITY .. " " .. tostring(floatSpeed))
				notify("Float speed → " .. tostring(floatSpeed), "SUCCESS")
			end
			if closeAfter then
				ui:closeSheet()
			end
		end

		ui:openSheet("floatSpeed", sheetTitle, function(body)
			local minS = tonumber(Config.Gravity.MIN_SPEED) or 1
			local maxS = tonumber(Config.Gravity.MAX_SPEED) or 10
			local hint = if isDropDial
				then ("Gravity drop kick only (1 soft → 10 hard). Range " .. minS .. "–" .. maxS .. ".")
				else ("Ungravity rise speed only (1 slow → 10 fast). Range " .. minS .. "–" .. maxS .. ".")
			local getSpeed: () -> string
			if ui:usesActionTemplate(body) then
				local calloutTitle = body:FindFirstChild("Title", true)
				if calloutTitle and calloutTitle:IsA("TextLabel") and calloutTitle.Name == "Title" then
					calloutTitle.Text = if isDropDial then "Drop speed" else "Float speed"
				end
				local calloutText = body:FindFirstChild("Text", true)
				if calloutText and calloutText:IsA("TextLabel") and calloutText.Name == "Text" then
					calloutText.Text = hint
				end
				local fieldLabel = body:FindFirstChild("FieldLabel", true)
				if fieldLabel and fieldLabel:IsA("TextLabel") then
					fieldLabel.Text = if isDropDial then "DROP SPEED" else "FLOAT SPEED"
				end
				local chipRow = body:FindFirstChild("ChipRow", true)
				local allowed: { [string]: boolean } = {}
				for n = minS, maxS do
					allowed[tostring(n)] = true
				end
				if chipRow and chipRow:IsA("Frame") then
					getSpeed = ui:bindChipRowTemplate(chipRow, tostring(currentSpeed), function(value)
						local n = tonumber(value)
						if n then
							applySpeed(n, false)
						end
					end, allowed)
				else
					local values = {}
					for n = minS, maxS do
						table.insert(values, tostring(n))
					end
					getSpeed = ui:addChipRow(body, values, tostring(currentSpeed), function(value)
						local n = tonumber(value)
						if n then
							applySpeed(n, false)
						end
					end)
				end
			else
				ui:addCallout(body, hint, "soft", sheetTitle)
				ui:addFieldLabel(body, sheetTitle)
				local values = {}
				for n = minS, maxS do
					table.insert(values, tostring(n))
				end
				getSpeed = ui:addChipRow(body, values, tostring(currentSpeed), function(value)
					local n = tonumber(value)
					if n then
						applySpeed(n, false)
					end
				end)
			end
			ui:setSheetFoot({
				{
					text = "Done",
					primary = true,
					onClick = function()
						applySpeed(tonumber(getSpeed()) or currentSpeed, true)
					end,
				},
			})
		end, nil, chromeFromActionId or "ungravity")
	end

	local function openDonateSheetLegacy(body: GuiObject)
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
				local preview = ui:addPreview(content, if kind == "robux" then "R$ 100" else DonationAmountFormat.formatCash(10000))
				ui:addFieldLabel(content, "Amount")
				amountBox = ui:addTextBox(content, "Amount", defaultAmt)
				amountBox.Text = defaultAmt
				local function syncPreview()
					local n = tonumber(amountBox and amountBox.Text) or 0
					preview.Text = if kind == "robux" then ("R$ " .. tostring(n)) else DonationAmountFormat.formatCash(n)
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
				ui:addFieldLabel(content, "Cash amount (" .. CashCurrencyDomain.getActive().adminHint .. ")")
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
				ui:addFieldLabel(content, "Amount (" .. CashCurrencyDomain.getActive().adminHint .. ")")
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
		content.Parent = body
		rebuildContent(donateMode)
	end

	local function openDonateSheet()
		ui:openSheet("donate", "Donations", function(body)
			if not ui:usesActionTemplate(body) then
				openDonateSheetLegacy(body)
				return
			end

			local ownerOk = isOwnerLike(resolveRole())
			local modeList = body:FindFirstChild("ModeList") or body

			local function modePickExists(key: string): boolean
				for _, d in ipairs(modeList:GetDescendants()) do
					if d:IsA("GuiButton") and tostring(d:GetAttribute("PickKey") or "") == key then
						return true
					end
				end
				return false
			end

			-- Only expose modes that still exist in the GUI ModeList.
			local allowedModes: { [string]: boolean } = { test = true }
			if ownerOk and modePickExists("credit") then
				allowedModes.credit = true
			end
			if ownerOk and modePickExists("edit") then
				allowedModes.edit = true
			end
			if not allowedModes[donateMode] then
				donateMode = "test"
			end

			local kind = "cash"
			local amountBox: TextBox? = nil
			local messageBox: TextBox? = nil
			local wired = { test = false, credit = false, edit = false }

			local function clearInjectedPlayer(panel: Instance)
				local info = panel:FindFirstChild("SelectedPlayerInfo")
				if info then
					info:Destroy()
				end
			end

			local function setPanelVisible(mode: string)
				for _, name in ipairs({ "test", "credit", "edit" }) do
					local panel = body:FindFirstChild("Panel_" .. name)
					if panel and panel:IsA("GuiObject") then
						panel.Visible = name == mode
					end
				end
			end

			local function panelPrimaryText(panel: Instance, fallback: string): string
				local attr = panel:GetAttribute("PrimaryText")
				if type(attr) == "string" and attr ~= "" then
					return attr
				end
				return fallback
			end

			local function bindAmountChips(panel: Frame, chips: { string }, box: TextBox)
				local amountRow = ui:findChipRowContaining(panel, "10000")
					or ui:findChipRowContaining(panel, "10")
					or ui:findChipRowContaining(panel, chips[1] or "")
				if amountRow then
					ui:fillChipRow(amountRow, chips, box.Text, function(value)
						box.Text = value
					end)
				end
			end

			local function askDonatePlayerThenReturn()
				ui:closeSheet(true)
				askPlayer("Manual donation — who?", function(entry)
					selectedPlayer = entry
					openDonateSheet()
				end)
			end

			local function setOwnerFoot(mode: string, panel: Frame)
				if not selectedPlayer then
					-- Reverse flow: sheet opens first; Manual mode asks for a player only when needed.
					ui:setSheetFoot({
						{
							text = "Pick player",
							primary = true,
							onClick = askDonatePlayerThenReturn,
						},
					})
					return
				end
				if mode == "credit" then
					ui:setSheetFoot({
						{
							text = "Change player",
							primary = false,
							onClick = askDonatePlayerThenReturn,
						},
						{
							text = panelPrimaryText(panel, "Give credit"),
							primary = true,
							onClick = function()
								if not selectedPlayer then
									return
								end
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
					ui:setSheetFoot({
						{
							text = "Change player",
							primary = false,
							onClick = askDonatePlayerThenReturn,
						},
						{
							text = panelPrimaryText(panel, "Apply score edit"),
							primary = true,
							onClick = function()
								if not selectedPlayer then
									return
								end
								local amt = if amountBox then amountBox.Text else "0"
								runCommand("/" .. Config.Donation.CMD_ADD_CASH .. " " .. selectedPlayer.username .. " " .. amt)
								notify("Score updated for " .. selectedPlayer.displayName, "SUCCESS")
								ui:closeSheet()
							end,
						},
					})
				end
			end

			local function refreshOwnerUi(mode: string)
				local panel = body:FindFirstChild("Panel_" .. mode)
				if not panel or not panel:IsA("Frame") then
					return
				end
				clearInjectedPlayer(panel)
				local amount = panel:FindFirstChild("Amount", true)
				local message = panel:FindFirstChild("Message", true)
				amountBox = if amount and amount:IsA("TextBox") then amount else nil
				messageBox = if message and message:IsA("TextBox") then message else nil
				if selectedPlayer then
					ui:showSelectedPlayer(panel, selectedPlayer, askDonatePlayerThenReturn)
				end
				setOwnerFoot(mode, panel)
			end

			local function wireOwnerPanel(mode: string)
				local panel = body:FindFirstChild("Panel_" .. mode)
				if not panel or not panel:IsA("Frame") then
					return
				end
				local amount = panel:FindFirstChild("Amount", true)
				if amount and amount:IsA("TextBox") then
					if amount.Text == "" then
						amount.Text = "10000"
					end
					bindAmountChips(panel, DONATE_IDR_CHIPS, amount)
				end
				local fieldLabels = {}
				for _, child in ipairs(panel:GetChildren()) do
					if child.Name == "FieldLabel" and child:IsA("TextLabel") then
						table.insert(fieldLabels, child)
					end
				end
				if fieldLabels[1] then
					local hint = CashCurrencyDomain.getActive().adminHint
					fieldLabels[1].Text = if mode == "credit"
						then ("Cash amount (" .. hint .. ")")
						else ("Amount (" .. hint .. ")")
				end
			end

			local function setFakeFoot(panel: Frame)
				-- No Target chip: fake preview always attributes to the admin (self).
				ui:setSheetFoot({
					{
						text = panelPrimaryText(panel, "Play fake donations"),
						primary = true,
						onClick = function()
							local amt = if amountBox then amountBox.Text else "0"
							local msg = if messageBox then string.gsub(messageBox.Text, "^%s*(.-)%s*$", "%1") else ""
							local cmd = if kind == "robux" then Config.Donation.CMD_FAKE_ROBUX else Config.Donation.CMD_FAKE_CASH
							local parts = { "/" .. cmd, amt }
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

			local function wireTestPanel()
				local panel = body:FindFirstChild("Panel_test")
				if not panel or not panel:IsA("Frame") then
					return
				end

				clearInjectedPlayer(panel)
				local kindRow = ui:findChipRowContaining(panel, "Cash")
				local amount = panel:FindFirstChild("Amount", true)
				local message = panel:FindFirstChild("Message", true)
				local preview = panel:FindFirstChild("Preview", true)
				amountBox = if amount and amount:IsA("TextBox") then amount else nil
				messageBox = if message and message:IsA("TextBox") then message else nil

				local function syncPreview()
					if not (preview and preview:IsA("TextLabel")) then
						return
					end
					local n = tonumber(amountBox and amountBox.Text) or 0
					preview.Text = if kind == "robux" then ("R$ " .. tostring(n)) else DonationAmountFormat.formatCash(n)
				end

				local function refreshAmountDefaults()
					local defaultAmt = if kind == "robux" then "100" else "10000"
					if amountBox then
						amountBox.Text = defaultAmt
						bindAmountChips(panel, if kind == "robux" then DONATE_ROBUX_CHIPS else DONATE_IDR_CHIPS, amountBox)
					end
					syncPreview()
				end

				if kindRow then
					ui:bindChipRowTemplate(kindRow, if kind == "robux" then "Robux" else "Cash", function(value)
						kind = if value == "Robux" then "robux" else "cash"
						refreshAmountDefaults()
					end)
				end

				if amountBox then
					if amountBox.Text == "" then
						amountBox.Text = if kind == "robux" then "100" else "10000"
					end
					bindAmountChips(panel, if kind == "robux" then DONATE_ROBUX_CHIPS else DONATE_IDR_CHIPS, amountBox)
					amountBox:GetPropertyChangedSignal("Text"):Connect(syncPreview)
				end
				if messageBox and messageBox.Text == "" then
					messageBox.Text = "Thanks!"
				end
				syncPreview()
				setFakeFoot(panel)
			end

			local function bindMode(mode: string)
				donateMode = mode
				setPanelVisible(mode)
				if mode == "test" then
					if not wired.test then
						wired.test = true
						wireTestPanel()
					else
						local panel = body:FindFirstChild("Panel_test")
						if panel and panel:IsA("Frame") then
							local amount = panel:FindFirstChild("Amount", true)
							local message = panel:FindFirstChild("Message", true)
							amountBox = if amount and amount:IsA("TextBox") then amount else nil
							messageBox = if message and message:IsA("TextBox") then message else nil
							setFakeFoot(panel)
						end
					end
				else
					if not wired[mode] then
						wired[mode] = true
						wireOwnerPanel(mode)
					end
					refreshOwnerUi(mode)
				end
			end

			ui:bindPickCards(modeList, donateMode, bindMode, allowedModes)
			bindMode(donateMode)
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
			local speed = ui:getFloatSpeed()
			floatSpeed = speed
			runCommand("/" .. Config.Gravity.CMD_ALIAS_UNGRAVITY .. " " .. tostring(speed))
			notify("Ungravity — speed " .. tostring(speed), "SUCCESS")
		elseif actionId == "gravity" then
			local intensity = ui:getRestoreSpeed()
			restoreSpeed = intensity
			runCommand("/" .. Config.Gravity.CMD_ALIAS .. " " .. tostring(intensity))
			notify("Gravity restored — drop " .. tostring(intensity), "SUCCESS")
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
	ui:bindGear(function(actionId: string)
		if not gateAllows("admin") then
			notify("Not available for your role", "WARNING")
			return
		end
		openGearSpeedSheet(actionId)
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
