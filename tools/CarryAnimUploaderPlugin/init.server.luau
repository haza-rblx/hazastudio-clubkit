--!nocheck
--[[
	ClubKit Carry Anim Uploader — LOCAL PLUGIN ONLY
	Install:
	  1. Studio → File → Beta Features → enable "CreateAssetAsync Lua API"
	  2. Right-click this Script → Save as Local Plugin
	     (or copy folder to %LOCALAPPDATA%\Roblox\Plugins\CarryAnimUploaderPlugin\)
	  3. Restart Studio → Plugins toolbar → "Carry Upload"

	Expects KeyframeSequences under ReplicatedStorage.Carry named like:
	  Hug 1 / Hug 2, Fireman1 / Fireman2, Piggyback 1 / Piggyback 2
	  → style + role: 1 = carrier, 2 = carried

	Then patches ReplicatedStorage.Hazastudio_ClubKitConfig.ClubKitConfig
	  Carry.Styles.<Style>.animations = { carrier = ID, carried = ID }
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local GroupService = game:GetService("GroupService")

-- ── Naming / style map ───────────────────────────────────────────────────────

-- Folder keyframe alias → ClubKitConfig.Carry.Styles key
local STYLE_ALIASES: { [string]: string } = {
	Pasakal = "Choke", -- common rename in place assets
	PASAKAL = "Choke",
	Chokehold = "Choke",
}

local KNOWN_STYLES = {
	Piggyback = true,
	Bridal = true,
	Hug = true,
	Tandem = true,
	Fireman = true,
	Choke = true,
}

local function normalizeStyleToken(raw: string): string
	local cleaned = (raw:gsub("^%s+", ""):gsub("%s+$", ""))
	local alias = STYLE_ALIASES[cleaned] or STYLE_ALIASES[string.upper(cleaned)]
	if alias then
		return alias
	end
	-- Title-case first letter for known styles matching ignore-case
	for styleName in pairs(KNOWN_STYLES) do
		if string.lower(styleName) == string.lower(cleaned) then
			return styleName
		end
	end
	return cleaned
end

-- "Hug 1" / "Hug1" / "Fireman2" → style, role ("carrier"|"carried")
local function parseKeyframeName(name: string): (string?, string?, string?)
	local stylePart, roleDigit = name:match("^(.+)%s*([12])%s*$")
	if not stylePart or not roleDigit then
		return nil, nil, "name must end with 1 (carrier) or 2 (carried)"
	end
	stylePart = stylePart:gsub("%s+$", "")
	local style = normalizeStyleToken(stylePart)
	local role = if roleDigit == "1" then "carrier" else "carried"
	return style, role, nil
end

local function findCarryFolder(): Folder?
	local carry = ReplicatedStorage:FindFirstChild("Carry")
	if carry and carry:IsA("Folder") then
		return carry
	end
	return nil
end

local function findConfigModule(): ModuleScript?
	local folder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKitConfig")
	if not folder then
		return nil
	end
	local mod = folder:FindFirstChild("ClubKitConfig")
	if mod and mod:IsA("ModuleScript") then
		return mod
	end
	return nil
end

local function collectKeyframeSequences(root: Instance): { KeyframeSequence }
	local list = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("KeyframeSequence") then
			table.insert(list, d)
		end
	end
	-- Also include direct children if root itself is a KFS (unlikely)
	if root:IsA("KeyframeSequence") then
		table.insert(list, root)
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

-- ── Config Source patch ──────────────────────────────────────────────────────

local function patchAnimationsInSource(source: string, style: string, carrierId: number?, carriedId: number?): (string, boolean)
	local ok = false
	local result = source:gsub(
		"(" .. style .. "%s*=%s*%b{})",
		function(block: string)
			local newBlock, n = block:gsub(
				"(animations%s*=%s*{%s*carrier%s*=%s*)(%d+)(,%s*carried%s*=%s*)(%d+)(%s*})",
				function(pre, _c, mid, _d, post)
					local c = if carrierId then tostring(carrierId) else _c
					local d = if carriedId then tostring(carriedId) else _d
					ok = true
					return pre .. c .. mid .. d .. post
				end
			)
			if n == 0 then
				newBlock, n = block:gsub(
					"(animations%s*=%s*{%s*carried%s*=%s*)(%d+)(,%s*carrier%s*=%s*)(%d+)(%s*})",
					function(_pre, _d, _mid, _c, _post)
						local c = if carrierId then tostring(carrierId) else _c
						local d = if carriedId then tostring(carriedId) else _d
						ok = true
						return string.format("animations = { carrier = %s, carried = %s }", c, d)
					end
				)
			end
			return if n > 0 then newBlock else block
		end
	)
	return result, ok
end

local function applyConfigPatch(mod: ModuleScript, idsByStyle: { [string]: { carrier: number?, carried: number? } }): { string }
	local log = {}
	local source = mod.Source
	local changed = false
	for style, ids in pairs(idsByStyle) do
		if ids.carrier or ids.carried then
			local nextSource, ok = patchAnimationsInSource(source, style, ids.carrier, ids.carried)
			if ok then
				source = nextSource
				changed = true
				table.insert(
					log,
					string.format(
						"patched %s → carrier=%s carried=%s",
						style,
						tostring(ids.carrier or "?"),
						tostring(ids.carried or "?")
					)
				)
			else
				table.insert(log, string.format("WARN: could not find animations block for style %s in ClubKitConfig", style))
			end
		end
	end
	if changed then
		mod.Source = source
		table.insert(log, "ClubKitConfig ModuleScript Source updated in place.")
		table.insert(log, "If Rojo is syncing this file, also paste IDs into repo ClubKitConfig.luau.")
	end
	return log
end

-- ── Upload ───────────────────────────────────────────────────────────────────

local function uploadKeyframe(seq: KeyframeSequence, groupId: number?): (boolean, number?, string?)
	local params: { [string]: any } = {
		Name = seq.Name,
		Description = "ClubKit Carry — uploaded via CarryAnimUploaderPlugin",
		CreatorType = if groupId then Enum.AssetCreatorType.Group else Enum.AssetCreatorType.User,
	}
	if groupId then
		params.CreatorId = groupId
	end

	local ok, createResult, assetId = pcall(function()
		return AssetService:CreateAssetAsync(seq, Enum.AssetType.Animation, params)
	end)
	if not ok then
		return false, nil, tostring(createResult)
	end
	if createResult ~= Enum.CreateAssetResult.Success then
		return false, nil, tostring(createResult)
	end
	return true, assetId :: number, nil
end

-- ── UI (Dovetail-inspired layout: fixed header + flex-fill log) ─────────────

local C = {
	carbon = Color3.fromHex("#0a0a0a"),
	graphite = Color3.fromHex("#141414"),
	iron = Color3.fromHex("#1e1e1e"),
	slate = Color3.fromHex("#313131"),
	ash = Color3.fromHex("#a7a7a7"),
	bone = Color3.fromHex("#ffffff"),
	indigo = Color3.fromHex("#6798ff"),
	indigoDeep = Color3.fromHex("#3d5f99"),
	success = Color3.fromRGB(90, 190, 120),
	warning = Color3.fromRGB(230, 180, 70),
	error = Color3.fromRGB(230, 90, 90),
	warnBtn = Color3.fromRGB(120, 70, 40),
}

local PAD = 14
local GAP = 10

local toolbar = plugin:CreateToolbar("Hazastudio Club Kit")
local toggleBtn = toolbar:CreateButton(
	"Carry Upload",
	"Upload Carry KeyframeSequences + patch ClubKitConfig",
	"rbxassetid://6035193736"
)

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 380, 620, 320, 480)
local widget = plugin:CreateDockWidgetPluginGui("ClubKitCarryAnimUploader", widgetInfo)
widget.Title = "Carry Anim Uploader"

toggleBtn.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

local function ui(className: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, radius: number?)
	ui("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function stroke(parent: Instance, color: Color3?, transparency: number?)
	ui("UIStroke", {
		Color = color or C.slate,
		Transparency = transparency or 0.35,
		Thickness = 1,
	}, parent)
end

-- Root: vertical list — top controls (auto height) + log (flex fill remaining)
local root = ui("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.carbon,
	BorderSizePixel = 0,
}, widget) :: Frame
ui("UIPadding", {
	PaddingTop = UDim.new(0, PAD),
	PaddingBottom = UDim.new(0, PAD),
	PaddingLeft = UDim.new(0, PAD),
	PaddingRight = UDim.new(0, PAD),
}, root)
ui("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, GAP),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, root)

-- Header card
local header = ui("Frame", {
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = C.graphite,
	BorderSizePixel = 0,
}, root) :: Frame
corner(header)
stroke(header, C.indigoDeep, 0.55)
ui("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 14),
	PaddingRight = UDim.new(0, 14),
}, header)
ui("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
}, header)

