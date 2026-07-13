--!strict
-- PATH: tools/ProbeWorkspaceLeaderboardRuntime.playmode.luau
--
-- Play-mode runtime probe: why boards show LoadingOverlay but text stuck on
-- Studio "placeholder", and whether paint actually wrote donor rows.
--
-- Run in Studio Command Bar WHILE PLAYING (Server or Client both OK; prefer Server):
--   1) Open this file, Select All, Copy
--   2) Paste into Command Bar, Enter
--
-- Does NOT modify the place (read-only prints).

local workspace = game:GetService("Workspace")

local BOARD_SPECS = {
	{
		rootPart = "RobuxDonationBoard",
		guiName = "RobuxDonationBoardGUI",
		topCards = { "1stPlaceWrapper", "2rdPlaceWrapper", "3rdPlaceWrapper" },
		kind = "robux",
	},
	{
		rootPart = "CommunityDonationBoard",
		guiName = "CommunityDonationBoardGUI",
		topCards = { "1stPlaceCommunityWrapper", "2ndPlaceCommunityWrapper", "3rdPlaceCommunityWrapper" },
		kind = "community",
	},
	{
		rootPart = "SaweriaDonationBoard",
		guiName = "SaweriaDonationBoardGUI",
		topCards = { "1stPlaceCard", "2ndPlaceCard", "3rdPlaceCard" },
		kind = "saweria",
	},
	{
		rootPart = "LikesLeaderboard",
		guiName = "LikesLeaderboardGUI",
		topCards = { "1stPlaceWrapper", "2rdPlaceWrapper", "3rdPlaceWrapper" },
		kind = "likes",
	},
}

local LOADING_OVERLAY = "LoadingOverlay"
local MAIN_CONTENT = "MainContentWrapper"
local DISPLAY_NAME_LABELS = { "PlayerDisplayName", "CommunityName" }

local function shortText(text: string, maxLen: number?): string
	local limit = maxLen or 60
	local cleaned = (text:gsub("%s+", " ")):sub(1, limit)
	if #text > limit then
		cleaned ..= "…"
	end
	return cleaned
end

local function findAllNamed(name: string): { Instance }
	local hits: { Instance } = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == name then
			table.insert(hits, d)
		end
	end
	return hits
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

