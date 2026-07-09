--!strict
-- Asset Permission Granter Plugin
--
-- Studio plugin that batch-grants Roblox asset permissions (audio, image,
-- mesh, etc.) to one or more target Universe IDs via the Open Cloud
-- Asset Permissions API.
--
-- INSTALL:
--   1. In Roblox Studio, open this file (or paste its contents) into a Script.
--   2. Right-click the script -> Save as Local Plugin.
--
-- USAGE:
--   1. Generate an Open Cloud API key on https://create.roblox.com/dashboard/credentials
--      with permission: `asset:read`, `asset:write` (or "Universe API Operations" -> Manage).
--   2. Open the plugin, paste the API key.
--   3. Enter target Universe IDs (comma-separated).
--   4. Click "Scan Workspace" or paste asset IDs manually.
--   5. Click "Grant Permissions". Watch the log for progress.
--
-- API KEY is stored locally via plugin:GetSetting/SetSetting and never leaves
-- this Studio instance.

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")

local PLUGIN_NAME = "AssetPermissionGranter"
local TOOLBAR_NAME = "Asset Tools"
local BUTTON_TITLE = "Grant Permissions"
local BUTTON_TOOLTIP = "Batch grant asset permissions to target universes."
local BUTTON_ICON = "rbxasset://textures/StudioToolbox/Cloud.png"

local SETTING_API_KEY = "AssetPermissionGranter_ApiKey"
local SETTING_UNIVERSE_IDS = "AssetPermissionGranter_UniverseIds"

local API_BASE = "https://apis.roblox.com/asset-permissions-api/v1"

-- ============================================================
-- Settings persistence
-- ============================================================

local function loadSetting(name: string, fallback: string): string
	local ok, value = pcall(function()
		return plugin:GetSetting(name)
	end)
	if ok and type(value) == "string" then
		return value
	end
	return fallback
end

local function saveSetting(name: string, value: string)
	pcall(function()
		plugin:SetSetting(name, value)
	end)
end

-- ============================================================
-- Asset ID scanner
-- ============================================================

local SCAN_ROOTS: { Instance } = {
	game:GetService("Workspace"),
	game:GetService("ReplicatedStorage"),
	game:GetService("ServerStorage"),
	game:GetService("StarterGui"),
	game:GetService("StarterPack"),
	game:GetService("StarterPlayer"),
	game:GetService("Lighting"),
	game:GetService("SoundService"),
}

local function extractAssetId(raw: string): number?
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local id = raw:match("rbxassetid://(%d+)") or raw:match("(%d+)")
	if id then
		local n = tonumber(id)
		if n and n > 0 then
			return n
		end
	end
	return nil
end

local function collectAssetIdsFrom(root: Instance, into: { [number]: boolean })
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			local id = extractAssetId(descendant.SoundId)
			if id then into[id] = true end
		elseif descendant:IsA("ImageLabel") then
			local id = extractAssetId(descendant.Image)
			if id then into[id] = true end
		elseif descendant:IsA("ImageButton") then
			local id = extractAssetId(descendant.Image)
			if id then into[id] = true end
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			local id = extractAssetId(descendant.Texture)
			if id then into[id] = true end
		elseif descendant:IsA("MeshPart") then
			local id = extractAssetId(descendant.MeshId)
			if id then into[id] = true end
			local tex = extractAssetId(descendant.TextureID)
			if tex then into[tex] = true end
		elseif descendant:IsA("SpecialMesh") then
			local id = extractAssetId(descendant.MeshId)
			if id then into[id] = true end
			local tex = extractAssetId(descendant.TextureId)
			if tex then into[tex] = true end
		elseif descendant:IsA("Animation") then
			local id = extractAssetId(descendant.AnimationId)
			if id then into[id] = true end
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			local id = extractAssetId((descendant :: any).Texture)
			if id then into[id] = true end
		end
	end
end