ui("TextLabel", {
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 11,
	TextColor3 = C.indigo,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "HAZASTUDIO CLUB KIT",
}, header)

ui("TextLabel", {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = C.bone,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Carry Anim Uploader",
}, header)

local statusLbl = ui("TextLabel", {
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = C.ash,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	Text = "Source: ReplicatedStorage.Carry (or Selection)",
}, header) :: TextLabel

-- Controls card
local controls = ui("Frame", {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = C.iron,
	BorderSizePixel = 0,
}, root) :: Frame
corner(controls)
stroke(controls)
ui("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, controls)
ui("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
}, controls)

ui("TextLabel", {
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 11,
	TextColor3 = C.indigo,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "OPTIONS",
}, controls)

local groupBox = ui("TextBox", {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = C.graphite,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = C.bone,
	PlaceholderText = "Group ID (optional — blank = personal)",
	PlaceholderColor3 = C.ash,
	Text = "",
	ClearTextOnFocus = false,
}, controls) :: TextBox
corner(groupBox, 6)
stroke(groupBox)

local dryRunToggle = ui("TextButton", {
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = C.graphite,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = C.bone,
	Text = "Dry run: ON (scan only)",
	AutoButtonColor = false,
}, controls) :: TextButton
corner(dryRunToggle, 6)
stroke(dryRunToggle)

