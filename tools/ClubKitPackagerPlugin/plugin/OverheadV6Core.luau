--!nocheck
-- P4b Stage 1 (ADR 0018): build OverheadGUIMainTemplateV6 (the trimmed 49-instance V5) inside
-- the open place, next to V4 â€” never replacing it â€” and port the buyer's V4/V5 customisations
-- by name. Called from the plugin's Tools page ("Nametag â†’ Install V6").
--
-- Shape authority: docs/plans/hardening-2026-09-24/p4b-overhead-template.md Â§2 (the AFTER tree)
-- and p4b-template-inventory.md (the V4 tree it was measured from). The renderer contract is
-- the names; every sizing decision below carries the inventory number it came from.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local OverheadV6Core = {}

local TEMPLATE_V6_NAME = "OverheadGUIMainTemplateV6"
local TEMPLATE_V4_NAME = "OverheadGUIMainTemplateV4"
local TEMPLATE_V5_NAME = "OverheadGUIMainTemplateV5"

-- The renderer's contract names (OverheadUI.luau ALL_BADGES + lazy list). `06-VVIPMemberBagde`
-- keeps the typo; `07-ELITEMemberBadge` is the code's name (a V4 place with the old
-- `07-SupremeMemberBadge` never shows that badge â€” the port maps it explicitly).
local BADGE_NAMES = {
	"01-OwnerCoOwnerBadge",
	"02-DeveloperBadge",
	"03-AdminBadge",
	"04-MemberBadge",
	"05-VIPMemberBadge",
	"06-VVIPMemberBagde",
	"07-ELITEMemberBadge",
	"08-StreakBadge",
	"09-LikeCounterBadge",
	"10-CommunityBadge",
	"11-DJBadge",
	"12-InfluencerBadge",
}

local MEMBERSHIP_GRADIENT_NAMES = { "UIGradientElite", "UIGradientGuest", "UIGradientMember", "UIGradientVIP", "UIGradientVVIP" }
local COUPLE_GRADIENT_NAMES = { "UIGradient", "UIGradientFun", "UIGradientSingle" }

local PORT_BADGE_FROM_SUPREME = "07-SupremeMemberBadge"

-- ----------------------------------------------------------------
-- Small builders
-- ----------------------------------------------------------------
local function prop(inst: Instance, props: { [string]: any }): Instance
	for k, v in pairs(props) do
		(inst :: any)[k] = v
	end
	return inst
end