local function scanWorkspace(): { number }
	local set: { [number]: boolean } = {}
	for _, root in ipairs(SCAN_ROOTS) do
		collectAssetIdsFrom(root, set)
	end
	local list: { number } = {}
	for id in pairs(set) do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

local function scanSelection(): { number }
	local set: { [number]: boolean } = {}
	for _, item in ipairs(Selection:Get()) do
		collectAssetIdsFrom(item, set)
	end
	local list: { number } = {}
	for id in pairs(set) do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

-- ============================================================
-- Input parsers
-- ============================================================

local function parseIdList(raw: string): { number }
	if type(raw) ~= "string" then
		return {}
	end
	local seen: { [number]: boolean } = {}
	local list: { number } = {}
	for chunk in raw:gmatch("[^,%s\r\n]+") do
		local n = tonumber(chunk)
		if n and n > 0 and not seen[n] then
			seen[n] = true
			table.insert(list, n)
		end
	end
	return list
end

-- ============================================================
-- HTTP: grant permission
-- ============================================================

type GrantResult = {
	ok: boolean,
	statusCode: number?,
	error: string?,
}

local function grantPermission(apiKey: string, assetId: number, universeId: number): GrantResult
	local url = string.format("%s/assets/%d/permissions", API_BASE, assetId)
	local body = HttpService:JSONEncode({
		requests = {
			{
				subjectType = "Universe",
				subjectId = tostring(universeId),
				action = "Use",
			},
		},
	})

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "PATCH",
			Headers = {
				["Content-Type"] = "application/json",
				["x-api-key"] = apiKey,
			},
			Body = body,
		})
	end)

	if not ok then
		return { ok = false, error = tostring(response) }
	end

	local resp = response :: any
	if resp.Success then
		return { ok = true, statusCode = resp.StatusCode }
	end
	return {
		ok = false,
		statusCode = resp.StatusCode,
		error = resp.StatusMessage .. " | " .. tostring(resp.Body),
	}
end

-- Forward declarations populated after the UI builds.
local appendLog: (line: string, kind: string?) -> () = function() end
local setBusy: (busy: boolean) -> () = function() end
local getApiKey: () -> string = function() return "" end
local getUniverseIds: () -> { number } = function() return {} end
local getAssetIds: () -> { number } = function() return {} end
local setAssetIds: (ids: { number }) -> () = function() end

local function runGrantBatch()
	local apiKey = getApiKey()
	if apiKey == "" then
		appendLog("Missing API key.", "error")
		return
	end
	local universes = getUniverseIds()
	if #universes == 0 then
		appendLog("Provide at least one Universe ID.", "error")
		return
	end
	local assets = getAssetIds()
	if #assets == 0 then
		appendLog("Provide at least one Asset ID (paste or scan).", "error")
		return
	end

	setBusy(true)
	appendLog(string.format(
		"Granting %d asset(s) -> %d universe(s) = %d total request(s).",
		#assets, #universes, #assets * #universes
	), "info")

	task.spawn(function()
		local successCount = 0
		local failureCount = 0
		for _, assetId in ipairs(assets) do
			for _, universeId in ipairs(universes) do
				local result = grantPermission(apiKey, assetId, universeId)
				if result.ok then
					successCount += 1
					appendLog(string.format("OK  asset=%d universe=%d", assetId, universeId), "ok")
				else
					failureCount += 1
					appendLog(string.format(
						"ERR asset=%d universe=%d status=%s err=%s",
						assetId,
						universeId,
						tostring(result.statusCode),
						tostring(result.error)
					), "error")
				end
				task.wait(0.15) -- gentle throttle
			end
		end
		appendLog(string.format("Done. ok=%d failed=%d", successCount, failureCount), "info")
		setBusy(false)
	end)
end

-- ============================================================
-- UI builder
-- ============================================================