local dryRun = true
dryRunToggle.MouseButton1Click:Connect(function()
	dryRun = not dryRun
	dryRunToggle.Text = if dryRun then "Dry run: ON (scan only)" else "Dry run: OFF (upload + patch)"
	dryRunToggle.BackgroundColor3 = if dryRun then C.graphite else C.warnBtn
end)

local btnRow = ui("Frame", {
	LayoutOrder = 4,
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
}, controls) :: Frame
ui("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
}, btnRow)

local scanBtn = ui("TextButton", {
	LayoutOrder = 1,
	Size = UDim2.new(0.5, -4, 1, 0),
	BackgroundColor3 = C.indigoDeep,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = C.bone,
	Text = "Scan",
	AutoButtonColor = false,
}, btnRow) :: TextButton
corner(scanBtn, 8)

local runBtn = ui("TextButton", {
	LayoutOrder = 2,
	Size = UDim2.new(0.5, -4, 1, 0),
	BackgroundColor3 = Color3.fromRGB(40, 130, 70),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = C.bone,
	Text = "Upload + patch",
	AutoButtonColor = false,
}, btnRow) :: TextButton
corner(runBtn, 8)

-- Log card: fills remaining vertical space via UIFlexItem
local logCard = ui("Frame", {
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 0),
	BackgroundColor3 = C.iron,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, root) :: Frame
corner(logCard)
stroke(logCard)
do
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = logCard
end
ui("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, logCard)
ui("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, logCard)

ui("TextLabel", {
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 12),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 11,
	TextColor3 = C.indigo,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "LOG",
}, logCard)

local logFrame = ui("ScrollingFrame", {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 0),
	BackgroundColor3 = C.graphite,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = C.slate,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ClipsDescendants = true,
}, logCard) :: ScrollingFrame
corner(logFrame, 6)
do
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = logFrame
end
ui("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
}, logFrame)
ui("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 3),
}, logFrame)

