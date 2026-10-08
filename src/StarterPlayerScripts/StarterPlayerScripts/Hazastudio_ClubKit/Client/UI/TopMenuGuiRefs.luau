--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local TopMenuGuiRefs = {}

export type ButtonMap = { [string]: TextButton }

export type Refs = {
	root: ScreenGui,
	desktopMenu: Frame,
	phoneMenu: ScrollingFrame,
	desktopButtons: ButtonMap,
	phoneButtons: ButtonMap,
	-- The same buttons in visual order, for the open cascade (ADR 0011).
	desktopRows: { GuiObject },
	phoneRows: { GuiObject },
}

local BUTTON_NAMES = {
	Config.TopbarMenu.BUTTONS.COUPLE,
	Config.TopbarMenu.BUTTONS.GIFT,
	Config.TopbarMenu.BUTTONS.DONATIONS,
	Config.TopbarMenu.BUTTONS.BROADCAST,
	Config.TopbarMenu.BUTTONS.SHOP,
	Config.TopbarMenu.BUTTONS.CINEMATIC_DOCK,
	Config.TopbarMenu.BUTTONS.PROFILE,
	Config.TopbarMenu.BUTTONS.SETTINGS,
	Config.TopbarMenu.BUTTONS.COMMUNITY,
	Config.TopbarMenu.BUTTONS.QUESTS,
	Config.TopbarMenu.BUTTONS.EVENT,
	Config.TopbarMenu.BUTTONS.ADMIN_PANEL,
	Config.TopbarMenu.BUTTONS.MUSIC_PLAYER,
}

local function expect(parent: Instance, name: string, timeout: number?): Instance
	local child = parent:WaitForChild(name, timeout or 15)
	assert(child, ("TopMenuGuiRefs: missing '%s' under %s"):format(name, parent:GetFullName()))
	return child
end

local function asFrame(instance: Instance): Frame
	assert(instance:IsA("Frame"), ("Expected Frame, got %s"):format(instance.ClassName))
	return instance :: Frame
end

local function asScrollingFrame(instance: Instance): ScrollingFrame
	assert(instance:IsA("ScrollingFrame"), ("Expected ScrollingFrame, got %s"):format(instance.ClassName))
	return instance :: ScrollingFrame
end

local function asTextButton(instance: Instance): TextButton
	assert(instance:IsA("TextButton"), ("Expected TextButton, got %s"):format(instance.ClassName))
	return instance :: TextButton
end

local function resolveButtons(menuRoot: Instance): ButtonMap
	local buttons: ButtonMap = {}
	for _, buttonName in ipairs(BUTTON_NAMES) do
		local found = menuRoot:FindFirstChild(buttonName, true)
		if found then
			buttons[buttonName] = asTextButton(found)
		end
	end
	return buttons
end

-- Top to bottom: sections sort by name (Section1..Section4), rows inside one section by
-- LayoutOrder then name — what a UIListLayout does under either SortOrder while the designs leave
-- LayoutOrder at 0. Order only decides the cascade, so a design that disagrees still animates.
local function orderRows(buttons: ButtonMap): { GuiObject }
	local rows: { GuiObject } = {}
	for _, button in pairs(buttons) do
		table.insert(rows, button)
	end
	table.sort(rows, function(a: GuiObject, b: GuiObject): boolean
		local sectionA = if a.Parent then a.Parent.Name else ""
		local sectionB = if b.Parent then b.Parent.Name else ""
		if sectionA ~= sectionB then
			return sectionA < sectionB
		end
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)
	return rows
end

local function resolveRoot(playerGui: PlayerGui, guiName: string): ScreenGui
	local existing = playerGui:FindFirstChild(guiName)
	if existing and existing:IsA("ScreenGui") then
		return existing :: ScreenGui
	end

	local waited = playerGui:WaitForChild(guiName, 20)
	if waited and waited:IsA("ScreenGui") then
		return waited :: ScreenGui
	end

	local template = StarterGui:FindFirstChild(guiName)
	if template and template:IsA("ScreenGui") then
		local cloned = template:Clone()
		cloned.Parent = playerGui
		return cloned :: ScreenGui
	end

	assert(false, ("TopMenuGuiRefs: missing '%s' in PlayerGui and StarterGui"):format(guiName))
end

function TopMenuGuiRefs.resolve(playerGui: PlayerGui): Refs
	local cfg = Config.TopbarMenu
	local root = resolveRoot(playerGui, cfg.GUI_NAME)

	local desktopMenu = asFrame(expect(root, cfg.DESKTOP_FRAME_NAME, 15))
	local phoneMenu = asScrollingFrame(expect(root, cfg.PHONE_FRAME_NAME, 15))

	local desktopButtons = resolveButtons(desktopMenu)
	local phoneButtons = resolveButtons(phoneMenu)

	return {
		root = root,
		desktopMenu = desktopMenu,
		phoneMenu = phoneMenu,
		desktopButtons = desktopButtons,
		phoneButtons = phoneButtons,
		desktopRows = orderRows(desktopButtons),
		phoneRows = orderRows(phoneButtons),
	}
end

return TopMenuGuiRefs