local COLOR_BG = Color3.fromRGB(28, 28, 32)
local COLOR_PANEL = Color3.fromRGB(38, 38, 44)
local COLOR_INPUT = Color3.fromRGB(22, 22, 26)
local COLOR_TEXT = Color3.fromRGB(230, 230, 235)
local COLOR_MUTED = Color3.fromRGB(150, 150, 160)
local COLOR_ACCENT = Color3.fromRGB(80, 160, 255)
local COLOR_OK = Color3.fromRGB(120, 220, 140)
local COLOR_ERR = Color3.fromRGB(240, 110, 110)

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local toggleButton = toolbar:CreateButton(BUTTON_TITLE, BUTTON_TOOLTIP, BUTTON_ICON)

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false, -- initial enabled
	false, -- override previous enabled state
	440,   -- floating width
	620,   -- floating height
	360,   -- min width
	480    -- min height
)
local widget = plugin:CreateDockWidgetPluginGui(PLUGIN_NAME, widgetInfo)
widget.Title = "Asset Permission Granter"
widget.Name = PLUGIN_NAME

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = COLOR_BG
root.BorderSizePixel = 0
root.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = root

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = root

local function makeLabel(text: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLOR_MUTED
	label.TextSize = 12
	label.Font = Enum.Font.GothamMedium
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	label.Parent = root
	return label
end

local function makeTextBox(placeholder: string, height: number, multiline: boolean, order: number, password: boolean?): TextBox
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = COLOR_INPUT
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = frame

	local box = Instance.new("TextBox")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundTransparency = 1
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = COLOR_MUTED
	box.TextColor3 = COLOR_TEXT
	box.TextSize = 13
	box.Font = Enum.Font.Code
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = if multiline then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	box.MultiLine = multiline
	box.ClearTextOnFocus = false
	box.TextWrapped = multiline
	box.Parent = frame

	if password then
		local display = Instance.new("TextLabel")
		display.Size = UDim2.fromScale(1, 1)
		display.BackgroundTransparency = 1
		display.TextColor3 = COLOR_TEXT
		display.TextSize = 13
		display.Font = Enum.Font.Code
		display.TextXAlignment = Enum.TextXAlignment.Left
		display.Text = ""
		display.ZIndex = box.ZIndex + 1
		display.Parent = frame
		local function refresh()
			if box.Text == "" then
				display.Text = ""
			else
				display.Text = string.rep("•", #box.Text)
			end
		end
		box:GetPropertyChangedSignal("Text"):Connect(refresh)
	end

	return box
end

local function makeButton(text: string, order: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 30)
	btn.BackgroundColor3 = COLOR_PANEL
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Text = text
	btn.TextColor3 = COLOR_TEXT
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamMedium
	btn.LayoutOrder = order
	btn.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn
	return btn
end

makeLabel("Open Cloud API Key", 1)
local apiKeyBox = makeTextBox("Paste API key here", 30, false, 2, true)
apiKeyBox.Text = loadSetting(SETTING_API_KEY, "")
apiKeyBox.FocusLost:Connect(function()
	saveSetting(SETTING_API_KEY, apiKeyBox.Text)
end)

makeLabel("Target Universe IDs (comma or newline separated)", 3)
local universeBox = makeTextBox("e.g. 1234567890, 9876543210", 56, true, 4)
universeBox.Text = loadSetting(SETTING_UNIVERSE_IDS, "")
universeBox.FocusLost:Connect(function()
	saveSetting(SETTING_UNIVERSE_IDS, universeBox.Text)
end)

makeLabel("Asset IDs (paste manually or click Scan)", 5)
local assetBox = makeTextBox("Asset IDs appear here", 140, true, 6)

local scanRow = Instance.new("Frame")
scanRow.Size = UDim2.new(1, 0, 0, 30)
scanRow.BackgroundTransparency = 1
scanRow.LayoutOrder = 7
scanRow.Parent = root

local scanRowLayout = Instance.new("UIListLayout")
scanRowLayout.FillDirection = Enum.FillDirection.Horizontal
scanRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
scanRowLayout.Padding = UDim.new(0, 6)
scanRowLayout.Parent = scanRow

local function makeRowButton(parent: Instance, text: string, order: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.5, -3, 1, 0)
	btn.BackgroundColor3 = COLOR_PANEL
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = COLOR_TEXT
	btn.TextSize = 12
	btn.Font = Enum.Font.GothamMedium
	btn.LayoutOrder = order
	btn.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = btn
	return btn
end

local scanWorkspaceBtn = makeRowButton(scanRow, "Scan Workspace", 1)
local scanSelectionBtn = makeRowButton(scanRow, "Scan Selection", 2)

local grantBtn = makeButton("Grant Permissions", 8)
grantBtn.BackgroundColor3 = COLOR_ACCENT
grantBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

makeLabel("Output", 9)
local logFrame = Instance.new("ScrollingFrame")
logFrame.Size = UDim2.new(1, 0, 0, 200)
logFrame.BackgroundColor3 = COLOR_INPUT
logFrame.BorderSizePixel = 0
logFrame.LayoutOrder = 10
logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
logFrame.ScrollBarThickness = 6
logFrame.Parent = root

local logCorner = Instance.new("UICorner")
logCorner.CornerRadius = UDim.new(0, 4)
logCorner.Parent = logFrame

local logPad = Instance.new("UIPadding")
logPad.PaddingTop = UDim.new(0, 6)
logPad.PaddingBottom = UDim.new(0, 6)
logPad.PaddingLeft = UDim.new(0, 8)
logPad.PaddingRight = UDim.new(0, 8)
logPad.Parent = logFrame

local logLayout = Instance.new("UIListLayout")
logLayout.FillDirection = Enum.FillDirection.Vertical
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Padding = UDim.new(0, 2)
logLayout.Parent = logFrame

local logCounter = 0
appendLog = function(line: string, kind: string?)
	logCounter += 1
	local entry = Instance.new("TextLabel")
	entry.Size = UDim2.new(1, 0, 0, 16)
	entry.BackgroundTransparency = 1
	entry.Text = line
	entry.TextSize = 12
	entry.Font = Enum.Font.Code
	entry.TextXAlignment = Enum.TextXAlignment.Left
	entry.TextWrapped = true
	entry.AutomaticSize = Enum.AutomaticSize.Y
	entry.LayoutOrder = logCounter
	if kind == "error" then
		entry.TextColor3 = COLOR_ERR
	elseif kind == "ok" then
		entry.TextColor3 = COLOR_OK
	else
		entry.TextColor3 = COLOR_TEXT
	end
	entry.Parent = logFrame
end

setBusy = function(busy: boolean)
	grantBtn.Active = not busy
	grantBtn.AutoButtonColor = not busy
	grantBtn.Text = if busy then "Working..." else "Grant Permissions"
end

getApiKey = function()
	return (apiKeyBox.Text or ""):match("^%s*(.-)%s*$") or ""
end

getUniverseIds = function()
	return parseIdList(universeBox.Text)
end

getAssetIds = function()
	return parseIdList(assetBox.Text)
end

setAssetIds = function(ids: { number })
	local lines = {}
	for _, id in ipairs(ids) do
		table.insert(lines, tostring(id))
	end
	assetBox.Text = table.concat(lines, ", ")
end

scanWorkspaceBtn.Activated:Connect(function()
	local ids = scanWorkspace()
	setAssetIds(ids)
	appendLog(string.format("Scanned workspace: %d unique asset(s).", #ids), "info")
end)

scanSelectionBtn.Activated:Connect(function()
	local ids = scanSelection()
	setAssetIds(ids)
	appendLog(string.format("Scanned selection: %d unique asset(s).", #ids), "info")
end)

grantBtn.Activated:Connect(runGrantBatch)

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
end)

appendLog("Plugin ready. Generate API key from create.roblox.com/dashboard/credentials.", "info")
