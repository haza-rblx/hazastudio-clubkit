--!nocheck
-- Club Kit panel v2 — Engine + Tools (HyperOS / AMOLED), built in Luau.

local SourceSyncCore = require(script.Parent.SourceSyncCore)
local Theme = require(script.Parent.DovetailTheme)
local DovetailUI = require(script.Parent.DovetailUI)

local UpdaterPanel = {}

export type PanelApi = {
	checkForUpdates: () -> (),
	runUpdate: () -> (),
	setStatus: (text: string, tone: string?) -> (),
}

export type CreateOpts = {
	onDismiss: (() -> ())?,
	plugin: Plugin?,
	onGenerateTools: (() -> ())?,
	onCarryFix: (() -> ())?,
}

local C = Theme.colors
local F = Theme.fonts

local BODY_FALLBACK =
	"Keeps the Club Kit engine current. ClubKitConfig and Secrets are never overwritten; missing config keys may be filled in."

local CHANNEL_HINT = {
	stable = "Production / buyer places. Tags: vX.Y.Z",
	canary = "Early features — use a test place. (Check still uses stable until channel sync ships.)",
	nightly = "Dev builds. Expect breakage. (Check still uses stable until channel sync ships.)",
}

local SKIP_TITLE = {
	Added = true,
	Changed = true,
	Fixed = true,
	Removed = true,
	Deprecated = true,
	Security = true,
}

local function truncateNotes(text: string, maxChars: number): string
	local plain = string.gsub(text, "\r\n", "\n")
	if #plain <= maxChars then
		return plain
	end
	return string.sub(plain, 1, maxChars - 1) .. "…"
end

local function cleanupChangelog(raw: string): string
	local plain = DovetailUI.formatMarkdownPlain(raw)
	plain = string.gsub(plain, "^%s*%-?%s*%d%d%d%d%-%d%d%-%d%d%s*\n+", "")
	plain = string.gsub(plain, "^%s*%d%d%d%d%-%d%d%-%d%d%s*\n+", "")
	return plain
end

local function corner(inst: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.sizes.corner)
	c.Parent = inst
end

local function pad(inst: GuiObject, t: number, r: number?, b: number?, l: number?)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t)
	p.PaddingRight = UDim.new(0, r or t)
	p.PaddingBottom = UDim.new(0, b or t)
	p.PaddingLeft = UDim.new(0, l or t)
	p.Parent = inst
	return p
end

local function listLayout(parent: Instance, gap: number?, horizontal: boolean?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap or 0)
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.Parent = parent
	return layout
end

local function makeLabel(parent: Instance, props: {
	text: string?,
	size: number?,
	font: Enum.Font?,
	color: Color3?,
	wrap: boolean?,
	xAlign: Enum.TextXAlignment?,
	yAlign: Enum.TextYAlignment?,
	order: number?,
	height: number?,
	autoY: boolean?,
}): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = props.font or F.body
	label.TextSize = props.size or 13
	label.TextColor3 = props.color or C.text
	label.Text = props.text or ""
	label.TextWrapped = props.wrap == true
	label.TextXAlignment = props.xAlign or Enum.TextXAlignment.Left
	label.TextYAlignment = props.yAlign or Enum.TextYAlignment.Top
	label.LayoutOrder = props.order or 0
	if props.autoY then
		label.Size = UDim2.new(1, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
	elseif props.height then
		label.Size = UDim2.new(1, 0, 0, props.height)
	else
		label.Size = UDim2.new(1, 0, 0, props.size or 13)
	end
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, props: {
	text: string,
	primary: boolean?,
	order: number?,
	height: number?,
}): TextButton
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = true
	btn.BorderSizePixel = 0
	btn.Font = F.bodyBold
	btn.TextSize = 15
	btn.Text = props.text
	btn.Size = UDim2.new(1, 0, 0, props.height or Theme.sizes.buttonHeight)
	btn.LayoutOrder = props.order or 0
	btn.TextColor3 = C.text
	if props.primary then
		btn.BackgroundColor3 = C.blue
	else
		btn.BackgroundColor3 = C.elevated
	end
	corner(btn, Theme.sizes.pillCorner)
	btn.Parent = parent
	return btn
end

local function makeCard(parent: Instance, order: number?): Frame
	local card = Instance.new("Frame")
	card.BackgroundColor3 = C.card
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = order or 0
	card.ClipsDescendants = true
	corner(card, Theme.sizes.corner)
	card.Parent = parent
	return card