-- Mirrors WorkspaceLeaderboardRenderer.findOverlayLabel
local function kitWouldPickOverlayLabel(overlay: Instance): TextLabel?
	local named = overlay:FindFirstChild("TextLabel", true)
	if named and named:IsA("TextLabel") then
		return named
	end
	for _, descendant in ipairs(overlay:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			return descendant
		end
	end
	return nil
end

local function findChrome(gui: Instance, childName: string): GuiObject?
	local direct = gui:FindFirstChild(childName)
	if direct and direct:IsA("GuiObject") then
		return direct
	end
	local nested = gui:FindFirstChild(childName, true)
	if nested and nested:IsA("GuiObject") then
		return nested
	end
	return nil
end

local function firstDisplayNameUnder(card: Instance): string?
	for _, labelName in ipairs(DISPLAY_NAME_LABELS) do
		local label = card:FindFirstChild(labelName, true)
		if label and label:IsA("TextLabel") then
			return label.Text
		end
	end
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text ~= "" then
			return d.Text
		end
	end
	return nil
end

print("========================================")
print("  WORKSPACE LEADERBOARD RUNTIME PROBE")
print("  (Play mode — read-only)")
print("========================================")

local revision = workspace:GetAttribute("LeaderboardRevision")
print(string.format("\n[0] Workspace.LeaderboardRevision = %s", tostring(revision)))
if revision == nil then
	warn("  [!] No revision yet — empty seed / DonationController may not have painted")
end

for _, spec in ipairs(BOARD_SPECS) do
	print(string.format("\n======== %s (%s) ========", spec.rootPart, spec.kind))

	local guiHits = findAllNamed(spec.guiName)
	print(string.format("  GUI name '%s' hits: %d", spec.guiName, #guiHits))
	for i, hit in ipairs(guiHits) do
		print(string.format("    [%d] %s  class=%s", i, hit:GetFullName(), hit.ClassName))
	end
	if #guiHits > 1 then
		warn("  [!] DUPLICATE GUI NAME — kit paints the first FindFirstChild hit; you may be looking at another")
	end

	local roots = findAllNamed(spec.rootPart)
	if #roots == 0 then
		warn("  [FAIL] root missing: " .. spec.rootPart)
		continue
	end
	if #roots > 1 then
		warn(string.format("  [!] duplicate root '%s' x%d", spec.rootPart, #roots))
		for i, r in ipairs(roots) do
			print(string.format("    root[%d] %s", i, r:GetFullName()))
		end
	end

	local root = roots[1]
	local gui, auto = findSurfaceGui(root, spec.guiName)
	if not gui then
		warn("  [FAIL] no SurfaceGui under root")
		continue
	end
	print(string.format("  Resolved GUI: %s%s", gui:GetFullName(), if auto then " (auto-discovered name)" else ""))

	local overlay = findChrome(gui, LOADING_OVERLAY)
	local main = findChrome(gui, MAIN_CONTENT)
	if not overlay then
		warn("  [FAIL] LoadingOverlay missing")
	else
		local nestedInMain = main ~= nil and overlay:IsDescendantOf(main)
		print(
			string.format(
				"  LoadingOverlay.Visible=%s  parent=%s%s",
				tostring(overlay.Visible),
				overlay.Parent and overlay.Parent.Name or "?",
				if nestedInMain then "  !! NESTED UNDER MainContentWrapper" else ""
			)
		)
		if nestedInMain then
			warn("  [!] Overlay nested in MainContent — hiding MainContent also hides overlay")
		end

		local labels: { TextLabel } = {}
		for _, d in ipairs(overlay:GetDescendants()) do
			if d:IsA("TextLabel") then
				table.insert(labels, d)
			end
		end
		print(string.format("  Overlay TextLabel count: %d", #labels))
		local picked = kitWouldPickOverlayLabel(overlay)
		for i, label in ipairs(labels) do
			local isPick = picked == label
			print(
				string.format(
					"    label[%d]%s  name=%s  Visible=%s  TextTransparency=%.2f  Text=%q  path=%s",
					i,
					if isPick then " << KIT PICKS THIS" else "",
					label.Name,
					tostring(label.Visible),
					label.TextTransparency,
					shortText(label.Text),
					label:GetFullName()
				)
			)
		end
		if picked then
			local t = string.lower(picked.Text)
			if string.find(t, "placeholder", 1, true) or picked.Text == "Label" or picked.Text == "TextLabel" then
				warn("  [!] Kit-picked label still looks like Studio authoring text — paint never wrote loading copy, or wrong label")
			end
		elseif overlay then
			warn("  [!] No TextLabel under LoadingOverlay — kit cannot set loading text")
		end
	end

	if not main then
		warn("  [FAIL] MainContentWrapper missing")
	else
		print(string.format("  MainContentWrapper.Visible=%s", tostring(main.Visible)))
	end

	-- Sample top-card text (proves data paint vs Studio mock)
	print("  Top-card sample text:")
	for _, cardName in ipairs(spec.topCards) do
		local card = gui:FindFirstChild(cardName, true)
		if not card then
			warn("    missing card " .. cardName)
		else
			local sample = firstDisplayNameUnder(card)
			print(
				string.format(
					"    %s Visible=%s  sample=%q",
					cardName,
					if card:IsA("GuiObject") then tostring(card.Visible) else "?",
					sample or "(no TextLabel)"
				)
			)
		end
	end
end

print("\n========================================")
print("  HOW TO READ")
print("  • Overlay Visible=true + kit label Text still 'placeholder'")
print("    → chrome on, text write miss / wrong label / animation not applied")
print("  • Robux top-card sample still mock after LeaderboardRevision set")
print("    → looking at wrong GUI, or card labels kit doesn't write")
print("  • Duplicate GUI hits → compare path you see in-world vs [1] kit paints")
print("========================================")
