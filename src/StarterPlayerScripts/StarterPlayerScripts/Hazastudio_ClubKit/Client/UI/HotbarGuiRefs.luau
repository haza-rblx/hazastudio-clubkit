--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)

local HotbarGuiRefs = {}

export type SlotRefs = {
	button: GuiButton,
	imageLabel: ImageLabel?,
	textLabel: TextLabel?,
	stroke: UIStroke?,
	scale: UIScale?,
	dragDetector: UIDragDetector?,
}

export type Refs = {
	root: ScreenGui,
	hotbarWrapper: Frame,
	stickerButtonWrapper: Frame,
	slots: { SlotRefs },
	stickerButton: GuiButton?,
	backpackButton: GuiButton?,
}

type SlotEntry = {
	slot: SlotRefs,
	layoutOrder: number,
	sourceIndex: number,
}

local function resolveRoot(playerGui: PlayerGui): ScreenGui?
	for _, name in ipairs(Config.Hotbar.GUI_NAMES) do
		local direct = playerGui:FindFirstChild(name)
		if direct and direct:IsA("ScreenGui") then
			return direct :: ScreenGui
		end

		local recursive = playerGui:FindFirstChild(name, true)
		if recursive and recursive:IsA("ScreenGui") then
			return recursive :: ScreenGui
		end
	end

	return nil
end

local SLOT_TEMPLATE_NAME = "Item"

local function isSlotButtonName(name: string, backpackButtonName: string): boolean
	if name == backpackButtonName then
		return false
	end
	if name == SLOT_TEMPLATE_NAME then
		return true
	end
	return string.sub(name, 1, 4) == "Item"
end

local function findSlotTemplate(wrapper: Frame, backpackButtonName: string): GuiButton?
	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("GuiButton") and isSlotButtonName(child.Name, backpackButtonName) then
			return child :: GuiButton
		end
	end

	for _, descendant in ipairs(wrapper:GetDescendants()) do
		if descendant:IsA("GuiButton") and isSlotButtonName(descendant.Name, backpackButtonName) then
			return descendant :: GuiButton
		end
	end

	return nil
end

-- Hotbar ships one `Item` template; clone up to device max for multiple tools.
local function ensureSlotButtons(wrapper: Frame, backpackButtonName: string): ()
	local maxSlots = PhoneLayout.getHotbarMaxSlots()
	local template = findSlotTemplate(wrapper, backpackButtonName)
	if not template then
		return
	end

	local existing = 0
	for _, child in ipairs(wrapper:GetDescendants()) do
		if child:IsA("GuiButton") and child ~= template and isSlotButtonName(child.Name, backpackButtonName) then
			existing += 1
		end
	end

	local needed = math.max(0, maxSlots - 1 - existing)
	for index = 1, needed do
		local clone = template:Clone()
		clone.Name = SLOT_TEMPLATE_NAME .. "_" .. tostring(index)
		clone.LayoutOrder = template.LayoutOrder + index
		clone.Visible = true
		clone.Parent = wrapper
	end
end

