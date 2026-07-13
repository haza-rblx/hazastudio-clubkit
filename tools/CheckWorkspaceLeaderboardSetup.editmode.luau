--!strict
-- PATH: tools/CheckWorkspaceLeaderboardSetup.editmode.luau
--
-- Audit Workspace donation leaderboard + marquee assets against Club Kit
-- WorkspaceLeaderboardRenderer / TagDonationDisplayRoots expectations.
--
-- Run in Studio Command Bar (Edit or Play — read-only):
--   1) Open this file, Select All, Copy
--   2) Paste into Command Bar, Enter
-- Or (if synced under a Studio path you prefer):
--   loadstring(game:GetService("HttpService"):GetAsync(...)) -- not needed
--
-- Does NOT modify the place.

local workspace = game:GetService("Workspace")

local passCount = 0
local failCount = 0
local warnCount = 0

local function ok(label: string, detail: string?)
	print(string.format("  [OK] %s%s", label, if detail then (" — " .. detail) else ""))
	passCount += 1
end

local function fail(label: string, detail: string?)
	warn(string.format("  [FAIL] %s%s", label, if detail then (" — " .. detail) else ""))
	failCount += 1
end

local function note(label: string, detail: string?)
	warn(string.format("  [!] %s%s", label, if detail then (" — " .. detail) else ""))
	warnCount += 1
end

type BoardSpec = {
	rootPart: string,
	guiName: string,
	topCards: { string },
	templateName: string,
	kind: string,
}

-- Mirrors Shared/Leaderboards/WorkspaceLeaderboardRenderer.BOARD_SPECS
local BOARD_SPECS: { BoardSpec } = {
	{
		rootPart = "RobuxDonationBoard",
		guiName = "RobuxDonationBoardGUI",
		topCards = { "1stPlaceWrapper", "2rdPlaceWrapper", "3rdPlaceWrapper" },
		templateName = "BasicCardTemplate",
		kind = "robux",
	},
	{
		rootPart = "CommunityDonationBoard",
		guiName = "CommunityDonationBoardGUI",
		topCards = { "1stPlaceCommunityWrapper", "2ndPlaceCommunityWrapper", "3rdPlaceCommunityWrapper" },
		templateName = "BasicCardTemplate",
		kind = "community",
	},
	{
		rootPart = "SaweriaDonationBoard",
		guiName = "SaweriaDonationBoardGUI",
		topCards = { "1stPlaceCard", "2ndPlaceCard", "3rdPlaceCard" },
		templateName = "BasicCardTemplate",
		kind = "saweria",
	},
	{
		rootPart = "LikesLeaderboard",
		guiName = "LikesLeaderboardGUI",
		topCards = { "1stPlaceWrapper", "2rdPlaceWrapper", "3rdPlaceWrapper" },
		templateName = "BasicCardTemplate",
		kind = "likes",
	},
}

local POSTER_ROOTS = {
	"Top1Robux",
	"Top2Robux",
	"Top3Robux",
	"Top1Cash",
	"Top2Cash",
	"Top3Cash",
}

-- Poster v2 field path (first segment only deep-check; full path listed in notes)
local POSTER_REQUIRED_DESCENDANTS = {
	"CanvasGroup",
	"PlayerProfileThumbnail",
	"PlayerDisplayName",
	"PlayerUsername",
	"TotalDonations",
}

local MARQUEE_ROOTS = {
	"RunningText",
	"LiveChatDonations",
}

local LOADING_OVERLAY = "LoadingOverlay"
local MAIN_CONTENT = "MainContentWrapper"

local function findNamed(name: string): Instance?
	return workspace:FindFirstChild(name, true)
end

local function findSurfaceGui(root: Instance, expectedName: string): (SurfaceGui?, boolean)
	local named = root:FindFirstChild(expectedName, true)
	if named and named:IsA("SurfaceGui") then
		return named, false
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("SurfaceGui") then
			return d, true
		end
	end
	return nil, false
end

local function hasDescendantNamed(root: Instance, name: string): boolean
	return root:FindFirstChild(name, true) ~= nil
end

print("========================================")
print("  WORKSPACE LEADERBOARD SETUP CHECK")
print("  (read-only — Club Kit paint contract)")
print("========================================")