end

local function makeSecHead(parent: Instance, title: string, order: number?): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 28)
	row.LayoutOrder = order or 0
	row.Parent = parent
	pad(row, 2, 6, 8, 6)
	makeLabel(row, {
		text = title,
		size = 13,
		font = F.body,
		color = C.faint,
		height = 18,
	})
	return row
end

local function makeListRow(parent: Instance, props: {
	iconText: string,
	iconColor: Color3,
	iconBg: Color3,
	title: string,
	desc: string,
	order: number?,
	disabled: boolean?,
}): TextButton
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = false
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.Size = UDim2.new(1, 0, 0, 70)
	btn.LayoutOrder = props.order or 0
	btn.Active = not props.disabled
	btn.Parent = parent

	local ico = Instance.new("TextLabel")
	ico.BackgroundColor3 = props.iconBg
	ico.BorderSizePixel = 0
	ico.Size = UDim2.fromOffset(40, 40)
	ico.Position = UDim2.new(0, 16, 0.5, -20)
	ico.Font = F.bodyBold
	ico.TextSize = 15
	ico.TextColor3 = props.iconColor
	ico.Text = props.iconText
	ico.Parent = btn
	corner(ico, 12)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 68, 0, 14)
	title.Size = UDim2.new(1, -100, 0, 20)
	title.Font = F.body
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = if props.disabled then C.faint else C.text
	title.Text = props.title
	title.Parent = btn

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.new(0, 68, 0, 36)
	desc.Size = UDim2.new(1, -100, 0, 18)
	desc.Font = F.body
	desc.TextSize = 12
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextColor3 = C.faint
	desc.Text = props.desc
	desc.Parent = btn

	local chev = Instance.new("TextLabel")
	chev.BackgroundTransparency = 1
	chev.AnchorPoint = Vector2.new(1, 0.5)
	chev.Position = UDim2.new(1, -16, 0.5, 0)
	chev.Size = UDim2.fromOffset(16, 24)
	chev.Font = F.body
	chev.TextSize = 22
	chev.TextColor3 = Color3.fromHex("#636366")
	chev.Text = "›"
	chev.Parent = btn

	btn.MouseEnter:Connect(function()
		if btn.Active then
			btn.BackgroundTransparency = 0.96
			btn.BackgroundColor3 = C.text
		end
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundTransparency = 1
	end)

	return btn
end