local function frame(parent: Instance, name: string, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = parent
	for k, v in pairs(props) do
		(f :: any)[k] = v
	end
	return f
end

local function textLabel(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Parent = parent
	for k, v in pairs(props) do
		(t :: any)[k] = v
	end
	return t
end

local function imageLabel(parent: Instance, name: string, props: { [string]: any }): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	i.Parent = parent
	for k, v in pairs(props) do
		(i :: any)[k] = v
	end
	return i
end

local function listLayout(parent: Instance, props: { [string]: any }): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Parent = parent
	for k, v in pairs(props) do
		(l :: any)[k] = v
	end
	return l
end

-- V4's black row backgrounds (00-SpecialStatus, 04-SpecialRank) are not solid: a black
-- UIGradient with these transparency stops fades them out to both sides. The port copies
-- the buyer's own gradient over these defaults.
local STATUS_FADE = { { 0, 1 }, { 0.2, 0.4 }, { 0.51, 0.06 }, { 0.8, 0.39 }, { 1, 1 } }
local RANK_FADE = { { 0, 1 }, { 0.09, 1 }, { 0.3, 0.49 }, { 0.51, 0.06 }, { 0.7, 0.51 }, { 0.9, 1 }, { 1, 1 } }

local function fadeGradient(row: GuiObject, stops: { { number } }): UIGradient
	local keypoints = {}
	for _, stop in ipairs(stops) do
		table.insert(keypoints, NumberSequenceKeypoint.new(stop[1], stop[2]))
	end
	local grad = Instance.new("UIGradient")
	grad.Name = "UIGradient"
	grad.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
	grad.Transparency = NumberSequence.new(keypoints)
	grad.Parent = row
	return grad
end

-- ----------------------------------------------------------------
-- Template build (the Â§2 AFTER tree, 49 instances)
-- ----------------------------------------------------------------
function OverheadV6Core.buildTemplate(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = TEMPLATE_V6_NAME
	-- V4 was 5Ã—4 studs under a 0.95 UIScale; V6 bakes 0.95 in (design risk 2 â†’ owner-confirmed
	-- pixel gate covers the residue).
	gui.Size = UDim2.new(4.75, 0, 3.8, 0)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	-- Inert (the renderer overwrites per apply: Near 28 / Medium 48 / Far 90); 48 = the default.
	gui.MaxDistance = 48
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0.5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local wrapper = frame(gui, "Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	listLayout(wrapper, {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.Name,
		Padding = UDim.new(0.005, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	})

	-- 00-DonationLayers (#4â€“13): container + two 4-instance chips.
	local layers = frame(wrapper, "00-DonationLayers", { Size = UDim2.fromScale(1, 0.12) })
	listLayout(layers, {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.Name,
		Padding = UDim.new(0.02, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})

	local function chip(name: string, labelSize: UDim2, labelPos: UDim2): Frame
		local c = frame(layers, name, {
			-- Both chips are 0.33 wide in V4 (inventory #5/#9); the Rupiah chip's 0.8 is its
			-- LABEL width (V4's 0.1 side padding), not the chip's.
			Size = UDim2.fromScale(0.33, 0.88),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0,
		})
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = c
		local grad = Instance.new("UIGradient")
		grad.Name = "UIGradient"
		-- V4's 4-stop rainbow (inventory #13); the renderer animates / repaints it.
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 128, 255)),
		})
		grad.Parent = c
		local label = textLabel(c, if name == "RobuxRankWrapper" then "RobuxRank" else "RupiahRank", {
			Size = labelSize,
			Position = labelPos,
			Font = Enum.Font.GothamBold, -- legacy Enum.Font.ExtraBold was removed; GothamBold is the closest shipped face
			TextScaled = true,
			Text = "",
			TextColor3 = Color3.fromRGB(255, 255, 255),
		})
		-- V4's dark text outline: white text on the bright rainbow is unreadable without it.
		local labelStroke = Instance.new("UIStroke")
		labelStroke.Color = Color3.fromRGB(45, 45, 45)
		labelStroke.Thickness = 1
		labelStroke.Parent = label
		return c
	end
	chip("RobuxRankWrapper", UDim2.fromScale(1, 0.64), UDim2.fromScale(0, 0.18))
	chip("RupiahRankWrapper", UDim2.fromScale(0.8, 0.64), UDim2.fromScale(0.1, 0.18))

	-- 00-SpecialStatus (#14): Frame + label, NOT row-is-label. V4's black background fades out
	-- to both sides through a transparency gradient; on a row-is-label that gradient would fade
	-- the text too, and without it the row paints as a solid black bar.
	local statusRow = frame(wrapper, "00-SpecialStatus", {
		Size = UDim2.fromScale(1, 0.09),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0,
		Visible = false,
	})
	statusRow.LayoutOrder = 4
	fadeGradient(statusRow, STATUS_FADE)
	textLabel(statusRow, "StatusValue", {
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Font = Enum.Font.GothamBold, -- legacy Enum.Font.ExtraBold was removed; GothamBold is the closest shipped face
		TextScaled = true,
		TextColor3 = Color3.fromRGB(217, 217, 217),
	})

	-- 01-SpecialTitle (#15â€“17).
	local titleRow = frame(wrapper, "01-SpecialTitle", {
		Size = UDim2.fromScale(1, 0.08),
		LayoutOrder = 5,
	})
	textLabel(titleRow, "SpecialTitleText", {
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = "",
	})
	local titleText = titleRow:FindFirstChild("SpecialTitleText") :: TextLabel
	local titleGrad = Instance.new("UIGradient")
	titleGrad.Name = "UIGradient"
	titleGrad.Parent = titleText

	-- 02-AddOnCustomImageBadge (#18â€“19, the V5 row, hidden): so one template serves V4 and V5
	-- venues. Sizing mirrors the V5 master (image row directly under the title by Name sort).
	local imageRow = frame(wrapper, "02-AddOnCustomImageBadge", {
		Size = UDim2.fromScale(1, 0.22),
		Visible = false,
		LayoutOrder = 6,
	})
	imageLabel(imageRow, "ChangeableImage", {
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Fit,
		Image = "",
	})

	-- 02-BadgeGroup (#20â€“37): 12 flat ImageLabels, SizeConstraint RelativeYY replaces the
	-- 12 Frames + 12 AR constraints; the three counter badges keep their one child each.
	local badgeGroup = frame(wrapper, "02-BadgeGroup", { Size = UDim2.fromScale(1, 0.14) })
	listLayout(badgeGroup, {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.Name,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})
	for _, badgeName in ipairs(BADGE_NAMES) do
		local badge = imageLabel(badgeGroup, badgeName, {
			Size = UDim2.fromScale(1, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Image = "",
		})
		if badgeName == "08-StreakBadge" then
			textLabel(badge, "TextLabel", {
				Size = UDim2.fromScale(0.37, 0.48),
				Position = UDim2.fromScale(0.34, 0.32),
				TextScaled = true,
				Text = "",
			})
		elseif badgeName == "09-LikeCounterBadge" then
			textLabel(badge, "LikeCounts", {
				Size = UDim2.fromScale(0.42, 0.43),
				Position = UDim2.fromScale(0.29, 0.26),
				TextScaled = true,
				Text = "",
			})
		elseif badgeName == "10-CommunityBadge" then
			local logo = imageLabel(badge, "CommunityLogo", {
				Size = UDim2.fromScale(0.64, 0.64),
				Position = UDim2.fromScale(0.19, 0.19),
				Image = "",
			})
			local logoCorner = Instance.new("UICorner")
			logoCorner.CornerRadius = UDim.new(0.3, 0)
			logoCorner.Parent = logo
		end
	end

	-- 03-Level (#38): the row IS the label (R4).
	local levelRow = textLabel(wrapper, "03-Level", {
		Size = UDim2.fromScale(1, 0.065),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Visible = false,
	})
	levelRow.LayoutOrder = 10

	-- 04-SpecialRank (#39â€“41).
	local rankRow = frame(wrapper, "04-SpecialRank", {
		Size = UDim2.fromScale(1, 0.08),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0,
		Visible = false,
	})
	rankRow.LayoutOrder = 11
	fadeGradient(rankRow, RANK_FADE)
	local rankLabel = textLabel(rankRow, "SpecialRoleName", {
		Size = UDim2.fromScale(1, 0.8),
		Position = UDim2.fromScale(0, 0.1),
		Font = Enum.Font.GothamBold, -- legacy Enum.Font.ExtraBold was removed; GothamBold is the closest shipped face
		TextScaled = true,
		Text = "",
	})
	local rankGrad = Instance.new("UIGradient")
	rankGrad.Name = "UIGradient"
	rankGrad.Color = ColorSequence.new(Color3.fromRGB(255, 175, 15), Color3.fromRGB(255, 160, 28))
	rankGrad.Parent = rankLabel

	-- 08-DisplayNameAndMembership (#42â€“47).
	local nameRow = frame(wrapper, "08-DisplayNameAndMembership", {
		Size = UDim2.fromScale(1, 0.1),
		LayoutOrder = 14,
	})
	listLayout(nameRow, {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.005, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		-- V4 centres vertically; UIListLayout defaults to Top, which lifts the 0.6-scaled
		-- separator bullet to the top of the row.
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	textLabel(nameRow, "PlayerDisplayName", {
		LayoutOrder = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		RichText = true,
		Text = "",
	})
	-- Exactly V4's shape: a full-height scaled label shrunk by a 0.6 UIScale. A 0.6-high label
	-- without TextScaled renders the bullet at the default TextSize, as a speck near the top.
	local separator = textLabel(nameRow, "Separator", {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextSize = 42,
		RichText = true,
		Text = utf8.char(0x2022),
		TextColor3 = Color3.fromRGB(255, 255, 255),
	})
	local separatorScale = Instance.new("UIScale")
	separatorScale.Scale = 0.6
	separatorScale.Parent = separator
	local membership = textLabel(nameRow, "MembershipLevel", {
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		RichText = true,
		Text = "",
	})
	local membershipGrad = Instance.new("UIGradient")
	membershipGrad.Name = "UIGradient"
	membershipGrad.Parent = membership

	-- 09-CoupleDisplayName (#48â€“49): the row IS the label (R4).
	local coupleRow = textLabel(wrapper, "09-CoupleDisplayName", {
		Size = UDim2.fromScale(1, 0.07),
		Text = "",
		Font = Enum.Font.GothamBold, -- legacy Enum.Font.ExtraBold was removed; GothamBold is the closest shipped face
		TextScaled = true,
		Visible = false,
	})
	coupleRow.LayoutOrder = 15
	local coupleGrad = Instance.new("UIGradient")
	coupleGrad.Name = "UIGradient"
	coupleGrad.Parent = coupleRow

	return gui
end

-- ----------------------------------------------------------------
-- Attribute scheme (R2/R3): one gradient per set, colours as attributes
-- ----------------------------------------------------------------
function OverheadV6Core.applyGradientAttributes(gui: BillboardGui, sources: { [string]: BillboardGui })
	local function findGradient(root: Instance, name: string): UIGradient?
		local hit = root:FindFirstChild(name, true)
		return if hit and hit:IsA("UIGradient") then hit else nil
	end

	local function portSet(gradient: UIGradient, names: { string })
		for _, gradName in ipairs(names) do
			-- Prefer a same-named gradient in any source template (V5 first: it is the newer).
			for _, source in ipairs(sources) do
				local src = findGradient(source, gradName)
				if src then
					gradient:SetAttribute(gradName, src.Color)
					gradient:SetAttribute(gradName .. "_Rotation", src.Rotation)
					break
				end
			end
		end
	end

	local membership = gui:FindFirstChild("MembershipLevel", true)
	local membershipGrad = membership and membership:FindFirstChildWhichIsA("UIGradient")
	if membershipGrad then
		portSet(membershipGrad, MEMBERSHIP_GRADIENT_NAMES)
	end
	local coupleRow = gui:FindFirstChild("09-CoupleDisplayName", true)
	local coupleGrad = coupleRow and (coupleRow :: TextLabel):FindFirstChildWhichIsA("UIGradient")
	if coupleGrad then
		portSet(coupleGrad, COUPLE_GRADIENT_NAMES)
	end
end

-- ----------------------------------------------------------------
-- Port customisations from V4/V5 by name (design Â§7 step 4)
-- ----------------------------------------------------------------
export type PortReport = { ported: { string }, notPorted: { string } }

function OverheadV6Core.portCustomisations(gui: BillboardGui, sources: { [string]: BillboardGui }): PortReport
	local report: PortReport = { ported = {}, notPorted = {} }

	local function firstNamed(name: string): (Instance?, string?)
		for _, source in ipairs(sources) do
			local hit = source:FindFirstChild(name, true)
			if hit then
				return hit, source.Name
			end
		end
		return nil, nil
	end

	-- Badge art + ScaleType (with the Supreme â†’ ELITE mapping). A V4 badge frame holds the art
	-- on a child named `Badge`; if the badge frame itself carries no Image we take the child.
	for _, badgeName in ipairs(BADGE_NAMES) do
		local wanted = badgeName
		local fromName = badgeName
		local hit = firstNamed(wanted)
		if not hit and badgeName == "07-ELITEMemberBadge" then
			hit, fromName = firstNamed(PORT_BADGE_FROM_SUPREME)
			wanted = PORT_BADGE_FROM_SUPREME
		end
		local target = gui:FindFirstChild(badgeName, true)
		if hit and target then
			-- The V4 badge is a Frame (art on the child `Badge` ImageLabel); the art source is
			-- whichever ImageLabel actually carries an Image.
			local art = nil
			if hit:IsA("ImageLabel") and (hit :: ImageLabel).Image ~= "" then
				art = hit
			else
				art = (hit :: Instance):FindFirstChild("Badge") or (hit :: Instance):FindFirstChildWhichIsA("ImageLabel", true)
			end
			if art and art:IsA("ImageLabel") and target:IsA("ImageLabel") then
				(target :: ImageLabel).Image = (art :: ImageLabel).Image
				;(target :: ImageLabel).ScaleType = (art :: ImageLabel).ScaleType
				table.insert(report.ported, ("badge %s â† %s"):format(badgeName, fromName))
			else
				table.insert(report.notPorted, ("badge %s: no art image under %s"):format(badgeName, wanted))
			end
		else
			table.insert(report.notPorted, ("badge %s: not found in V4/V5"):format(badgeName))
		end
	end

	-- Per-label fonts + text colours. Separator's text is ported too: the bullet is
	-- data, not code, and a literal written through a JSON transport can arrive mojibake'd.
	for _, labelName in ipairs({
		"RobuxRank", "RupiahRank", "SpecialTitleText", "SpecialRoleName",
		"PlayerDisplayName", "MembershipLevel", "Separator", "TextLabel", "LikeCounts", "StatusValue",
	}) do
		local hit = firstNamed(labelName)
		local target = gui:FindFirstChild(labelName, true)
		if hit and hit:IsA("TextLabel") and target and target:IsA("TextLabel") then
			local src = hit :: TextLabel
			local dst = target :: TextLabel
			dst.FontFace = src.FontFace
			dst.TextColor3 = src.TextColor3
			if labelName == "Separator" then
				dst.Text = src.Text
			end
			table.insert(report.ported, ("label %s (font + colour)"):format(labelName))
		end
	end
	-- Row-is-label rows (R4) take the font of the V4 label they replaced.
	for rowName, sourceLabelName in pairs({
		["03-Level"] = "LevelCounterText",
		["09-CoupleDisplayName"] = "CoupleDisplayNameText",
	}) do
		local hit = firstNamed(sourceLabelName)
		local target = gui:FindFirstChild(rowName, true)
		if hit and hit:IsA("TextLabel") and target and target:IsA("TextLabel") then
			(target :: TextLabel).FontFace = (hit :: TextLabel).FontFace
			;(target :: TextLabel).TextColor3 = (hit :: TextLabel).TextColor3
			table.insert(report.ported, ("label %s <- %s (font + colour)"):format(rowName, sourceLabelName))
		end
	end

	-- Chip gradient colours.
	for _, chipName in ipairs({ "RobuxRankWrapper", "RupiahRankWrapper" }) do
		local hit = firstNamed(chipName)
		local target = gui:FindFirstChild(chipName, true)
		if hit and target then
			local srcGrad = (hit :: Instance):FindFirstChildWhichIsA("UIGradient", true)
			local dstGrad = (target :: Instance):FindFirstChildWhichIsA("UIGradient", true)
			if srcGrad and dstGrad then
				dstGrad.Color = srcGrad.Color
				dstGrad.Rotation = srcGrad.Rotation
				table.insert(report.ported, ("chip gradient %s"):format(chipName))
			end
		end
	end

	-- Special-rank text gradient.
	do
		local hit = firstNamed("SpecialRoleName")
		local target = gui:FindFirstChild("SpecialRoleName", true)
		if hit and hit:IsA("TextLabel") and target and target:IsA("TextLabel") then
			local srcGrad = (hit :: TextLabel):FindFirstChildWhichIsA("UIGradient")
			local dstGrad = (target :: TextLabel):FindFirstChildWhichIsA("UIGradient")
			if srcGrad and dstGrad then
				dstGrad.Color = srcGrad.Color
				dstGrad.Rotation = srcGrad.Rotation
				table.insert(report.ported, "special-rank gradient")
			end
		end
	end

	-- Status / rank row backgrounds: the row's own colour + its whole gradient (colour AND the
	-- transparency fade). Porting only the gradient's first colour paints a solid bar.
	for _, rowName in ipairs({ "00-SpecialStatus", "04-SpecialRank" }) do
		local hit = firstNamed(rowName)
		local target = gui:FindFirstChild(rowName, true)
		if hit and hit:IsA("GuiObject") and target and target:IsA("GuiObject") then
			(target :: GuiObject).BackgroundColor3 = (hit :: GuiObject).BackgroundColor3
			;(target :: GuiObject).BackgroundTransparency = (hit :: GuiObject).BackgroundTransparency
			local srcGrad = (hit :: Instance):FindFirstChildWhichIsA("UIGradient")
			local dstGrad = (target :: Instance):FindFirstChildWhichIsA("UIGradient")
			if srcGrad and dstGrad then
				dstGrad.Color = srcGrad.Color
				dstGrad.Transparency = srcGrad.Transparency
				dstGrad.Rotation = srcGrad.Rotation
				dstGrad.Offset = srcGrad.Offset
				dstGrad.Enabled = srcGrad.Enabled
			elseif dstGrad then
				dstGrad:Destroy()
			end
			table.insert(report.ported, ("%s background (colour + fade)"):format(rowName))
		end
	end

	-- Membership / couple gradients â†’ attributes.
	OverheadV6Core.applyGradientAttributes(gui, sources)

	-- Image row sizing from V5.
	do
		local v5 = nil
		for _, source in ipairs(sources) do
			if source.Name == TEMPLATE_V5_NAME then
				v5 = source
			end
		end
		local v5Row = v5 and v5:FindFirstChild("02-AddOnCustomImageBadge", true)
		local v6Row = gui:FindFirstChild("02-AddOnCustomImageBadge", true)
		if v5Row and v5Row:IsA("GuiObject") and v6Row and v6Row:IsA("GuiObject") then
			(v6Row :: GuiObject).Size = (v5Row :: GuiObject).Size
			table.insert(report.ported, "image row size â† V5")
		end
	end

	return report
end

-- ----------------------------------------------------------------
-- Install flow (design Â§7): precondition, backup, insert, port, report
-- ----------------------------------------------------------------
export type InstallReport = {
	ok: boolean,
	message: string,
	portReport: PortReport?,
}

function OverheadV6Core.install(): InstallReport
	local engineOk = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
		and (ReplicatedStorage.Hazastudio_ClubKit:FindFirstChild("Shared") ~= nil)
	if not engineOk then
		return { ok = false, message = "Kit engine not found in this place â€” Update Engine first.", portReport = nil }
	end
	-- Precondition: the engine knows V6 (Stage 0 installed).
	local kitConfig = ReplicatedStorage.Hazastudio_ClubKit.Shared:FindFirstChild("Constants")
		and ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants:FindFirstChild("Config")
	local engineKnowsV6 = false
	if kitConfig and kitConfig:IsA("ModuleScript") then
		local ok, config = pcall(require, kitConfig)
		engineKnowsV6 = ok and type(config) == "table" and type(config.OverheadGuiVariants) == "table"
			and config.OverheadGuiVariants.V6 ~= nil
	end
	if not engineKnowsV6 then
		return {
			ok = false,
			message = "This place's engine has no V6 variant â€” run Engine â†’ Update Engine first.",
			portReport = nil,
		}
	end

	ChangeHistoryService:SetWaypoint("ClubKit before Install V6")

	local existing = ReplicatedStorage:FindFirstChild(TEMPLATE_V6_NAME, true)
	if existing then
		local stamp = os.date("%Y%m%d")
		existing.Name = TEMPLATE_V6_NAME .. "_backup_" .. stamp
		print(("[ClubKitV6] Existing V6 renamed to %s (never overwritten)"):format(existing.Name))
	end

	-- Backup V4 (and V5 if present) by selection + waypoint; a real RBXM backup is written by
	-- the caller's save flow. Keeping V4 in the place IS the rollback (GuiType = "V4").
	local sources: { [string]: BillboardGui } = {}
	for _, name in ipairs({ TEMPLATE_V4_NAME, TEMPLATE_V5_NAME }) do
		local hit = ReplicatedStorage:FindFirstChild(name)
		if hit and hit:IsA("BillboardGui") then
			table.insert(sources, hit :: BillboardGui)
		end
	end
	if #sources == 0 then
		return {
			ok = false,
			message = "No V4/V5 template found in ReplicatedStorage â€” nothing to port from; install manually.",
			portReport = nil,
		}
	end

	local gui = OverheadV6Core.buildTemplate()
	gui.Parent = ReplicatedStorage

	local portReport = OverheadV6Core.portCustomisations(gui, sources)

	ChangeHistoryService:SetWaypoint("ClubKit after Install V6")

	local count = #gui:GetDescendants() + 1
	local lines = {
		("[ClubKitV6] Installed %s (%d instances, target 54) next to V4."):format(TEMPLATE_V6_NAME, count),
		("[ClubKitV6] Ported %d, not portable %d (list below)."):format(#portReport.ported, #portReport.notPorted),
		"[ClubKitV6] V4 was NOT modified. To switch: Config â†’ Overhead â†’ GuiType = \"V6\", save, publish. Undo = set GuiType back to \"V4\".",
	}
	for _, line in ipairs(portReport.ported) do
		table.insert(lines, "  + " .. line)
	end
	for _, line in ipairs(portReport.notPorted) do
		table.insert(lines, "  ! " .. line)
	end
	print(table.concat(lines, "\n"))

	return {
		ok = true,
		message = ("V6 installed (%d instances). Ported %d, not portable %d â€” see Output."):format(
			count,
			#portReport.ported,
			#portReport.notPorted
		),
		portReport = portReport,
	}
end

return OverheadV6Core

