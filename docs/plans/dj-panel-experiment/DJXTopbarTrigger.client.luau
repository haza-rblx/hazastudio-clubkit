--!nocheck
-- DJ panel topbar trigger (owner, 2026-10-16) - PLACE-ONLY, not kit code.
-- A "DJ" pill on the left of the topbar toggles StarterGui.DJGUI (the DJXExperiment panel);
-- the header close button closes it too. The panel builds while open, then starts closed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local kit = ReplicatedStorage:WaitForChild("Hazastudio_ClubKit", 30)
local iconModule = kit and kit:WaitForChild("Icon", 30)
if not iconModule then
	warn("[DJXTopbarTrigger] TopbarPlus Icon module not found")
	return
end
local Icon = require(iconModule)
local gui = pg:WaitForChild("DJGUI", 30)
if not gui then
	return
end

local FILL = Color3.fromRGB(7, 7, 7)
local pillAllowed = false -- D3: mirrors the kit's DJ permission (see applyPermission)
local icon = Icon.new()
icon:setLabel("DJ")
icon:setOrder(3)
icon:setEnabled(false) -- hidden until the kit says this player may set DJ mode
if type(icon.setLeft) == "function" then
	icon:setLeft()
elseif type(icon.align) == "function" then
	icon:align("Left")
end
if type(icon.modifyTheme) == "function" then
	icon:modifyTheme({
		{ "Widget", "BackgroundTransparency", 1 },
		{ "IconButton", "BackgroundColor3", FILL },
		{ "IconButton", "BackgroundTransparency", 0 },
		{ "WidgetStroke", "Color", FILL:Lerp(Color3.new(1, 1, 1), 0.35) },
		{ "WidgetStroke", "Transparency", 0.7 },
	})
end

local syncing = false
local function setOpen(open)
	if open and not pillAllowed then
		open = false
	end
	if gui.Enabled ~= open then
		gui.Enabled = open
	end
	syncing = true
	if open and not icon.isSelected then
		icon:select()
	elseif not open and icon.isSelected then
		icon:deselect()
	end
	syncing = false
end
icon.selected:Connect(function()
	if not syncing then
		setOpen(true)
	end
end)
icon.deselected:Connect(function()
	if not syncing then
		setOpen(false)
	end
end)

-- D3 (2026-10-16): only players the kit lets set DJ mode see the pill. Client signal = the kit's
-- MusicPlayerStore "isControlAllowed" key (the same key the Music panel uses for its DJ tab).
-- Fails closed: no store, no pill.
local allowedStore = nil
do
	local okStore, store = pcall(function()
		local K = player:WaitForChild("PlayerScripts", 5):WaitForChild("Hazastudio_ClubKit", 5)
		return require(K:WaitForChild("Client", 5):WaitForChild("State", 5):WaitForChild("MusicPlayerStore", 5))
	end)
	if okStore then
		allowedStore = store
	end
end
local function applyPermission()
	local allowed = allowedStore ~= nil and allowedStore:get().isControlAllowed == true
	local lost = pillAllowed and not allowed
	pillAllowed = allowed
	icon:setEnabled(allowed)
	-- only close on a real loss; the first state sync lands ~2-3 s after join, and the panel
	-- must stay open until the startup close below so DJXExperiment can build
	if lost then
		setOpen(false)
	end
end
if allowedStore then
	allowedStore:subscribe("isControlAllowed", applyPermission)
end
applyPermission()

-- header close button (DJX_Header "×")
task.spawn(function()
	for _ = 1, 40 do
		local header = gui:FindFirstChild("DJX_Header", true)
		if header then
			for _, d in header:GetDescendants() do
				if d:IsA("TextButton") and d.Text == "×" then
					d.MouseButton1Click:Connect(function()
						setOpen(false)
					end)
					return
				end
			end
		end
		task.wait(0.25)
	end
end)

-- let DJXExperiment measure and build while the panel is open, then start closed
task.delay(3, function()
	setOpen(false)
end)
