--!nocheck
--[[
  Club Kit dock panel — "Aurora Dusk" visual system.
  Config / Diagnostics / Engine / Tools / Packager / Settings.

  Shell layout (verified live in this Studio install — see AGENTS.md):
    - Sidebar: fixed Brand block (plain Frame, non-interactive) + nav (flat
      TextButtons, DIRECT children of Sidebar, opaque backgrounds).
    - Content: one ScrollingFrame; only the ACTIVE page is mounted under pageHost
      so AutomaticCanvasSize never sums hidden pages. A floating "unsaved changes"
      bar lives OUTSIDE the ScrollingFrame so it stays put while the page scrolls.
    - Inter FontFace (Theme.fontFaces) everywhere; body + chrome both.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local Theme = require(script.Parent.DovetailTheme)
local UI = require(script.Parent.ClubKitUI)
local Motion = require(script.Parent.PanelMotion)
local ConfigEditCore = require(script.Parent.ConfigEditCore)
local SourceSyncCore = require(script.Parent.SourceSyncCore)
local PluginSyncCore = require(script.Parent.PluginSyncCore)
local PackagerCore = require(script.Parent.PackagerCore)
local CarryUploadCore = require(script.Parent.CarryUploadCore)
local Manifest = require(script.Parent.ClubKitManifest)

local ClubKitPanel = {}

export type CreateOpts = {
	plugin: Plugin,
	onDismiss: (() -> ())?,
	onGenerateTools: (() -> ())?,
	mountFromSources: ((sources: { [string]: string }) -> boolean)?,
	applyPluginSoftUpdate: ((tag: string, onProgress: any) -> any)?,
}

local CONFIG_META = {
	general = { title = "General", subtitle = "Club name, group, and owner settings." },
	features = { title = "Features", subtitle = "Turn kit features on or off (from ClubKitConfigSchema manifest)." },
	membership = { title = "Membership", subtitle = "Tier names, prices, and game pass IDs." },
	donation = { title = "Donations", subtitle = "Provider, API keys, and donation channels." },
}

local KIT_DEFAULT_LOGO_ID = "79426970537296"

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
end

local function grid2(parent: Instance, order: number, cellH: number): Frame
	local g = Instance.new("Frame")
	g.Name = "Grid2"
	g.BackgroundTransparency = 1
	g.Size = UDim2.new(1, 0, 0, 0)
	g.AutomaticSize = Enum.AutomaticSize.Y
	g.LayoutOrder = order
	g.Parent = parent
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -7, 0, cellH)
	gl.CellPadding = UDim2.new(0, 14, 0, 10)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = g
	return g
end

--[[
  ctx (shared between shell + page builders):
    plugin, opts, toast(msg)
    state: sellerMode, updateChannel, activeConfigPanel, draft, dirty
    badges: { diag: TextLabel, engine: TextLabel }
    hooks: { configRebuild, diagRun, engineCheck, engineSetChannel, saveDiscard, saveCommit }
    setDirty(bool), setSellerNavVisible(bool)
]]

----------------------------------------------------------------
-- CONFIG PAGE
----------------------------------------------------------------
local function buildConfigPage(ctx, page: Frame)
	local state = ctx.state
	local _header, title, subtitle = UI.pageHeader({
		parent = page,
		kicker = "Configuration",
		title = "General",
		subtitle = CONFIG_META.general.subtitle,
		order = 1,
	})

	local bodyHost = Instance.new("Frame")
	bodyHost.Name = "ConfigBody"
	bodyHost.BackgroundTransparency = 1
	bodyHost.Size = UDim2.new(1, 0, 0, 0)
	bodyHost.AutomaticSize = Enum.AutomaticSize.Y
	bodyHost.LayoutOrder = 2
	bodyHost.Parent = page
	UI.vlist(bodyHost, Theme.sizes.sectionGap)

	local tailSpacer = Instance.new("Frame")
	tailSpacer.Name = "TailSpacer"
	tailSpacer.BackgroundTransparency = 1
	tailSpacer.Size = UDim2.new(1, 0, 0, 46)
	tailSpacer.LayoutOrder = 3
	tailSpacer.Parent = page

	local function markDirty()
		state.dirty = true
		ctx.setDirty(true)
	end

	----------------------------------------------------------------
	local function renderGeneral(draft)
		local _c1, b1 = UI.card({ parent = bodyHost, order = 1 })
		UI.cardTitle(b1, "Club identity", nil, 1)
		UI.field({
			parent = b1,
			label = "Club name",
			value = draft.branding.gameName,
			placeholder = "e.g. The Basic Club",
			order = 2,
			onChanged = function(v)
				draft.branding.gameName = v
				markDirty()
			end,
		})
		UI.field({
			parent = b1,
			label = "Welcome message",
			value = draft.branding.welcome,
			placeholder = "Welcome to the club, %s",
			order = 3,
			onChanged = function(v)
				draft.branding.welcome = v
				markDirty()
			end,
		})
		UI.field({
			parent = b1,
			label = "Community logo",
			value = draft.branding.logo,
			placeholder = "rbxassetid://…",
			hint = "Shown on the loading screen, posters, donation boards, and the join-community prompt.",
			order = 4,
			onChanged = function(v)
				draft.branding.logo = v
				markDirty()
			end,
		})

		local _c2, b2 = UI.card({ parent = bodyHost, order = 2 })
		UI.cardTitle(b2, "Group & ownership", "Controls who gets mod, admin, and owner permissions in-game.", 1)
		local g = grid2(b2, 2, 72)
		UI.field({
			parent = g,
			label = "Roblox group ID",
			value = draft.group.groupId > 0 and tostring(draft.group.groupId) or "",
			placeholder = "Not set",
			order = 1,
			onChanged = function(v)
				draft.group.groupId = tonumber(v) or 0
				markDirty()
			end,
		})
		UI.field({
			parent = g,
			label = "Owner user ID",
			value = draft.group.ownerUserId > 0 and tostring(draft.group.ownerUserId) or "",
			placeholder = "Not set",
			order = 2,
			onChanged = function(v)
				draft.group.ownerUserId = tonumber(v) or 0
				markDirty()
			end,
		})
		UI.field({
			parent = b2,
			label = "Owner group rank",
			value = tostring(draft.group.ownerGroupRank),
			placeholder = "255",
			order = 3,
			onChanged = function(v)
				draft.group.ownerGroupRank = tonumber(v) or 255
				markDirty()
			end,
		})
	end

	local function renderFeatures(draft)
		local featureGroups = ConfigEditCore.getFeatureGroups()
		for gi, group in featureGroups do
			local _c, b = UI.card({ parent = bodyHost, order = gi, gap = 0 })
			UI.cardTitle(b, group.name, nil, 1)
			local spacer = Instance.new("Frame")
			spacer.BackgroundTransparency = 1
			spacer.Size = UDim2.new(1, 0, 0, 8)
			spacer.LayoutOrder = 2
			spacer.Parent = b
			for i, item in group.items do
				local key = if type(item) == "table" then (item.key or item[1]) else item[1]
				local label = if type(item) == "table" then (item.label or item[2]) else item[2]
				UI.row({
					parent = b,
					label = label,
					order = 2 + i,
					noBorder = i == #group.items,
					rightWidth = 54,
					right = UI.switch({
						on = draft.features[key] ~= false,
						onChanged = function(on)
							draft.features[key] = on
							markDirty()
						end,
					}),
				})
			end
		end
	end

	local function renderMembership(draft)
		local tierNames = { Tier1 = "Tier 1", Tier2 = "Tier 2", Tier3 = "Tier 3" }
		local order = 0
		for _, tier in { "Tier1", "Tier2", "Tier3" } do
			order += 1
			local m = draft.membership[tier]
			local s = draft.shop[tier]
			local _c, b = UI.card({ parent = bodyHost, order = order })
			UI.cardTitle(b, tierNames[tier] .. "  ·  " .. (m.label or "?"), nil, 1)
			local g = grid2(b, 2, 72)
			UI.field({
				parent = g,
				label = "Display name",
				value = m.label,
				placeholder = "e.g. VIP",
				order = 1,
				onChanged = function(v)
					m.label = v
					markDirty()
				end,
			})
			UI.field({
				parent = g,
				label = "Price (Robux)",
				value = tostring(s.price),
				placeholder = "0",
				order = 2,
				onChanged = function(v)
					s.price = tonumber(v) or 0
					markDirty()
				end,
			})
			UI.field({
				parent = g,
				label = "Game Pass (self-buy)",
				value = s.pass > 0 and tostring(s.pass) or "",
				placeholder = "Not set",
				order = 3,
				onChanged = function(v)
					s.pass = tonumber(v) or 0
					markDirty()
				end,
			})
			UI.field({
				parent = g,
				label = "Product (gifting)",
				value = s.gift > 0 and tostring(s.gift) or "",
				placeholder = "Not set",
				order = 4,
				onChanged = function(v)
					s.gift = tonumber(v) or 0
					markDirty()
				end,
			})
		end
	end

	local function renderDonation(draft)
		local _c1, b1 = UI.card({ parent = bodyHost, order = 1 })
		UI.cardTitle(b1, "Platform & API", "Choose where your community sends donations.", 1)
		local pillHost = UI.pillGroup({
			parent = b1,
			options = {
				{ "bagibagi", "Bagi-Bagi" },
				{ "saweria", "Saweria" },
				{ "sociabuzz", "SociaBuzz" },
			},
			selected = draft.donation.provider,
			onSelect = function(value)
				draft.donation.provider = value
				markDirty()
			end,
		})
		UI.row({
			parent = b1,
			label = "Donation platform",
			order = 2,
			rightWidth = 300,
			right = pillHost,
		})
		UI.field({
			parent = b1,
			label = "Donation API address",
			value = draft.donation.apiUrl,
			placeholder = "https://your-worker.workers.dev",
			hint = "Leave empty for boards-only mode.",
			order = 3,
			onChanged = function(v)
				draft.donation.apiUrl = v
				markDirty()
			end,
		})
		UI.field({
			parent = b1,
			label = "Donation page link",
			value = draft.donation.providerLink,
			placeholder = "https://bagibagi.co/your-page",
			order = 4,
			onChanged = function(v)
				draft.donation.providerLink = v
				markDirty()
			end,
		})

		local _c2, b2 = UI.card({ parent = bodyHost, order = 2 })
		UI.cardTitle(b2, "API keys", "Stored on the server only — never visible to players.", 1)
		UI.field({
			parent = b2,
			label = "Donation API key",
			value = draft.secrets.donationApiSecret,
			placeholder = "Not set",
			order = 2,
			onChanged = function(v)
				draft.secrets.donationApiSecret = v
				markDirty()
			end,
		})
		UI.field({
			parent = b2,
			label = "Game data API key",
			value = draft.secrets.gameDataApiSecret,
			placeholder = "Optional",
			order = 3,
			onChanged = function(v)
				draft.secrets.gameDataApiSecret = v
				markDirty()
			end,
		})

		local _c3, b3 = UI.card({ parent = bodyHost, order = 3 })
		UI.cardTitle(b3, "Donation channels", nil, 1)
		UI.row({
			parent = b3,
			label = "Cash donations",
			desc = "Bagi-Bagi, Saweria, or SociaBuzz",
			order = 2,
			rightWidth = 54,
			right = UI.switch({
				on = draft.donation.cashEnabled,
				onChanged = function(on)
					draft.donation.cashEnabled = on
					markDirty()
				end,
			}),
		})
		UI.row({
			parent = b3,
			label = "Robux donations",
			desc = "Donations via in-game Robux products",
			order = 3,
			rightWidth = 54,
			right = UI.switch({
				on = draft.donation.robuxEnabled,
				onChanged = function(on)
					draft.donation.robuxEnabled = on
					markDirty()
				end,
			}),
		})
		UI.field({
			parent = b3,
			label = "Minimum recorded donation",
			value = tostring(draft.donation.minAmount),
			hint = "Cash donations below this amount won't appear in notifications & boards.",
			order = 4,
			onChanged = function(v)
				draft.donation.minAmount = tonumber(v) or 0
				markDirty()
			end,
		})
	end

	local function rebuild()
		clearChildren(bodyHost)
		local meta = CONFIG_META[state.activeConfigPanel] or CONFIG_META.general
		title.Text = meta.title
		if subtitle then
			subtitle.Text = meta.subtitle
		end
		if not state.dirty then
			state.draft = ConfigEditCore.read()
		end
		local draft = state.draft
		if not draft.ok then
			UI.label({
				parent = bodyHost,
				text = draft.error or "Config unavailable — is Hazastudio_ClubKitConfig in the place?",
				color = Theme.colors.error,
				wrap = true,
				autoHeight = true,
				order = 1,
				size = UDim2.new(1, 0, 0, 0),
			})
			return
		end
		if state.activeConfigPanel == "features" then
			renderFeatures(draft)
		elseif state.activeConfigPanel == "membership" then
			renderMembership(draft)
		elseif state.activeConfigPanel == "donation" then
			renderDonation(draft)
		else
			renderGeneral(draft)
		end
	end

	ctx.hooks.configRebuild = rebuild
	ctx.hooks.saveDiscard = function()
		state.draft = ConfigEditCore.read()
		state.dirty = false
		ctx.setDirty(false)
		rebuild()
		ctx.toast("Changes discarded")
	end
	ctx.hooks.saveCommit = function()
		local draft = state.draft
		ChangeHistoryService:SetWaypoint("ClubKit config before save")
		local report = ConfigEditCore.write({
			branding = draft.branding,
			group = draft.group,
			features = draft.features,
			membership = {
				Tier1 = { label = draft.membership.Tier1.label },
				Tier2 = { label = draft.membership.Tier2.label },
				Tier3 = { label = draft.membership.Tier3.label },
			},
			shop = draft.shop,
			donation = {
				provider = draft.donation.provider,
				providerLink = draft.donation.providerLink,
				apiUrl = draft.donation.apiUrl,
				cashEnabled = draft.donation.cashEnabled,
				robuxEnabled = draft.donation.robuxEnabled,
				minAmount = draft.donation.minAmount,
			},
			secrets = draft.secrets,
		})
		ChangeHistoryService:SetWaypoint("ClubKit config after save")
		if report.ok then
			-- Re-sync draft from Source so tab rebuild matches what was written.
			state.draft = ConfigEditCore.read()
			state.dirty = false
			ctx.setDirty(false)
			ctx.toast("Settings saved — <font color='#64b5ff'>" .. tostring(#report.patched) .. " keys</font>")
		else
			state.dirty = false
			ctx.setDirty(false)
			ctx.toast(tostring(report.message))
		end
	end

	rebuild()
end

----------------------------------------------------------------
-- DIAGNOSTICS PAGE
----------------------------------------------------------------
local function buildDiagnosticsPage(ctx, page: Frame)
	UI.pageHeader({
		parent = page,
		kicker = "Health check",
		title = "Diagnostics",
		subtitle = "Check place readiness before going live — catch problems before players do.",
		order = 1,
	})

	-- Summary stat cards
	local summary = Instance.new("Frame")
	summary.Name = "Summary"
	summary.BackgroundTransparency = 1
	summary.Size = UDim2.new(1, 0, 0, 88)
	summary.LayoutOrder = 2
	summary.Parent = page
	UI.hlist(summary, 12)

	local statLabels = {}
	statLabels.fail = UI.statCard({ parent = summary, order = 1, label = "Failed", color = Theme.colors.error })
	statLabels.warn = UI.statCard({ parent = summary, order = 2, label = "Warnings", color = Theme.colors.warning })
	statLabels.ok = UI.statCard({ parent = summary, order = 3, label = "Passed", color = Theme.colors.success })

	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, 48)
	actions.LayoutOrder = 3
	actions.Parent = page
	UI.hlist(actions, 10)

	local rowsHost = Instance.new("Frame")
	rowsHost.Name = "RowsHost"
	rowsHost.BackgroundTransparency = 1
	rowsHost.Size = UDim2.new(1, 0, 0, 0)
	rowsHost.AutomaticSize = Enum.AutomaticSize.Y
	rowsHost.LayoutOrder = 4
	rowsHost.Parent = page
	UI.vlist(rowsHost, Theme.sizes.sectionGap)

	local lastReport: { string } = {}

	local function runChecks()
		clearChildren(rowsHost)
		local snap = ConfigEditCore.read()
		local counts = { fail = 0, warn = 0, ok = 0 }
		local checks = {}

		local function add(section: string, label: string, status: string, desc: string)
			table.insert(checks, { section = section, label = label, status = status, desc = desc })
			counts[status] += 1
		end

		if not snap.ok then
			add("Configuration", "Buyer config", "fail", snap.error or "ClubKitConfig not found in this place.")
		else
			if snap.group.groupId <= 0 then
				add("Configuration", "Group & owner", "fail", "Group ID is empty — mod/admin/owner roles won't work.")
			else
				add("Configuration", "Group & owner", "ok", "Group " .. tostring(snap.group.groupId) .. " · owner " .. tostring(snap.group.ownerUserId))
			end
			if snap.branding.logo == "" or string.find(snap.branding.logo, KIT_DEFAULT_LOGO_ID, 1, true) then
				add("Configuration", "Community logo", "fail", "Still the kit's default logo — replace it before going live.")
			else
				add("Configuration", "Community logo", "ok", "Custom logo set")
			end
			if snap.secrets.donationApiSecret ~= "" then
				add("Configuration", "Donation API key", "ok", "Set — live donations ready")
			elseif snap.donation.apiUrl ~= "" then
				add("Configuration", "Donation API key", "warn", "API address is set but the key is missing — live donations will fail.")
			else
				add("Configuration", "Donation API key", "fail", "No key & address yet — live donations off (boards still work).")
			end
			local missingPass = 0
			for _, tier in { "Tier1", "Tier2", "Tier3" } do
				if snap.shop[tier].pass == 0 then
					missingPass += 1
				end
			end
			if missingPass > 0 then
				add("Configuration", "Membership game passes", "warn", tostring(missingPass) .. " tier(s) have no game pass yet — players can't buy them.")
			else
				add("Configuration", "Membership game passes", "ok", "All tiers have Game Pass IDs")
			end
		end

		local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
		if kit then
			add("Structure & versions", "Kit components", "ok", "Hazastudio_ClubKit present")
		else
			add("Structure & versions", "Kit components", "fail", "Hazastudio_ClubKit missing — sync Rojo or run Update Engine")
		end
		local localVer = SourceSyncCore.getLocalVersion() or Manifest.KIT_VERSION
		add("Structure & versions", "Kit version", "ok", "Installed " .. tostring(localVer))

		statLabels.fail.Text = tostring(counts.fail)
		statLabels.warn.Text = tostring(counts.warn)
		statLabels.ok.Text = tostring(counts.ok)
		ctx.badges.diag.Text = tostring(counts.fail + counts.warn)
		ctx.badges.diag.Visible = (counts.fail + counts.warn) > 0

		lastReport = {}
		local bySection: { [string]: { any } } = {}
		local sectionOrder = {}
		for _, c in checks do
			if not bySection[c.section] then
				bySection[c.section] = {}
				table.insert(sectionOrder, c.section)
			end
			table.insert(bySection[c.section], c)
			table.insert(lastReport, "[" .. string.upper(c.status) .. "] " .. c.label .. " — " .. c.desc)
		end

		for si, section in sectionOrder do
			local items = bySection[section]
			local _c, b = UI.card({ parent = rowsHost, order = si })
			UI.cardTitle(b, section, nil, 1)
			for i, c in items do
				UI.row({
					parent = b,
					label = c.label,
					desc = c.desc,
					order = 1 + i,
					noBorder = i == #items,
					rightWidth = 24,
					right = UI.statusDot(nil, c.status),
				})
			end
		end
	end

	UI.button({
		parent = actions,
		text = "Run checks",
		variant = "primary",
		small = true,
		order = 1,
		onClick = runChecks,
	})
	UI.button({
		parent = actions,
		text = "Copy report",
		variant = "ghost",
		small = true,
		order = 2,
		onClick = function()
			print("[ClubKit Diagnostics]\n" .. table.concat(lastReport, "\n"))
			ctx.toast("Report printed to Output")
		end,
	})

	ctx.hooks.diagRun = runChecks
	task.defer(runChecks)
end

----------------------------------------------------------------
-- ENGINE PAGE
----------------------------------------------------------------
local function buildEnginePage(ctx, page: Frame)
	local state = ctx.state
	UI.pageHeader({
		parent = page,
		kicker = "Maintenance",
		title = "Engine update",
		subtitle = "Update the place kit. Update the plugin first under Settings if prompted.",
		order = 1,
	})

	local _c1, verBody = UI.card({ parent = page, order = 2 })
	local verRow = Instance.new("Frame")
	verRow.Name = "VersionRow"
	verRow.BackgroundTransparency = 1
	verRow.Size = UDim2.new(1, 0, 0, 30)
	verRow.LayoutOrder = 1
	verRow.Parent = verBody
	UI.hlist(verRow, 10)
	local installed = UI.label({
		parent = verRow,
		text = SourceSyncCore.getLocalVersion() or Manifest.KIT_VERSION,
		weight = "extraBold",
		textSize = 20,
		size = UDim2.new(0, 0, 1, 0),
		order = 1,
	})
	installed.AutomaticSize = Enum.AutomaticSize.X
	UI.tag(verRow, "installed", 2)
	local channelTag = UI.tag(verRow, state.updateChannel, 3, "accent")

	local latestDesc = UI.label({
		parent = verBody,
		text = "Checking…",
		weight = "medium",
		textSize = 13,
		color = Theme.colors.faint,
		order = 2,
		size = UDim2.new(1, 0, 0, 18),
	})

	local _c2, changelogBody = UI.card({ parent = page, order = 3 })
	UI.cardTitle(changelogBody, "What's new", nil, 1)
	local changelog = UI.label({
		parent = changelogBody,
		text = "Run \"Check for updates\" to load release notes.",
		weight = "medium",
		textSize = 13,
		color = Theme.colors.muted,
		wrap = true,
		autoHeight = true,
		yAlign = Enum.TextYAlignment.Top,
		order = 2,
		size = UDim2.new(1, 0, 0, 0),
	})

	local engActions = Instance.new("Frame")
	engActions.Name = "EngineActions"
	engActions.BackgroundTransparency = 1
	engActions.Size = UDim2.new(1, 0, 0, 46)
	engActions.LayoutOrder = 4
	engActions.Parent = page
	UI.hlist(engActions, 10)

	local progressApi = Motion.createProgress(page, 5)

	local status = UI.label({
		parent = page,
		text = "",
		weight = "medium",
		textSize = 12,
		color = Theme.colors.faint,
		wrap = true,
		autoHeight = true,
		order = 6,
		size = UDim2.new(1, 0, 0, 0),
	})

	local _c3, backupBody = UI.card({ parent = page, order = 7 })
	UI.cardTitle(backupBody, "Backups", nil, 1)
	UI.row({
		parent = backupBody,
		label = "No backups yet",
		labelColor = Theme.colors.faint,
		desc = "The previous version is saved automatically before every update — restore anytime.",
		order = 2,
		noBorder = true,
	})

	local pendingTag: string? = nil
	local pluginNeedsUpdate = false
	local updateBusy = false
	local updateEngineBtn

	local function setEngineButtonEnabled(on: boolean)
		if updateEngineBtn then
			updateEngineBtn.Active = on
			updateEngineBtn.AutoButtonColor = on
			updateEngineBtn.BackgroundTransparency = if on then 0 else 0.45
		end
	end

	local function refreshPluginGate()
		local result = PluginSyncCore.checkPluginUpdate(ctx.plugin)
		if result.error then
			-- Don't block engine forever on HTTP fail — surface message, leave button enabled.
			pluginNeedsUpdate = false
			setEngineButtonEnabled(true)
			return result
		end
		pluginNeedsUpdate = result.needsUpdate == true
		setEngineButtonEnabled(not pluginNeedsUpdate)
		ctx.state.pluginNeedsUpdate = pluginNeedsUpdate
		return result
	end

	local function refreshCheck()
		channelTag.Text = state.updateChannel
		local pluginResult = refreshPluginGate()

		local result = SourceSyncCore.checkForUpdates()
		installed.Text = result.localVersion or Manifest.KIT_VERSION
		if result.error then
			pendingTag = nil
			latestDesc.Text = "Check failed"
			status.Text = tostring(result.error)
			ctx.badges.engine.Visible = false
			return
		end
		if result.updateAvailable and result.latestTag then
			pendingTag = result.latestTag
			latestDesc.Text = "Version " .. tostring(result.latestVersion or result.latestTag) .. " available"
			ctx.badges.engine.Text = "1"
			ctx.badges.engine.Visible = true
			status.Text = if pluginNeedsUpdate
				then "Plugin outdated — update under Settings before engine."
				else ""
		else
			pendingTag = nil
			latestDesc.Text = "Kit is up to date."
			ctx.badges.engine.Visible = false
			status.Text = if pluginNeedsUpdate
				then "Plugin outdated — update under Settings before engine."
				else ""
		end
		if result.changelog and #result.changelog > 0 then
			changelog.Text = string.sub(result.changelog, 1, 1800)
		end
		if pluginResult and pluginResult.error and status.Text == "" then
			status.Text = "Plugin check: " .. tostring(pluginResult.error)
		end
		setEngineButtonEnabled(not pluginNeedsUpdate)
	end

	UI.button({
		parent = engActions,
		text = "Check for updates",
		variant = "ghost",
		small = true,
		order = 1,
		onClick = function()
			status.Text = "Checking…"
			task.spawn(refreshCheck)
		end,
	})
	updateEngineBtn = UI.button({
		parent = engActions,
		text = "Update engine",
		variant = "primary",
		small = true,
		order = 2,
		onClick = function()
			if updateBusy then
				return
			end
			if pluginNeedsUpdate then
				ctx.toast("Update the plugin under Settings first")
				status.Text = "Blocked — Settings → Update plugin."
				return
			end
			if not pendingTag then
				refreshCheck()
				if pluginNeedsUpdate then
					ctx.toast("Update the plugin under Settings first")
					return
				end
				if not pendingTag then
					ctx.toast("Already up to date")
					return
				end
			end
			updateBusy = true
			progressApi.busy()
			status.Text = "Updating…"
			task.spawn(function()
				local report = SourceSyncCore.applyEngineUpdate(pendingTag, function(msg, i, total)
					if total and total > 0 then
						progressApi.set(i, total)
					end
					status.Text = tostring(msg or "")
				end)
				updateBusy = false
				progressApi.hide()
				local ok = report and #(report.errors or {}) == 0
				if ok then
					pendingTag = nil
					ctx.badges.engine.Visible = false
					installed.Text = SourceSyncCore.getLocalVersion() or Manifest.KIT_VERSION
					latestDesc.Text = "Kit is up to date."
					status.Text = report.configPatch or "Done — save the place to persist."
					ctx.toast("Engine updated — <font color='#64b5ff'>save the place</font> to persist")
				else
					local err = report and report.errors and report.errors[1] or "Update failed"
					status.Text = tostring(err)
					ctx.toast(tostring(err))
				end
			end)
		end,
	})

	ctx.hooks.engineCheck = refreshCheck
	ctx.hooks.engineSetChannel = function(ch: string)
		channelTag.Text = ch
	end
	if _G.__clubkitEngineAutoChecked ~= true then
		_G.__clubkitEngineAutoChecked = true
		task.defer(refreshCheck)
	else
		task.defer(function()
			latestDesc.Text = "Run Check for updates."
			setEngineButtonEnabled(true)
		end)
	end
end

----------------------------------------------------------------
-- TOOLS PAGE
----------------------------------------------------------------
local function buildToolsPage(ctx, page: Frame)
	UI.pageHeader({
		parent = page,
		kicker = "Utilities",
		title = "Tools",
		subtitle = "Utilities to build and repair place components.",
		order = 1,
	})

	local _c1, genBody = UI.card({ parent = page, order = 2 })
	UI.cardTitle(genBody, "Generate", nil, 1)
	UI.row({
		parent = genBody,
		label = "Generate role tools",
		desc = "Ready-to-use tools for every role (VIP, Mod, Admin, etc.).",
		order = 2,
		right = UI.button({
			text = "Create",
			variant = "primary",
			small = true,
			onClick = function()
				if ctx.opts.onGenerateTools then
					ctx.opts.onGenerateTools()
					ctx.toast("Role tools generated")
				end
			end,
		}),
	})
	UI.row({
		parent = genBody,
		label = "Quick fixes",
		desc = "Ready-made fixes for signs & glowsticks.",
		order = 3,
		noBorder = true,
		right = UI.button({
			text = "Apply",
			variant = "ghost",
			small = true,
			onClick = function()
				print("[ClubKitPanel] RemakeSignAndGlowColor / SoftenDualGlowTrails — see tools/place-fixes/")
				ctx.toast("Place-fix scripts live under tools/place-fixes — run from the command bar")
			end,
		}),
	})

	local _carryCard, carryBody = UI.card({ parent = page, order = 3 })
	UI.cardTitle(carryBody, "Carry animations", "Scan KeyframeSequences and re-upload via CreateAssetAsync.", 1)

	local carryStatus = UI.label({
		parent = carryBody,
		text = "Source: ReplicatedStorage.Carry (or Selection)",
		textSize = Theme.sizes.hint,
		weight = "medium",
		color = Theme.colors.muted,
		wrap = true,
		autoHeight = true,
		order = 2,
		size = UDim2.new(1, 0, 0, 0),
	})

	local groupIdText = ""
	UI.field({
		parent = carryBody,
		label = "Group ID",
		placeholder = "Optional — blank = personal inventory",
		order = 3,
		onChanged = function(v)
			groupIdText = v
		end,
	})

	local dryRun = true
	UI.row({
		parent = carryBody,
		label = "Dry run",
		desc = "Scan only — turn off to upload and patch ClubKitConfig.",
		order = 4,
		rightWidth = 54,
		right = UI.switch({
			on = true,
			onChanged = function(on)
				dryRun = on
			end,
		}),
	})

	local logFrame = Instance.new("ScrollingFrame")
	logFrame.Name = "CarryLog"
	logFrame.BackgroundColor3 = Theme.colors.elevated
	logFrame.BorderSizePixel = 0
	logFrame.Size = UDim2.new(1, 0, 0, 160)
	logFrame.ScrollBarThickness = 4
	logFrame.ScrollBarImageColor3 = Theme.colors.scrollbar
	logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	logFrame.LayoutOrder = 5
	logFrame.Parent = carryBody
	UI.corner(logFrame)
	UI.pad(logFrame, 8)
	UI.vlist(logFrame, 3)

	local logOrder = 0
	local function clearCarryLog()
		for _, child in ipairs(logFrame:GetChildren()) do
			if child:IsA("TextLabel") or child:IsA("TextBox") then
				child:Destroy()
			end
		end
		logOrder = 0
	end

	local function carryLogLine(text: string, color: Color3?)
		logOrder += 1
		local line = Instance.new("TextLabel")
		line.BackgroundTransparency = 1
		line.BorderSizePixel = 0
		line.Size = UDim2.new(1, -4, 0, 0)
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.FontFace = Theme.fontFaces.mono
		line.TextSize = 11
		line.TextColor3 = color or Theme.colors.muted
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextWrapped = true
		line.Text = text
		line.LayoutOrder = logOrder
		line.Parent = logFrame
		task.defer(function()
			logFrame.CanvasPosition =
				Vector2.new(0, math.max(0, logFrame.AbsoluteCanvasSize.Y - logFrame.AbsoluteSize.Y))
		end)
	end

	local carryBusy = false
	local btnRow = Instance.new("Frame")
	btnRow.Name = "CarryActions"
	btnRow.BackgroundTransparency = 1
	btnRow.BorderSizePixel = 0
	btnRow.Size = UDim2.new(1, 0, 0, 36)
	btnRow.LayoutOrder = 6
	btnRow.Parent = carryBody
	UI.hlist(btnRow, 8)

	local scanBtn = UI.button({
		text = "Scan",
		variant = "ghost",
		parent = btnRow,
		size = UDim2.new(0.5, -4, 1, 0),
		order = 1,
		onClick = function()
			local result = CarryUploadCore.planUploads()
			carryStatus.Text = result.sourceLabel
			clearCarryLog()
			for _, line in ipairs(CarryUploadCore.formatPlanLines(result)) do
				carryLogLine(line.text, line.color)
			end
			ctx.toast(if #result.planned > 0 then "Scan complete" else "Nothing to upload — see log")
		end,
	})
	scanBtn.Size = UDim2.new(0.5, -4, 1, 0)

	local uploadBtn = UI.button({
		text = "Upload + patch",
		variant = "primary",
		parent = btnRow,
		size = UDim2.new(0.5, -4, 1, 0),
		order = 2,
		onClick = function()
			if carryBusy then
				return
			end
			carryBusy = true
			uploadBtn.Text = "Working…"
			task.spawn(function()
				local result = CarryUploadCore.planUploads()
				carryStatus.Text = result.sourceLabel
				clearCarryLog()
				for _, line in ipairs(CarryUploadCore.formatPlanLines(result)) do
					carryLogLine(line.text, line.color)
				end

				local groupId = tonumber(groupIdText)
				if groupIdText ~= "" and not groupId then
					carryLogLine("Invalid Group ID.", Theme.colors.error)
					ctx.toast("Invalid Group ID")
					carryBusy = false
					uploadBtn.Text = "Upload + patch"
					return
				end

				local report = CarryUploadCore.runUpload(result.planned, {
					dryRun = dryRun,
					groupId = groupId,
					onLog = carryLogLine,
				})

				if report.abortReason == "dry_run" then
					ctx.toast("Dry run — turn off Dry run to upload")
				elseif report.okCount > 0 then
					ctx.toast(
						string.format(
							"Uploaded <font color='#64b5ff'>%d</font> · failed %d",
							report.okCount,
							report.failCount
						)
					)
				elseif report.abortReason == "empty" then
					ctx.toast("Nothing to upload — see log")
				elseif report.failCount > 0 then
					ctx.toast("Upload failed — check CreateAssetAsync beta")
				end

				carryBusy = false
				uploadBtn.Text = "Upload + patch"
			end)
		end,
	})
	uploadBtn.Size = UDim2.new(0.5, -4, 1, 0)

	local _c2, previewBody = UI.card({ parent = page, order = 4 })
	UI.cardTitle(previewBody, "Preview", nil, 1)
	UI.row({
		parent = previewBody,
		label = "Demo mode",
		desc = "Boards show sample data for preview. Turn off before going live.",
		order = 2,
		noBorder = true,
		rightWidth = 54,
		right = UI.switch({
			on = true,
			onChanged = function(on)
				ctx.toast(on and "Demo mode on" or "Demo mode off — remember for live")
			end,
		}),
	})
end

----------------------------------------------------------------
-- PACKAGER PAGE (seller mode only)
----------------------------------------------------------------
local function buildPackagerPage(ctx, page: Frame)
	UI.pageHeader({
		parent = page,
		kicker = "Distribution",
		title = "Packager",
		subtitle = "Pack the kit into a single file to ship to buyers.",
		order = 1,
	})

	local includeBlankConfig = true

	local _c1, newBody = UI.card({ parent = page, order = 2 })
	UI.cardTitle(newBody, "New package", nil, 1)
	UI.field({
		parent = newBody,
		label = "Package version",
		value = Manifest.KIT_VERSION,
		order = 2,
	})
	UI.row({
		parent = newBody,
		label = "Include blank config",
		desc = "For buyers doing a fresh install.",
		order = 3,
		rightWidth = 54,
		right = UI.switch({
			on = true,
			onChanged = function(on)
				includeBlankConfig = on
			end,
		}),
	})
	UI.row({
		parent = newBody,
		label = "Main template pack",
		desc = "Clone full service contents into Workspace model. Only SyncBhms/BHMS excluded.",
		order = 4,
		noBorder = true,
		right = UI.button({
			text = "Create package",
			variant = "primary",
			small = true,
			onClick = function()
				local folder, report = PackagerCore.collect({
					includeConfig = includeBlankConfig,
					includeSecrets = false,
				})
				PackagerCore.printCollectReport(report)
				if folder then
					Selection:Set({ folder })
					ctx.toast("Template pack ready in <font color='#64b5ff'>Workspace</font>")
				else
					ctx.toast("Package failed — see Output")
				end
			end,
		}),
	})
	UI.row({
		parent = newBody,
		label = "SyncBhms add-on",
		desc = "Legacy BHMS dance pack only (DanceGui, SyncServer, bridges). Optional — unpack + LegacySyncBhms = true.",
		order = 5,
		noBorder = true,
		right = UI.button({
			text = "Create SyncBhms add-on",
			variant = "secondary",
			small = true,
			onClick = function()
				local folder, report = PackagerCore.collectSyncBhmsAddon({})
				PackagerCore.printCollectReport(report)
				if folder then
					Selection:Set({ folder })
					ctx.toast("SyncBhms add-on ready in <font color='#64b5ff'>Workspace</font>")
				else
					ctx.toast("SyncBhms add-on failed — see Output")
				end
			end,
		}),
	})

	local _c2, unpackBody = UI.card({ parent = page, order = 3 })
	UI.cardTitle(unpackBody, "Unpack", nil, 1)
	UI.row({
		parent = unpackBody,
		label = "Install package into this place",
		desc = "Select a Club Kit package folder first. Existing config & secrets are preserved.",
		order = 2,
		noBorder = true,
		right = UI.button({
			text = "Unpack",
			variant = "ghost",
			small = true,
			onClick = function()
				local root = PackagerCore.findPackageRoot(Selection:Get())
				if not root then
					ctx.toast("Select a Club Kit package folder first")
					return
				end
				local report = PackagerCore.unpack(root, {
					replaceExisting = true,
					keepBuyerConfig = true,
					keepBuyerSecrets = true,
				})
				PackagerCore.printUnpackReport(report)
				ctx.toast("Unpack finished — see Output")
			end,
		}),
	})
end

----------------------------------------------------------------
-- SETTINGS PAGE
----------------------------------------------------------------
local function buildSettingsPage(ctx, page: Frame)
	local state = ctx.state
	UI.pageHeader({
		parent = page,
		kicker = "Preferences",
		title = "Settings",
		subtitle = "Plugin preferences for this place.",
		order = 1,
	})

	local _c1, genBody = UI.card({ parent = page, order = 2 })
	UI.cardTitle(genBody, "General", nil, 1)
	UI.row({
		parent = genBody,
		label = "Seller mode",
		desc = "Show the Packager tab for kit distribution. Leave off if you're a buyer.",
		order = 2,
		rightWidth = 54,
		right = UI.switch({
			on = state.sellerMode,
			onChanged = function(on)
				state.sellerMode = on
				ctx.plugin:SetSetting("ClubKit_SellerMode", on)
				ctx.setSellerNavVisible(on)
				ctx.toast(on and "Seller mode on" or "Seller mode off")
			end,
		}),
	})

	local channelPills = UI.pillGroup({
		parent = genBody,
		options = {
			{ "stable", "stable" },
			{ "canary", "canary" },
			{ "nightly", "nightly" },
		},
		selected = state.updateChannel,
		onSelect = function(ch)
			state.updateChannel = ch
			ctx.plugin:SetSetting("ClubKit_UpdateChannel", ch)
			if ctx.hooks.engineSetChannel then
				ctx.hooks.engineSetChannel(ch)
			end
		end,
	})
	UI.row({
		parent = genBody,
		label = "Update channel",
		desc = "Which builds you get when checking for updates. stable recommended.",
		order = 3,
		noBorder = true,
		rightWidth = 250,
		right = channelPills,
	})

	local _c2, aboutBody = UI.card({ parent = page, order = 3 })
	UI.cardTitle(aboutBody, "About", nil, 1)
	UI.row({
		parent = aboutBody,
		label = "Plugin version",
		order = 2,
		rightWidth = 110,
		right = UI.tag(nil, Manifest.PLUGIN_VERSION or Manifest.KIT_VERSION),
	})
	UI.row({
		parent = aboutBody,
		label = "Installed kit version",
		order = 3,
		noBorder = true,
		rightWidth = 110,
		right = UI.tag(nil, SourceSyncCore.getLocalVersion() or Manifest.KIT_VERSION),
	})

	----------------------------------------------------------------
	-- Plugin soft-update (Settings)
	----------------------------------------------------------------
	local _cPlugin, pluginBody = UI.card({ parent = page, order = 4 })
	UI.cardTitle(pluginBody, "Update plugin", nil, 1)
	UI.label({
		parent = pluginBody,
		text = "Soft-update the dock from GitHub (does not rewrite the .rbxm on disk). Do this before Update Engine.",
		weight = "medium",
		textSize = 13,
		color = Theme.colors.muted,
		wrap = true,
		autoHeight = true,
		order = 2,
		size = UDim2.new(1, 0, 0, 0),
	})

	local pluginVerRow = Instance.new("Frame")
	pluginVerRow.Name = "PluginVersionRow"
	pluginVerRow.BackgroundTransparency = 1
	pluginVerRow.Size = UDim2.new(1, 0, 0, 30)
	pluginVerRow.LayoutOrder = 3
	pluginVerRow.Parent = pluginBody
	UI.hlist(pluginVerRow, 10)
	local pluginInstalled = UI.label({
		parent = pluginVerRow,
		text = PluginSyncCore.getLocalPluginVersion(),
		weight = "extraBold",
		textSize = 20,
		size = UDim2.new(0, 0, 1, 0),
		order = 1,
	})
	pluginInstalled.AutomaticSize = Enum.AutomaticSize.X
	UI.tag(pluginVerRow, "plugin", 2)

	local pluginLatestDesc = UI.label({
		parent = pluginBody,
		text = "Checking…",
		weight = "medium",
		textSize = 13,
		color = Theme.colors.faint,
		order = 4,
		size = UDim2.new(1, 0, 0, 18),
	})

	local pluginActions = Instance.new("Frame")
	pluginActions.Name = "PluginActions"
	pluginActions.BackgroundTransparency = 1
	pluginActions.Size = UDim2.new(1, 0, 0, 40)
	pluginActions.LayoutOrder = 5
	pluginActions.Parent = pluginBody
	UI.hlist(pluginActions, 10)

	local pluginStatus = UI.label({
		parent = pluginBody,
		text = "",
		weight = "medium",
		textSize = 12,
		color = Theme.colors.faint,
		wrap = true,
		autoHeight = true,
		order = 6,
		size = UDim2.new(1, 0, 0, 0),
	})

	local pendingPluginTag: string? = nil
	local pluginBusy = false
	local pluginProgress = Motion.createProgress(pluginBody, 7)

	local function refreshPluginCheck()
		pluginInstalled.Text = PluginSyncCore.getLocalPluginVersion()
		local result = PluginSyncCore.checkPluginUpdate(ctx.plugin)
		if result.error then
			pendingPluginTag = nil
			pluginLatestDesc.Text = "Check failed"
			pluginStatus.Text = tostring(result.error)
			ctx.state.pluginNeedsUpdate = false
			return
		end
		if result.needsUpdate and result.tag then
			pendingPluginTag = result.tag
			pluginLatestDesc.Text = "v" .. tostring(result.remoteVersion or result.tag) .. " available"
			pluginStatus.Text = ""
			ctx.state.pluginNeedsUpdate = true
		else
			pendingPluginTag = nil
			pluginLatestDesc.Text = "Plugin is up to date."
			pluginStatus.Text = ""
			ctx.state.pluginNeedsUpdate = false
		end
	end

	UI.button({
		parent = pluginActions,
		text = "Check",
		variant = "ghost",
		small = true,
		order = 1,
		onClick = function()
			pluginStatus.Text = "Checking…"
			task.spawn(refreshPluginCheck)
		end,
	})
	UI.button({
		parent = pluginActions,
		text = "Update plugin",
		variant = "primary",
		small = true,
		order = 2,
		onClick = function()
			if pluginBusy then
				return
			end
			if not ctx.opts.applyPluginSoftUpdate then
				ctx.toast("Soft-update not available — rebuild / reinstall the plugin RBXM")
				return
			end
			if not pendingPluginTag then
				refreshPluginCheck()
				if not pendingPluginTag then
					ctx.toast("Plugin already up to date")
					return
				end
			end
			pluginBusy = true
			pluginProgress.busy()
			pluginStatus.Text = "Updating plugin…"
			local tag = pendingPluginTag
			task.spawn(function()
				local report = ctx.opts.applyPluginSoftUpdate(tag, function(msg, i, total)
					if total and total > 0 then
						pluginProgress.set(i, total)
					end
					pluginStatus.Text = tostring(msg or "")
				end)
				pluginBusy = false
				pluginProgress.hide()
				if report and report.ok then
					print(
						("[ClubKitPackager] Plugin soft-updated to v%s (%d modules)"):format(
							tostring(report.version or "?"),
							report.moduleCount or 0
						)
					)
				else
					local err = report and report.error or "Plugin update failed"
					pluginStatus.Text = tostring(err)
					ctx.toast(tostring(err))
				end
			end)
		end,
	})

	task.defer(refreshPluginCheck)
end

----------------------------------------------------------------
-- SHELL
----------------------------------------------------------------
function ClubKitPanel.create(widget: DockWidgetPluginGui, opts: CreateOpts)
	local plugin = opts.plugin

	local root = Instance.new("Frame")
	root.Name = "ClubKitRoot"
	root.BackgroundColor3 = Theme.colors.page
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = widget

	local ctx = {
		plugin = plugin,
		opts = opts,
		toast = UI.toast(root),
		state = {
			sellerMode = plugin:GetSetting("ClubKit_SellerMode") == true,
			updateChannel = tostring(plugin:GetSetting("ClubKit_UpdateChannel") or "stable"),
			activeConfigPanel = "general",
			draft = nil,
			dirty = false,
		},
		badges = {},
		hooks = {},
	}

	-- ===== Sidebar =====
	-- Paint rule verified live: Sidebar TextButtons must be DIRECT children of
	-- Sidebar with opaque backgrounds. Inactive nav buttons are opaque but
	-- colour-matched to the sidebar fill, so they read as plain text until
	-- hovered/active — airy, not a stack of grey chips.
	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.BackgroundColor3 = Theme.colors.sidebar
	sidebar.BorderSizePixel = 0
	sidebar.Size = UDim2.new(0, Theme.sizes.sidebarW, 1, 0)
	sidebar.ZIndex = 5
	sidebar.Parent = root

	UI.pad(sidebar, 12, 10, 12, 10)
	UI.vlist(sidebar, Theme.sizes.navGap)

	local function sidebarSpacer(height: number, order: number)
		local s = Instance.new("Frame")
		s.Name = "Spacer"
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.Size = UDim2.new(1, 0, 0, height)
		s.LayoutOrder = order
		s.Parent = sidebar
		return s
	end

	-- ---- Brand: logo + wordmark, centered; nav stays left-aligned ----
	do
		local logoSize = Theme.sizes.logo
		local brand = Instance.new("Frame")
		brand.Name = "Brand"
		brand.BackgroundColor3 = Theme.colors.sidebar
		brand.BackgroundTransparency = 0
		brand.BorderSizePixel = 0
		brand.Size = UDim2.new(1, 0, 0, 6 + logoSize + 8 + 34)
		brand.LayoutOrder = 1
		brand.ZIndex = 6
		brand.ClipsDescendants = true
		brand.Parent = sidebar
		UI.pad(brand, 6, 0, 0, 0)
		local brandList = UI.vlist(brand, 8)
		brandList.HorizontalAlignment = Enum.HorizontalAlignment.Center

		local logo = Instance.new("ImageLabel")
		logo.Name = "Logo"
		logo.BackgroundTransparency = 1
		logo.BorderSizePixel = 0
		logo.Image = Theme.assets.studioLogo
		logo.ScaleType = Enum.ScaleType.Fit
		logo.Size = UDim2.fromOffset(logoSize, logoSize)
		logo.LayoutOrder = 1
		logo.ZIndex = 7
		logo.Parent = brand

		local title = Instance.new("TextLabel")
		title.Name = "BrandTitle"
		title.BackgroundTransparency = 1
		title.BorderSizePixel = 0
		title.Size = UDim2.new(1, 0, 0, 34)
		title.LayoutOrder = 2
		title.FontFace = Theme.face("bold")
		title.TextSize = 15
		title.TextColor3 = Theme.colors.text
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.TextYAlignment = Enum.TextYAlignment.Top
		title.RichText = true
		title.Text = string.format(
			"<b>Club Kit</b>\n<font size=\"12\" color=\"#%s\">by Hazastudio  ·  v%s</font>",
			Theme.colors.faint:ToHex(),
			Manifest.KIT_VERSION
		)
		title.ZIndex = 7
		title.Parent = brand
	end

	sidebarSpacer(12, 2)

	local function solidBtn(props: {
		name: string,
		text: string,
		order: number,
		parent: Instance?,
		height: number?,
		leftPad: number?,
		textSize: number?,
		weight: string?,
	}): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = props.name
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.BackgroundColor3 = Theme.colors.sidebar
		btn.BackgroundTransparency = 0
		btn.Size = UDim2.new(1, 0, 0, props.height or Theme.sizes.navH)
		btn.FontFace = Theme.face(props.weight or "medium")
		btn.TextSize = props.textSize or 15
		btn.TextColor3 = Theme.colors.muted
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Text = props.text
		btn.LayoutOrder = props.order
		btn.ZIndex = 6
		btn.ClipsDescendants = false
		btn.Parent = props.parent or sidebar
		UI.corner(btn, Theme.sizes.navCorner)
		UI.pad(btn, 0, 10, 0, props.leftPad or 12)
		Motion.bindPress(btn)
		return btn
	end

	local navButtons: { [string]: TextButton } = {}
	local sellerOnlyNav: { [string]: boolean } = {}
	local pages: { [string]: Frame } = {}
	local activePage = "config"
	local configNavBtns: { [string]: TextButton } = {}

	-- Soft tint active (opaque blend) — no left accent bar.
	local function setNavActive(btn: TextButton, on: boolean, boldWeight: string?)
		if on then
			btn.BackgroundColor3 = Theme.colors.navActive
			btn.BackgroundTransparency = 0
			btn.TextColor3 = Theme.colors.text
			btn.FontFace = Theme.face(boldWeight or "semiBold")
		else
			btn.BackgroundColor3 = Theme.colors.sidebar
			btn.BackgroundTransparency = 0
			btn.TextColor3 = Theme.colors.muted
			btn.FontFace = Theme.face("medium")
		end
	end

	local function setConfigNavActive(panelId: string?)
		for pid, b in configNavBtns do
			setNavActive(b, panelId ~= nil and pid == panelId, "semiBold")
		end
	end

	local function showPage(id: string)
		activePage = id
		local shown = pages[id]
		for pid, frame in pages do
			frame.Visible = pid == id
			frame.Parent = if pid == id then ctx.pageHost else nil
		end
		for nid, btn in navButtons do
			setNavActive(btn, nid == id)
		end
		if id == "config" then
			setConfigNavActive(ctx.state.activeConfigPanel)
		else
			setConfigNavActive(nil)
		end
		ctx.scroll.CanvasPosition = Vector2.zero
		if shown then
			Motion.popIn(shown, 0)
		end
		ctx.refreshStickyBar()
	end

	local function navItem(id: string, label: string, order: number, navOpts: { sellerOnly: boolean?, badge: TextButton? }?)
		navOpts = navOpts or {}
		local btn = solidBtn({
			name = "Nav_" .. id,
			text = label,
			order = order,
		})
		if navOpts.badge then
			navOpts.badge.AnchorPoint = Vector2.new(1, 0.5)
			navOpts.badge.Position = UDim2.new(1, -8, 0.5, 0)
			navOpts.badge.Parent = btn
		end
		btn.MouseButton1Click:Connect(function()
			showPage(id)
		end)
		btn.MouseEnter:Connect(function()
			if activePage ~= id then
				btn.BackgroundColor3 = Theme.colors.hover
				btn.TextColor3 = Theme.colors.text
			end
		end)
		btn.MouseLeave:Connect(function()
			setNavActive(btn, activePage == id)
		end)
		navButtons[id] = btn
		if navOpts.sellerOnly then
			sellerOnlyNav[id] = true
			btn.Visible = ctx.state.sellerMode
		end
		return btn
	end

	local function makeBadge(color: Color3): TextButton
		local b = Instance.new("TextButton")
		b.Name = "Badge"
		b.AutoButtonColor = false
		b.Active = false
		b.BackgroundColor3 = color
		b.BorderSizePixel = 0
		b.Size = UDim2.new(0, 20, 0, 20)
		b.FontFace = Theme.fontFaces.bold
		b.TextSize = 11
		b.TextColor3 = Color3.fromHex("#FFFFFF")
		b.Text = "0"
		b.Visible = false
		b.ZIndex = 8
		UI.corner(b, Theme.sizes.pill)
		return b
	end

	ctx.badges.diag = makeBadge(Theme.colors.error)
	ctx.badges.engine = makeBadge(Theme.colors.blue)

	-- Flat config sections — always visible, no Config parent / collapse.
	local function addConfigNav(panelId: string, label: string, order: number)
		local btn = solidBtn({
			name = "Cfg_" .. panelId,
			text = label,
			order = order,
		})
		btn.MouseButton1Click:Connect(function()
			ctx.state.activeConfigPanel = panelId
			showPage("config")
			setConfigNavActive(panelId)
			if ctx.hooks.configRebuild then
				ctx.hooks.configRebuild()
			end
		end)
		btn.MouseEnter:Connect(function()
			local on = activePage == "config" and ctx.state.activeConfigPanel == panelId
			if not on then
				btn.BackgroundColor3 = Theme.colors.hover
				btn.TextColor3 = Theme.colors.text
			end
		end)
		btn.MouseLeave:Connect(function()
			if activePage == "config" then
				setConfigNavActive(ctx.state.activeConfigPanel)
			else
				setNavActive(btn, false)
			end
		end)
		configNavBtns[panelId] = btn
	end
	addConfigNav("general", "General", 10)
	addConfigNav("features", "Features", 11)
	addConfigNav("membership", "Membership", 12)
	addConfigNav("donation", "Donations", 13)

	navItem("diagnostics", "Diagnostics", 20, { badge = ctx.badges.diag })
	navItem("engine", "Engine", 30, { badge = ctx.badges.engine })
	navItem("tools", "Tools", 40)
	navItem("packager", "Packager", 50, { sellerOnly = true })
	navItem("settings", "Settings", 60)

	function ctx.setSellerNavVisible(on: boolean)
		for nid in sellerOnlyNav do
			local btn = navButtons[nid]
			if btn then
				btn.Visible = on
			end
			if not on and activePage == nid then
				showPage("settings")
			end
		end
	end

	-- ===== Content =====
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundColor3 = Theme.colors.page
	content.BorderSizePixel = 0
	content.ClipsDescendants = true
	content.Position = UDim2.new(0, Theme.sizes.sidebarW, 0, 0)
	content.Size = UDim2.new(1, -Theme.sizes.sidebarW, 1, 0)
	content.ZIndex = 1
	content.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ContentScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.colors.scrollbar
	scroll.Parent = content
	ctx.scroll = scroll

	-- Inset via size/position (more reliable than UIPadding alone in PluginGui).
	local scrollInner = Instance.new("Frame")
	scrollInner.Name = "ScrollInner"
	scrollInner.BackgroundTransparency = 1
	scrollInner.Position = UDim2.new(0, Theme.sizes.contentPadX, 0, Theme.sizes.contentPadY)
	scrollInner.Size = UDim2.new(1, -Theme.sizes.contentPadX * 2, 0, 0)
	scrollInner.AutomaticSize = Enum.AutomaticSize.Y
	scrollInner.Parent = scroll

	local pageHost = Instance.new("Frame")
	pageHost.Name = "PageHost"
	pageHost.BackgroundTransparency = 1
	pageHost.Size = UDim2.new(1, 0, 0, 0)
	pageHost.AutomaticSize = Enum.AutomaticSize.Y
	pageHost.Parent = scrollInner
	ctx.pageHost = pageHost

	-- Floating unsaved bar — solid TextButtons only (no UIPadding / Inter label bugs).
	local stickyBar = Instance.new("Frame")
	stickyBar.Name = "StickySaveBar"
	stickyBar.AnchorPoint = Vector2.new(0.5, 1)
	stickyBar.Position = UDim2.new(0.5, 0, 1, 60)
	stickyBar.BackgroundColor3 = Theme.colors.elevated
	stickyBar.BorderSizePixel = 0
	stickyBar.AutomaticSize = Enum.AutomaticSize.X
	stickyBar.Size = UDim2.new(0, 0, 0, 48)
	stickyBar.Visible = false
	stickyBar.ZIndex = 20
	stickyBar.ClipsDescendants = false
	stickyBar.Parent = content
	UI.corner(stickyBar, Theme.sizes.pill)
	UI.pad(stickyBar, 7, 10, 7, 12)
	UI.hlist(stickyBar, 10).VerticalAlignment = Enum.VerticalAlignment.Center

	local function stickyChip(props: {
		text: string,
		order: number,
		bg: Color3,
		textColor: Color3?,
		width: number,
		onClick: (() -> ())?,
	}): TextButton
		local b = Instance.new("TextButton")
		b.Name = "Sticky_" .. props.text:gsub("%s+", "")
		b.AutoButtonColor = false
		b.Active = props.onClick ~= nil
		b.BorderSizePixel = 0
		b.BackgroundColor3 = props.bg
		b.BackgroundTransparency = 0
		b.Size = UDim2.new(0, props.width, 0, 34)
		b.FontFace = Theme.fontFaces.semiBold
		b.TextSize = 14
		b.TextColor3 = props.textColor or Theme.colors.text
		b.Text = props.text
		b.LayoutOrder = props.order
		b.ZIndex = 21
		b.Parent = stickyBar
		UI.corner(b, Theme.sizes.pill)
		if props.onClick then
			b.MouseButton1Click:Connect(props.onClick)
		end
		return b
	end

	stickyChip({
		text = "  Unsaved changes",
		order = 1,
		bg = Color3.fromHex("#2a2418"),
		textColor = Theme.colors.warning,
		width = 150,
	})
	stickyChip({
		text = "Discard",
		order = 2,
		bg = Theme.colors.hover,
		width = 88,
		onClick = function()
			if ctx.hooks.saveDiscard then
				ctx.hooks.saveDiscard()
			end
		end,
	})
	stickyChip({
		text = "Save changes",
		order = 3,
		bg = Theme.colors.blue,
		width = 128,
		onClick = function()
			if ctx.hooks.saveCommit then
				ctx.hooks.saveCommit()
			end
		end,
	})

	function ctx.refreshStickyBar()
		local visible = ctx.state.dirty and activePage == "config"
		if visible then
			stickyBar.Visible = true
			Motion.tween(stickyBar, { Position = UDim2.new(0.5, 0, 1, -20) }, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		else
			local tw = Motion.tween(stickyBar, { Position = UDim2.new(0.5, 0, 1, 60) }, TweenInfo.new(0.18))
			tw.Completed:Connect(function()
				if not (ctx.state.dirty and activePage == "config") then
					stickyBar.Visible = false
				end
			end)
		end
	end

	function ctx.setDirty(dirty: boolean)
		ctx.state.dirty = dirty
		ctx.refreshStickyBar()
	end

	local function pageFrame(id: string): Frame
		local f = Instance.new("Frame")
		f.Name = "Page_" .. id
		f.BackgroundTransparency = 1
		f.Size = UDim2.new(1, 0, 0, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.Visible = false
		pages[id] = f
		UI.vlist(f, Theme.sizes.sectionGap)
		return f
	end

	buildConfigPage(ctx, pageFrame("config"))
	buildDiagnosticsPage(ctx, pageFrame("diagnostics"))
	buildEnginePage(ctx, pageFrame("engine"))
	buildToolsPage(ctx, pageFrame("tools"))
	buildPackagerPage(ctx, pageFrame("packager"))
	buildSettingsPage(ctx, pageFrame("settings"))

	showPage("config")

	return {
		checkForUpdates = function()
			if ctx.hooks.engineCheck then
				task.spawn(ctx.hooks.engineCheck)
			end
		end,
		runDiagnostics = function()
			if ctx.hooks.diagRun then
				ctx.hooks.diagRun()
			end
		end,
		reloadConfig = function()
			ctx.state.dirty = false
			ctx.refreshStickyBar()
			if ctx.hooks.configRebuild then
				ctx.hooks.configRebuild()
			end
		end,
	}
end

return ClubKitPanel