function UpdaterPanel.create(parent: Instance, opts: CreateOpts?): PanelApi
	opts = opts or {}
	local pluginRef = opts.plugin

	local root = Instance.new("Frame")
	root.Name = "ClubKitPanelV2"
	root.BackgroundColor3 = C.page
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent

	listLayout(root, 0)
	local rootLayout = root:FindFirstChildOfClass("UIListLayout")
	if rootLayout then
		rootLayout.VerticalFlex = Enum.UIFlexAlignment.Fill
	end

	-- Tabs
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, 52)
	tabs.LayoutOrder = 1
	tabs.Parent = root
	pad(tabs, 12, 14, 14, 14)
	local tabsLayout = listLayout(tabs, 0, true)
	tabsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local function makeTab(id: string, label: string, selected: boolean, order: number): TextButton
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. id
		tab.AutoButtonColor = false
		tab.BorderSizePixel = 0
		tab.Font = F.bodyBold
		tab.TextSize = 14
		tab.Text = label
		tab.Size = UDim2.fromOffset(88, 32)
		tab.LayoutOrder = order
		tab:SetAttribute("Selected", selected)
		if selected then
			tab.BackgroundColor3 = C.card
			tab.TextColor3 = C.text
		else
			tab.BackgroundTransparency = 1
			tab.TextColor3 = C.faint
		end
		corner(tab, 999)
		tab.Parent = tabs
		return tab
	end

	local tabEngine = makeTab("engine", "Engine", true, 1)
	local tabTools = makeTab("tools", "Tools", false, 2)

	-- Body scroll
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, 0, 1, -52)
	body.CanvasSize = UDim2.new(0, 0, 0, 0)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 0
	body.LayoutOrder = 2
	body.Parent = root
	pad(body, 0, 14, 16, 14)
	listLayout(body, 0)

	local panelEngine = Instance.new("Frame")
	panelEngine.Name = "PanelEngine"
	panelEngine.BackgroundTransparency = 1
	panelEngine.Size = UDim2.new(1, 0, 0, 0)
	panelEngine.AutomaticSize = Enum.AutomaticSize.Y
	panelEngine.Visible = true
	panelEngine.LayoutOrder = 1
	panelEngine.Parent = body
	listLayout(panelEngine, 0)

	local panelTools = Instance.new("Frame")
	panelTools.Name = "PanelTools"
	panelTools.BackgroundTransparency = 1
	panelTools.Size = UDim2.new(1, 0, 0, 0)
	panelTools.AutomaticSize = Enum.AutomaticSize.Y
	panelTools.Visible = false
	panelTools.LayoutOrder = 2
	panelTools.Parent = body
	listLayout(panelTools, 0)

	local function selectTab(which: string)
		local isEngine = which == "engine"
		panelEngine.Visible = isEngine
		panelTools.Visible = not isEngine
		for _, tab in { tabEngine, tabTools } do
			local on = (tab == tabEngine and isEngine) or (tab == tabTools and not isEngine)
			tab:SetAttribute("Selected", on)
			if on then
				tab.BackgroundTransparency = 0
				tab.BackgroundColor3 = C.card
				tab.TextColor3 = C.text
			else
				tab.BackgroundTransparency = 1
				tab.TextColor3 = C.faint
			end
		end
	end

	tabEngine.MouseButton1Click:Connect(function()
		selectTab("engine")
	end)
	tabTools.MouseButton1Click:Connect(function()
		selectTab("tools")
	end)

	-- ── Engine panel ──────────────────────────────────────────────────────────
	local hero = Instance.new("Frame")
	hero.Name = "Hero"
	hero.BackgroundTransparency = 1
	hero.Size = UDim2.new(1, 0, 0, 74)
	hero.LayoutOrder = 1
	hero.Parent = panelEngine
	pad(hero, 12, 12, 16, 12)

	local heroTitle = makeLabel(hero, {
		text = "Check for the Club Kit Engine update.",
		size = 20,
		font = F.title,
		color = C.text,
		wrap = true,
		xAlign = Enum.TextXAlignment.Center,
		yAlign = Enum.TextYAlignment.Center,
		autoY = true,
	})
	heroTitle.Name = "HeroTitle"
	heroTitle.Position = UDim2.fromScale(0, 0)
	heroTitle.Size = UDim2.new(1, 0, 1, 0)
	heroTitle.AutomaticSize = Enum.AutomaticSize.None

	-- Spec grid
	local specCard = makeCard(panelEngine, 2)
	local specGrid = Instance.new("Frame")
	specGrid.BackgroundTransparency = 1
	specGrid.Size = UDim2.new(1, 0, 0, 72)
	specGrid.Parent = specCard
	local specLayout = listLayout(specGrid, 0, true)
	specLayout.FillDirection = Enum.FillDirection.Horizontal

	local function makeSpecCell(label: string, accent: boolean): (Frame, TextLabel)
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.new(0.5, 0, 1, 0)
		cell.Parent = specGrid
		pad(cell, 18, 12, 18, 12)
		local v = makeLabel(cell, {
			text = "—",
			size = 18,
			font = F.title,
			color = if accent then C.blueBright else C.text,
			xAlign = Enum.TextXAlignment.Center,
			height = 22,
		})
		v.Name = "Value"
		local k = makeLabel(cell, {
			text = label,
			size = 12,
			font = F.body,
			color = C.faint,
			xAlign = Enum.TextXAlignment.Center,
			height = 16,
		})
		k.Position = UDim2.new(0, 0, 0, 28)
		if not accent then
			local divider = Instance.new("Frame")
			divider.BackgroundColor3 = C.sep
			divider.BackgroundTransparency = 0.92
			divider.BorderSizePixel = 0
			divider.Size = UDim2.new(0, 1, 1, 0)
			divider.Position = UDim2.new(1, -1, 0, 0)
			divider.Parent = cell
		end
		return cell, v
	end

	local _, currentVerLabel = makeSpecCell("This place", false)
	local _, latestVerLabel = makeSpecCell("Channel latest", true)

	-- Actions
	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, 0)
	actions.AutomaticSize = Enum.AutomaticSize.Y
	actions.LayoutOrder = 3
	actions.Parent = panelEngine
	pad(actions, 4, 2, 16, 2)
	listLayout(actions, 8)

	local btnPrimary = makeButton(actions, { text = "Check for updates", primary = true, order = 1 })
	local btnStay = makeButton(actions, { text = "Skip this version", primary = false, order = 2 })

	-- Release notes
	makeSecHead(panelEngine, "Release notes", 4)
	local notesCard = makeCard(panelEngine, 5)
	local notesLabel = Instance.new("TextLabel")
	notesLabel.Name = "Notes"
	notesLabel.BackgroundTransparency = 1
	notesLabel.BorderSizePixel = 0
	notesLabel.Size = UDim2.new(1, 0, 0, 0)
	notesLabel.AutomaticSize = Enum.AutomaticSize.Y
	notesLabel.Font = F.body
	notesLabel.TextSize = 13
	notesLabel.TextColor3 = C.muted
	notesLabel.TextXAlignment = Enum.TextXAlignment.Left
	notesLabel.TextYAlignment = Enum.TextYAlignment.Top
	notesLabel.TextWrapped = true
	notesLabel.Text = BODY_FALLBACK
	notesLabel.Parent = notesCard
	pad(notesLabel, 16)

	-- More actions (rollback)
	makeSecHead(panelEngine, "More actions", 6)
	local moreCard = makeCard(panelEngine, 7)
	local btnRollback = makeListRow(moreCard, {
		iconText = "↓",
		iconColor = C.red,
		iconBg = Color3.fromRGB(40, 18, 18),
		title = "Downgrade",
		desc = "Previous tag on this channel",
		order = 1,
		disabled = true,
	})
	btnRollback.Name = "BtnRollback"

	-- Channel
	makeSecHead(panelEngine, "Channel", 8)
	local channelCard = makeCard(panelEngine, 9)
	local modes = Instance.new("Frame")
	modes.BackgroundTransparency = 1
	modes.Size = UDim2.new(1, 0, 0, 88)
	modes.Parent = channelCard
	pad(modes, 12, 8, 4, 8)
	local modesLayout = listLayout(modes, 4, true)
	modesLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	modesLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local channelButtons: { [string]: TextButton } = {}
	local function makeChannel(id: string, short: string, label: string, order: number): TextButton
		local btn = Instance.new("TextButton")
		btn.AutoButtonColor = false
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.Size = UDim2.fromOffset(96, 72)
		btn.LayoutOrder = order
		btn:SetAttribute("Channel", id)
		btn.Parent = modes

		local ring = Instance.new("TextLabel")
		ring.Name = "Ring"
		ring.BackgroundColor3 = C.elevated
		ring.BorderSizePixel = 0
		ring.Size = UDim2.fromOffset(40, 40)
		ring.Position = UDim2.new(0.5, -20, 0, 0)
		ring.Font = F.bodyBold
		ring.TextSize = 12
		ring.TextColor3 = C.muted
		ring.Text = short
		ring.Parent = btn
		corner(ring, 999)

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, 0, 0, 16)
		name.Position = UDim2.new(0, 0, 0, 48)
		name.Font = F.body
		name.TextSize = 12
		name.TextColor3 = C.faint
		name.Text = label
		name.Parent = btn

		channelButtons[id] = btn
		return btn
	end

	makeChannel("stable", "ST", "Stable", 1)
	makeChannel("canary", "CN", "Canary", 2)
	makeChannel("nightly", "NT", "Nightly", 3)

	local channelHint = makeLabel(channelCard, {
		text = CHANNEL_HINT.stable,
		size = 12,
		font = F.body,
		color = C.faint,
		wrap = true,
		xAlign = Enum.TextXAlignment.Center,
		autoY = true,
		order = 2,
	})
	channelHint.Name = "ChannelHint"
	pad(channelHint, 0, 16, 14, 16)

	local statusLine = makeLabel(panelEngine, {
		text = "",
		size = 11,
		font = F.body,
		color = C.faint,
		wrap = true,
		xAlign = Enum.TextXAlignment.Center,
		autoY = true,
		order = 99,
	})
	statusLine.Name = "StatusLine"

	-- ── Tools panel ───────────────────────────────────────────────────────────
	makeSecHead(panelTools, "Studio helpers", 1)
	local toolsCard = makeCard(panelTools, 2)
	local btnGenTools = makeListRow(toolsCard, {
		iconText = "T",
		iconColor = C.blueBright,
		iconBg = Color3.fromRGB(18, 36, 56),
		title = "Generate Tools folders",
		desc = "Empty folders under ServerStorage.Tools from role config",
		order = 1,
	})
	local btnCarryFix = makeListRow(toolsCard, {
		iconText = "C",
		iconColor = C.muted,
		iconBg = C.elevated,
		title = "Carry fix",
		desc = "Upload ReplicatedStorage.Carry clips + patch ClubKitConfig animations",
		order = 2,
	})

	-- ── Rollback confirm overlay ──────────────────────────────────────────────
	local modalBg = Instance.new("Frame")
	modalBg.Name = "RollbackModal"
	modalBg.BackgroundColor3 = Color3.new(0, 0, 0)
	modalBg.BackgroundTransparency = 0.45
	modalBg.BorderSizePixel = 0
	modalBg.Size = UDim2.fromScale(1, 1)
	modalBg.Visible = false
	modalBg.ZIndex = 50
	modalBg.Parent = root

	local modal = Instance.new("Frame")
	modal.BackgroundColor3 = C.card
	modal.BorderSizePixel = 0
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.new(1, -48, 0, 0)
	modal.AutomaticSize = Enum.AutomaticSize.Y
	modal.ZIndex = 51
	modal.Parent = modalBg
	corner(modal, 16)
	pad(modal, 20)
	listLayout(modal, 12)

	makeLabel(modal, {
		text = "Downgrade engine?",
		size = 17,
		font = F.title,
		order = 1,
		height = 22,
	})
	local rbBody = makeLabel(modal, {
		text = "Engine Sources only. Config, Secrets, and GUI stay.",
		size = 13,
		font = F.body,
		color = C.muted,
		wrap = true,
		autoY = true,
		order = 2,
	})
	local rbRow = Instance.new("Frame")
	rbRow.BackgroundTransparency = 1
	rbRow.Size = UDim2.new(1, 0, 0, 44)
	rbRow.LayoutOrder = 3
	rbRow.Parent = modal
	local rbLayout = listLayout(rbRow, 8, true)
	rbLayout.FillDirection = Enum.FillDirection.Horizontal

	local rbCancel = makeButton(rbRow, { text = "Cancel", primary = false, order = 1 })
	rbCancel.Size = UDim2.new(0.5, -4, 0, 44)
	local rbConfirm = makeButton(rbRow, { text = "Downgrade", primary = true, order = 2 })
	rbConfirm.Size = UDim2.new(0.5, -4, 0, 44)

	-- ── State / wiring ────────────────────────────────────────────────────────
	local busy = false
	local activeChannel = "stable"
	if pluginRef then
		local saved = pluginRef:GetSetting("ClubKit_UpdateChannel")
		if type(saved) == "string" and CHANNEL_HINT[saved] then
			activeChannel = saved
		end
	end

	local lastCheck: any = {
		localVersion = SourceSyncCore.getLocalVersion() or "unknown",
		updateAvailable = false,
	}
	local previousTag: string? = nil

	local function setStatus(text: string, _tone: string?)
		statusLine.Text = text or ""
	end

	local function setChannelUI(ch: string)
		activeChannel = ch
		if pluginRef then
			pluginRef:SetSetting("ClubKit_UpdateChannel", ch)
		end
		for id, btn in channelButtons do
			local on = id == ch
			local ring = btn:FindFirstChild("Ring") :: TextLabel?
			local nameLabel = btn:FindFirstChildWhichIsA("TextLabel", false)
			-- Find name label (not Ring)
			for _, child in btn:GetChildren() do
				if child:IsA("TextLabel") and child.Name ~= "Ring" then
					nameLabel = child
				end
			end
			if ring then
				if on then
					ring.BackgroundColor3 = C.blue
					ring.TextColor3 = C.text
				else
					ring.BackgroundColor3 = C.elevated
					ring.TextColor3 = C.muted
				end
			end
			if nameLabel then
				nameLabel.TextColor3 = if on then C.text else C.faint
			end
		end
		channelHint.Text = CHANNEL_HINT[ch] or CHANNEL_HINT.stable
	end

	local function setDowngrade(enabled: boolean, prev: string?)
		previousTag = if enabled then prev else nil
		btnRollback.Active = enabled == true and previousTag ~= nil
		local titleLabel = btnRollback:FindFirstChildWhichIsA("TextLabel", true)
		-- Update title text specifically
		for _, child in btnRollback:GetChildren() do
			if child:IsA("TextLabel") and child.Position.X.Offset == 68 and child.Position.Y.Offset == 14 then
				child.Text = if enabled and prev then ("Downgrade to " .. prev) else "Downgrade"
				child.TextColor3 = if enabled then C.text else C.faint
			end
		end
	end

	local function setPrimaryIdle(canInstall: boolean)
		btnPrimary.Active = true
		btnPrimary.AutoButtonColor = true
		if canInstall then
			btnPrimary.Text = "Update engine"
			btnPrimary.BackgroundColor3 = C.blue
		else
			btnPrimary.Text = "Check for updates"
			btnPrimary.BackgroundColor3 = C.blue
		end
	end

	local function setPrimaryBusy(label: string)
		btnPrimary.Active = false
		btnPrimary.AutoButtonColor = false
		btnPrimary.Text = label
		btnPrimary.BackgroundColor3 = C.elevated
	end

	local function refreshMeta()
		local localV = lastCheck.localVersion or "unknown"
		local latestV = lastCheck.latestVersion
		currentVerLabel.Text = localV
		latestVerLabel.Text = latestV or "—"

		if lastCheck.error then
			heroTitle.Text = "Could not check for updates."
			notesLabel.Text = tostring(lastCheck.error)
			setPrimaryIdle(false)
			setDowngrade(false, nil)
			return
		end

		if latestV and lastCheck.updateAvailable then
			heroTitle.Text = "An engine update is available."
			setPrimaryIdle(true)
		elseif latestV then
			heroTitle.Text = "You're on the latest engine."
			setPrimaryIdle(false)
		else
			heroTitle.Text = "Check for the Club Kit Engine update."
			setPrimaryIdle(false)
		end

		-- Rollback not wired to channel history yet
		setDowngrade(false, nil)
	end

	local function applyCheckResult(result)
		lastCheck = result
		refreshMeta()

		if result.changelog and result.changelog ~= "" then
			local plain = cleanupChangelog(result.changelog)
			notesLabel.Text = truncateNotes(plain, 900)
		else
			notesLabel.Text = BODY_FALLBACK
		end

		if result.error then
			setStatus(result.error)
			warn("[ClubKitUpdater] " .. result.error)
			return
		end

		if result.updateAvailable then
			local msg = ("Update available: v%s → v%s"):format(result.localVersion, result.latestVersion)
			setStatus(msg)
			print("[ClubKitUpdater] " .. msg)
		else
			setStatus(("Up to date · v%s"):format(result.localVersion))
			print(("[ClubKitUpdater] Engine is up to date (v%s)."):format(result.localVersion))
		end
	end

	local function checkForUpdates()
		if busy then
			print("[ClubKitUpdater] Still busy, please wait...")
			return
		end
		busy = true
		heroTitle.Text = "Checking for updates…"
		setPrimaryBusy("Checking…")
		setStatus("Checking GitHub tags…")
		print("[ClubKitUpdater] Checking GitHub tags...")
		task.spawn(function()
			local ok, result = pcall(SourceSyncCore.checkForUpdates)
			if not ok then
				local err = tostring(result)
				lastCheck.error = err
				refreshMeta()
				setStatus("Check failed: " .. err)
				warn("[ClubKitUpdater] " .. err)
			else
				applyCheckResult(result)
			end
			busy = false
		end)
	end

	local function runUpdate()
		if busy then
			return
		end
		if not lastCheck.updateAvailable or not lastCheck.latestTag then
			checkForUpdates()
			return
		end

		if lastCheck.localVersion ~= "unknown" and lastCheck.latestVersion then
			local cmp = SourceSyncCore.compareVersions(lastCheck.localVersion, lastCheck.latestVersion)
			if cmp > 0 then
				setStatus("Downgrade detected — see Output.")
				warn("[ClubKitUpdater] Downgrade not blocked - proceed with caution.")
			elseif cmp == 0 then
				setStatus("Already on latest version.")
				refreshMeta()
				return
			end
		end

		busy = true
		setPrimaryBusy("Updating…")
		setStatus("Fetching file tree…")
		print("[ClubKitUpdater] Applying update from " .. tostring(lastCheck.latestTag) .. "...")
		task.spawn(function()
			local tag = lastCheck.latestTag :: string
			local ok, reportOrErr = pcall(function()
				return SourceSyncCore.applyEngineUpdate(tag, function(msg, index, total)
					local line = ("%s (%d/%d)"):format(msg, index, total)
					setStatus(line)
					print("[ClubKitUpdater] " .. line)
				end)
			end)

			if not ok then
				local err = tostring(reportOrErr)
				setStatus("Update failed: " .. err)
				warn("[ClubKitUpdater] " .. err)
				busy = false
				refreshMeta()
				return
			end

			local report = reportOrErr
			local okCount = #report.ok
			local errCount = #report.errors
			if report.configPatch then
				print("[ClubKitUpdater] " .. tostring(report.configPatch))
			end
			if errCount == 0 then
				local doneMsg = ("Done · %d files · v%s · save place"):format(okCount, report.version or "?")
				if report.configPatch then
					doneMsg = doneMsg .. " · " .. tostring(report.configPatch)
				end
				setStatus(doneMsg)
				print("[ClubKitUpdater] " .. doneMsg)
			else
				local doneMsg = ("Finished with errors: %d ok, %d failed."):format(okCount, errCount)
				setStatus(doneMsg)
				warn("[ClubKitUpdater] " .. doneMsg)
				for _, line in report.errors do
					warn("[ClubKitUpdater] FAIL " .. line)
				end
			end

			local recheckOk, recheckResult = pcall(SourceSyncCore.checkForUpdates)
			if recheckOk then
				applyCheckResult(recheckResult)
			else
				refreshMeta()
			end
			busy = false
		end)
	end

	local function primaryClick()
		if lastCheck.updateAvailable and lastCheck.latestTag then
			runUpdate()
		else
			checkForUpdates()
		end
	end

	local function stayOnVersion()
		if busy then
			return
		end
		print("[ClubKitUpdater] Skip this version")
		if opts.onDismiss then
			opts.onDismiss()
		end
	end

	btnPrimary.MouseButton1Click:Connect(primaryClick)
	btnStay.MouseButton1Click:Connect(stayOnVersion)

	for id, btn in channelButtons do
		btn.MouseButton1Click:Connect(function()
			setChannelUI(id)
			if id ~= "stable" then
				setStatus("Channel saved · Check/Update still use stable tags for now")
			end
		end)
	end

	btnRollback.MouseButton1Click:Connect(function()
		if not btnRollback.Active or not previousTag then
			return
		end
		rbBody.Text = ("Apply %s. Config, Secrets, GUI stay."):format(previousTag)
		modalBg.Visible = true
	end)
	rbCancel.MouseButton1Click:Connect(function()
		modalBg.Visible = false
	end)
	rbConfirm.MouseButton1Click:Connect(function()
		modalBg.Visible = false
		if not previousTag or busy then
			return
		end
		busy = true
		setPrimaryBusy("Downgrading…")
		setStatus("Downgrading to " .. previousTag)
		local tag = previousTag
		task.spawn(function()
			local ok, reportOrErr = pcall(function()
				return SourceSyncCore.applyEngineUpdate(tag, function(msg, index, total)
					setStatus(("%s (%d/%d)"):format(msg, index, total))
				end)
			end)
			if not ok then
				setStatus("Downgrade failed: " .. tostring(reportOrErr))
				warn("[ClubKitUpdater] " .. tostring(reportOrErr))
			else
				setStatus(("Downgraded · v%s · save place"):format(reportOrErr.version or tag))
			end
			local recheckOk, recheckResult = pcall(SourceSyncCore.checkForUpdates)
			if recheckOk then
				applyCheckResult(recheckResult)
			else
				refreshMeta()
			end
			busy = false
		end)
	end)

	btnGenTools.MouseButton1Click:Connect(function()
		if opts.onGenerateTools then
			opts.onGenerateTools()
			setStatus("Generate Tools folders — see Output")
		else
			warn("[ClubKitPanel] Generate Tools callback missing")
		end
	end)

	btnCarryFix.MouseButton1Click:Connect(function()
		if opts.onCarryFix then
			opts.onCarryFix()
		else
			warn(
				"[ClubKitPanel] Carry fix: use toolbar Hazastudio Club Kit → Carry Upload (local plugin + CreateAssetAsync beta)."
			)
			print("[ClubKitPanel] Carry fix — open Carry Upload from the Plugins toolbar.")
			setStatus("Carry fix — open Carry Upload on toolbar")
		end
	end)

	setChannelUI(activeChannel)
	refreshMeta()
	setStatus("Opening · checking for updates…")
	setPrimaryIdle(false)

	return {
		checkForUpdates = checkForUpdates,
		runUpdate = runUpdate,
		setStatus = setStatus,
	}
end

return UpdaterPanel
