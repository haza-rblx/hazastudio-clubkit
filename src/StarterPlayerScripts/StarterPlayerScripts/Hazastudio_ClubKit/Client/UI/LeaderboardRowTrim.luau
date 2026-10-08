--!strict
-- Leaderboard rows carry decoration that draws nothing. Each row is cloned by the server
-- renderer from the board's BasicCardTemplate: 28 instances, 46 rows a board, ~8,900 instances on
-- the client in Experiment Area. This removes, on the client only:
-- - disabled UIStrokes;
-- - all-zero UIPaddings;
-- - UICorners on fully transparent Frames;
-- - UIAspectRatioConstraints, replaced by the fixed size they produce. Rows are a fixed height,
--   and the renderer only ever writes text into rows.
-- Measured 2026-10-07: 276 rows, -1,472 instances, 0 text/image rects moved.
-- Switch: Config.ClientFootprint.TRIM_LEADERBOARD_ROWS.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local LeaderboardRowTrim = {}

local ROW_PATTERN = "^GeneratedLeaderboardRow%d+$"
local TRIMMED_ATTRIBUTE = "FootprintTrimmed"

local watchedLists: { [Instance]: RBXScriptConnection } = {}

local function isZeroPadding(padding: UIPadding): boolean
	for _, value in ipairs({ padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom }) do
		if value.Scale ~= 0 or value.Offset ~= 0 then
			return false
		end
	end
	return true
end

-- Returns whether the row is done (false = layout not computed yet, try again later).
local function trimRow(row: GuiObject): boolean
	if row:GetAttribute(TRIMMED_ATTRIBUTE) then
		return true
	end
	local pending = false
	for _, item in ipairs(row:GetDescendants()) do
		local parent = item.Parent
		if item:IsA("UIStroke") then
			if not item.Enabled then
				item:Destroy()
			end
		elseif item:IsA("UIPadding") then
			if isZeroPadding(item) then
				item:Destroy()
			end
		elseif item:IsA("UICorner") then
			if parent and parent:IsA("Frame") and parent.BackgroundTransparency >= 1 then
				item:Destroy()
			end
		elseif item:IsA("UIAspectRatioConstraint") then
			if parent and parent:IsA("GuiObject") then
				local size = parent.AbsoluteSize
				if size.X > 0 and size.Y > 0 then
					item:Destroy()
					parent.Size = UDim2.fromOffset(math.round(size.X), math.round(size.Y))
				else
					pending = true
				end
			end
		end
	end
	if not pending then
		row:SetAttribute(TRIMMED_ATTRIBUTE, true)
	end
	return not pending
end

local function trimLater(row: GuiObject)
	task.defer(function()
		for _ = 1, 10 do
			if not row.Parent or trimRow(row) then
				return
			end
			task.wait(1)
		end
	end)
end

local function watchList(list: Instance)
	if watchedLists[list] then
		return
	end
	watchedLists[list] = list.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") and string.match(child.Name, ROW_PATTERN) then
			trimLater(child)
		end
	end)
	list.Destroying:Connect(function()
		local connection = watchedLists[list]
		if connection then
			connection:Disconnect()
		end
		watchedLists[list] = nil
	end)
end

-- Trims every row under these board GUIs and keeps trimming rows added later.
function LeaderboardRowTrim.attach(boardGuis: { Instance })
	if Config.ClientFootprint.TRIM_LEADERBOARD_ROWS ~= true then
		return
	end
	for _, gui in ipairs(boardGuis) do
		for _, item in ipairs(gui:GetDescendants()) do
			if item:IsA("GuiObject") and string.match(item.Name, ROW_PATTERN) then
				if item.Parent then
					watchList(item.Parent)
				end
				trimLater(item)
			end
		end
	end
end

return LeaderboardRowTrim