local function collectSlots(container: Frame): { SlotRefs }
	local entries = {} :: { SlotEntry }

	local backpackButtonName = Config.Hotbar.BACKPACK_BUTTON_NAME

	local seen = {} :: { [GuiButton]: boolean }
	local function addSlotButton(button: GuiButton, sourceIndex: number)
		if seen[button] then
			return
		end
		seen[button] = true

		local imageLabel = button:FindFirstChildWhichIsA("ImageLabel", true)
		local textLabel = button:FindFirstChildWhichIsA("TextLabel", true)
		local stroke = button:FindFirstChildWhichIsA("UIStroke")
		local scale = button:FindFirstChildWhichIsA("UIScale")
		local dragDetector = button:FindFirstChildWhichIsA("UIDragDetector")

		table.insert(entries, {
			slot = {
				button = button,
				imageLabel = if imageLabel and imageLabel:IsA("ImageLabel") then imageLabel else nil,
				textLabel = if textLabel and textLabel:IsA("TextLabel") then textLabel else nil,
				stroke = if stroke and stroke:IsA("UIStroke") then stroke else nil,
				scale = if scale and scale:IsA("UIScale") then scale else nil,
				dragDetector = if dragDetector and dragDetector:IsA("UIDragDetector") then dragDetector else nil,
			},
			layoutOrder = button.LayoutOrder,
			sourceIndex = sourceIndex,
		})
	end

	for index, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiButton") and isSlotButtonName(child.Name, backpackButtonName) then
			addSlotButton(child :: GuiButton, index)
		end
	end

	for index, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("GuiButton") and isSlotButtonName(descendant.Name, backpackButtonName) then
			addSlotButton(descendant :: GuiButton, index + 1000)
		end
	end

	table.sort(entries, function(left: SlotEntry, right: SlotEntry): boolean
		if left.layoutOrder == right.layoutOrder then
			return left.sourceIndex < right.sourceIndex
		end
		return left.layoutOrder < right.layoutOrder
	end)

	local slots = {} :: { SlotRefs }
	local maxSlots = PhoneLayout.getHotbarMaxSlots()
	for index, entry in ipairs(entries) do
		if index > maxSlots then
			break
		end
		table.insert(slots, entry.slot)
	end

	return slots
end

local function collectFirstButton(container: Frame): GuiButton?
	local configured = container:FindFirstChild(Config.Hotbar.STICKER_TRIGGER_NAME, true)
	if configured and configured:IsA("GuiButton") then
		return configured :: GuiButton
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			return descendant :: GuiButton
		end
	end

	return nil
end

function HotbarGuiRefs.resolve(playerGui: PlayerGui): Types.Result<Refs>
	local root = resolveRoot(playerGui)
	if not root then
		return {
			ok = false,
			error = ("HotbarGuiRefs: missing ScreenGui, expected one of %s"):format(
				table.concat(Config.Hotbar.GUI_NAMES, ", ")
			),
		}
	end

	local hotbarWrapper = root:FindFirstChild(Config.Hotbar.HOTBAR_WRAPPER_NAME, true)
	if not hotbarWrapper or not hotbarWrapper:IsA("Frame") then
		return {
			ok = false,
			error = ("HotbarGuiRefs: missing Frame '%s' under %s"):format(
				Config.Hotbar.HOTBAR_WRAPPER_NAME,
				root:GetFullName()
			),
		}
	end

	local stickerWrapper = root:FindFirstChild(Config.Hotbar.STICKER_WRAPPER_NAME, true)
	if not stickerWrapper or not stickerWrapper:IsA("Frame") then
		return {
			ok = false,
			error = ("HotbarGuiRefs: missing Frame '%s' under %s"):format(
				Config.Hotbar.STICKER_WRAPPER_NAME,
				root:GetFullName()
			),
		}
	end

	local backpackButtonName = Config.Hotbar.BACKPACK_BUTTON_NAME
	ensureSlotButtons(hotbarWrapper :: Frame, backpackButtonName)

	local slots = collectSlots(hotbarWrapper :: Frame)
	if #slots == 0 then
		return {
			ok = false,
			error = ("HotbarGuiRefs: no GuiButton slot children found under %s"):format(hotbarWrapper:GetFullName()),
		}
	end

	local backpackChild = (hotbarWrapper :: Frame):FindFirstChild(backpackButtonName, true)
	local backpackButton = if backpackChild and backpackChild:IsA("GuiButton") then backpackChild :: GuiButton else nil

	return {
		ok = true,
		value = {
			root = root,
			hotbarWrapper = hotbarWrapper :: Frame,
			stickerButtonWrapper = stickerWrapper :: Frame,
			slots = slots,
			stickerButton = collectFirstButton(stickerWrapper :: Frame),
			backpackButton = backpackButton,
		},
	}
end

return HotbarGuiRefs