local logOrder = 0
local function clearLog()
	for _, child in ipairs(logFrame:GetChildren()) do
		if child:IsA("TextBox") then
			child:Destroy()
		end
	end
	logOrder = 0
end

local function logLine(text: string, color: Color3?)
	logOrder += 1
	ui("TextBox", {
		LayoutOrder = logOrder,
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		TextSize = 11,
		TextColor3 = color or Color3.fromRGB(210, 210, 210),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextEditable = false,
		ClearTextOnFocus = false,
		Text = text,
	}, logFrame)
	task.defer(function()
		logFrame.CanvasPosition = Vector2.new(0, math.max(0, logFrame.AbsoluteCanvasSize.Y - logFrame.AbsoluteSize.Y))
	end)
end

type Planned = {
	seq: KeyframeSequence,
	style: string,
	role: string,
}

local function planUploads(): ({ Planned }, { string })
	local warnings = {}
	local planned: { Planned } = {}

	local selected = Selection:Get()
	local sequences: { KeyframeSequence } = {}
	local usedSelection = false
	for _, obj in ipairs(selected) do
		if obj:IsA("KeyframeSequence") then
			table.insert(sequences, obj)
			usedSelection = true
		elseif obj:IsA("Folder") or obj:IsA("Model") then
			for _, kfs in ipairs(collectKeyframeSequences(obj)) do
				table.insert(sequences, kfs)
			end
			usedSelection = true
		end
	end

	if #sequences == 0 then
		local carry = findCarryFolder()
		if not carry then
			table.insert(warnings, "No Selection and ReplicatedStorage.Carry folder missing.")
			return planned, warnings
		end
		sequences = collectKeyframeSequences(carry)
		statusLbl.Text = "Source: ReplicatedStorage.Carry (" .. #sequences .. " clips)"
	else
		statusLbl.Text = if usedSelection
			then ("Source: Selection (" .. #sequences .. " clips)")
			else statusLbl.Text
	end

	for _, seq in ipairs(sequences) do
		local styleAttr = seq:GetAttribute("CarryStyle")
		local roleAttr = seq:GetAttribute("CarryRole")
		local style: string?
		local role: string?
		local err: string?

		if type(styleAttr) == "string" and type(roleAttr) == "string" then
			style = normalizeStyleToken(styleAttr)
			role = if string.lower(roleAttr) == "carried" then "carried" else "carrier"
		else
			style, role, err = parseKeyframeName(seq.Name)
		end

		if err or not style or not role then
			table.insert(warnings, string.format("skip '%s': %s", seq.Name, err or "parse failed"))
			continue
		end
		if not KNOWN_STYLES[style] then
			table.insert(
				warnings,
				string.format("skip '%s': unknown style '%s' (add STYLE_ALIASES or rename)", seq.Name, style)
			)
			continue
		end
		table.insert(planned, { seq = seq, style = style, role = role })
	end

	return planned, warnings
end

local function printPlan(planned: { Planned }, warnings: { string })
	clearLog()
	logLine("── Scan ──", Color3.fromRGB(120, 180, 255))
	for _, w in ipairs(warnings) do
		logLine("! " .. w, Color3.fromRGB(240, 180, 60))
	end
	if #planned == 0 then
		logLine("Nothing to upload.", Color3.fromRGB(220, 80, 80))
		return
	end
	local byStyle: { [string]: { carrier: string?, carried: string? } } = {}
	for _, p in ipairs(planned) do
		byStyle[p.style] = byStyle[p.style] or {}
		byStyle[p.style][p.role] = p.seq.Name
		logLine(string.format("%s → %s.%s", p.seq.Name, p.style, p.role))
	end
	logLine("── Expected pairs ──", Color3.fromRGB(120, 180, 255))
	for style, roles in pairs(byStyle) do
		local okPair = roles.carrier and roles.carried
		logLine(
			string.format(
				"%s: carrier=%s carried=%s%s",
				style,
				roles.carrier or "MISSING",
				roles.carried or "MISSING",
				if okPair then "" else "  ← incomplete"
			),
			if okPair then Color3.fromRGB(100, 210, 130) else Color3.fromRGB(240, 180, 60)
		)
	end
	local cfg = findConfigModule()
	logLine(if cfg then "ClubKitConfig: found" else "ClubKitConfig: MISSING", if cfg then Color3.fromRGB(100, 210, 130) else Color3.fromRGB(220, 80, 80))
end

scanBtn.MouseButton1Click:Connect(function()
	local planned, warnings = planUploads()
	printPlan(planned, warnings)
end)

local busy = false
runBtn.MouseButton1Click:Connect(function()
	if busy then
		return
	end
	busy = true
	runBtn.Text = "Working…"

	task.spawn(function()
		local planned, warnings = planUploads()
		printPlan(planned, warnings)

		if dryRun then
			logLine("Dry run only — flip Dry run OFF to upload.", Color3.fromRGB(240, 180, 60))
			busy = false
			runBtn.Text = "Upload + patch"
			return
		end

		if #planned == 0 then
			busy = false
			runBtn.Text = "Upload + patch"
			return
		end

		local groupId = tonumber(groupBox.Text)
		if groupBox.Text ~= "" and not groupId then
			logLine("Invalid Group ID.", Color3.fromRGB(220, 80, 80))
			busy = false
			runBtn.Text = "Upload + patch"
			return
		end
		if groupId then
			local okInfo, info = pcall(function()
				return GroupService:GetGroupInfoAsync(groupId)
			end)
			if not okInfo then
				logLine("Group lookup failed.", Color3.fromRGB(220, 80, 80))
				busy = false
				runBtn.Text = "Upload + patch"
				return
			end
			logLine("Upload as group: " .. tostring(info.Name), Color3.fromRGB(160, 160, 160))
		end

		local idsByStyle: { [string]: { carrier: number?, carried: number? } } = {}
		local okCount, failCount = 0, 0

		logLine("── Upload ──", Color3.fromRGB(120, 180, 255))
		for _, p in ipairs(planned) do
			local ok, assetId, err = uploadKeyframe(p.seq, groupId)
			if ok and assetId then
				idsByStyle[p.style] = idsByStyle[p.style] or {}
				idsByStyle[p.style][p.role] = assetId
				p.seq:SetAttribute("UploadedAnimationId", assetId)
				logLine(string.format("✔ %s → %d (%s.%s)", p.seq.Name, assetId, p.style, p.role), Color3.fromRGB(100, 210, 130))
				okCount += 1
			else
				logLine(string.format("✖ %s — %s", p.seq.Name, tostring(err)), Color3.fromRGB(220, 80, 80))
				failCount += 1
			end
			task.wait(0.12)
		end

		logLine(string.format("Upload done: %d ok, %d failed", okCount, failCount), Color3.fromRGB(200, 200, 200))

		local mod = findConfigModule()
		if mod then
			logLine("── Patch ClubKitConfig ──", Color3.fromRGB(120, 180, 255))
			local patchLog = applyConfigPatch(mod, idsByStyle)
			for _, line in ipairs(patchLog) do
				logLine(line)
			end
		else
			logLine("Skip patch: ClubKitConfig module not found.", Color3.fromRGB(240, 180, 60))
		end

		logLine("── Paste into repo (if Rojo) ──", Color3.fromRGB(120, 180, 255))
		for style, ids in pairs(idsByStyle) do
			if ids.carrier and ids.carried then
				logLine(
					string.format(
						"%s: animations = { carrier = %d, carried = %d },",
						style,
						ids.carrier,
						ids.carried
					),
					Color3.fromRGB(180, 220, 255)
				)
			end
		end

		busy = false
		runBtn.Text = "Upload + patch"
	end)
end)

print("[CarryAnimUploader] Ready — enable CreateAssetAsync beta, install as LOCAL plugin.")