print("\n[1] Leaderboard boards")
for _, spec in ipairs(BOARD_SPECS) do
	print(string.format("\n  -- %s (%s)", spec.rootPart, spec.kind))
	local root = findNamed(spec.rootPart)
	if not root then
		fail(("Root '%s' missing"):format(spec.rootPart), "Must exist somewhere under Workspace (nested Folder OK)")
		continue
	end
	ok(("Root '%s' found"):format(spec.rootPart), root:GetFullName())

	local gui, auto = findSurfaceGui(root, spec.guiName)
	if not gui then
		fail(("No SurfaceGui under '%s'"):format(spec.rootPart), ("Expected name '%s'"):format(spec.guiName))
		continue
	end
	if auto then
		note(
			("SurfaceGui auto-name '%s'"):format(gui.Name),
			("Expected '%s' — paint may still work via auto-discover"):format(spec.guiName)
		)
	else
		ok(("SurfaceGui '%s'"):format(spec.guiName))
	end

	if hasDescendantNamed(gui, LOADING_OVERLAY) then
		ok(LOADING_OVERLAY)
	else
		fail(LOADING_OVERLAY .. " missing", "Without this, boards stay on Studio placeholders (no loading chrome)")
	end

	if hasDescendantNamed(gui, MAIN_CONTENT) then
		ok(MAIN_CONTENT)
	else
		fail(MAIN_CONTENT .. " missing", "Paint toggles this vs LoadingOverlay")
	end

	if hasDescendantNamed(gui, spec.templateName) then
		ok(("Template '%s'"):format(spec.templateName))
	else
		fail(("Template '%s' missing"):format(spec.templateName), "Needed to clone rank rows")
	end

	local missingCards: { string } = {}
	for _, cardName in ipairs(spec.topCards) do
		if not hasDescendantNamed(gui, cardName) then
			table.insert(missingCards, cardName)
		end
	end
	if #missingCards == 0 then
		ok("Top cards present", table.concat(spec.topCards, ", "))
	else
		fail("Top cards missing", table.concat(missingCards, ", "))
	end
end

print("\n[2] Top posters (Top1–3 Robux/Cash)")
for _, name in ipairs(POSTER_ROOTS) do
	local root = findNamed(name)
	if not root then
		fail(("Poster root '%s' missing"):format(name))
		continue
	end
	ok(("Poster '%s'"):format(name), root:GetFullName())

	local gui, auto = findSurfaceGui(root, "SurfaceGui")
	if not gui then
		fail(("'%s' has no SurfaceGui"):format(name))
		continue
	end
	if auto and gui.Name ~= "SurfaceGui" then
		note(("'%s' SurfaceGui named '%s'"):format(name, gui.Name), "Expected 'SurfaceGui'")
	else
		ok(("'%s' SurfaceGui"):format(name))
	end

	local missingFields: { string } = {}
	for _, fieldName in ipairs(POSTER_REQUIRED_DESCENDANTS) do
		if not hasDescendantNamed(gui, fieldName) then
			table.insert(missingFields, fieldName)
		end
	end
	if #missingFields == 0 then
		ok(("'%s' poster fields"):format(name))
	else
		fail(("'%s' poster fields missing"):format(name), table.concat(missingFields, ", "))
	end
end

print("\n[3] Donation marquees (TagDonationDisplayRoots)")
for _, name in ipairs(MARQUEE_ROOTS) do
	local root = findNamed(name)
	if not root then
		fail(("Marquee root '%s' missing"):format(name), "Explains TagDonationDisplayRoots totalTagged=0 for this name")
	else
		ok(("Marquee '%s'"):format(name), root:GetFullName())
	end
end

local daily = findNamed("DailyDonations")
if daily then
	ok("DailyDonations present (optional)", daily:GetFullName())
else
	note("DailyDonations not found", "Optional daily showcase board — OK if unused")
end

print("\n========================================")
print(string.format("  SUMMARY  OK=%d  FAIL=%d  WARN=%d", passCount, failCount, warnCount))
if failCount == 0 then
	print("  Hierarchy looks paint-ready. If boards still stuck:")
	print("    • Wait ~25s for leaderboard prewarm, or /refreshleaderboard all")
	print("    • Compare Output: Leaderboard payload built / paint incomplete")
else
	print("  Fix FAIL items on the broken place (copy GUI structure from a working map).")
end
print("========================================")
