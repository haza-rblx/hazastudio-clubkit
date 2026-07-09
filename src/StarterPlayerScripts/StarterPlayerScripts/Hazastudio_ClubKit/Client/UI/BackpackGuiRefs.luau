--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

local BackpackGuiRefs = {}

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
	wrapper: Frame,
	scrollFrame: ScrollingFrame,
	itemTemplate: GuiButton,
	gridLayout: UIGridLayout?,
}

local function resolveRoot(playerGui: PlayerGui): ScreenGui?
	local direct = playerGui:FindFirstChild(Config.Backpack.GUI_NAME)
	if direct and direct:IsA("ScreenGui") then
		return direct :: ScreenGui
	end

	local recursive = playerGui:FindFirstChild(Config.Backpack.GUI_NAME, true)
	if recursive and recursive:IsA("ScreenGui") then
		return recursive :: ScreenGui
	end

	return nil
end

function BackpackGuiRefs.resolve(playerGui: PlayerGui): Types.Result<Refs>
	local root = resolveRoot(playerGui)
	if not root then
		return {
			ok = false,
			error = ("BackpackGuiRefs: missing ScreenGui '%s'"):format(Config.Backpack.GUI_NAME),
		}
	end

	local wrapper = root:FindFirstChild(Config.Backpack.WRAPPER_NAME, true)
	if not wrapper or not wrapper:IsA("Frame") then
		return {
			ok = false,
			error = ("BackpackGuiRefs: missing Frame '%s' under %s"):format(
				Config.Backpack.WRAPPER_NAME,
				root:GetFullName()
			),
		}
	end

	local scrollFrame = wrapper:FindFirstChild(Config.Backpack.SCROLL_NAME, true)
	if not scrollFrame or not scrollFrame:IsA("ScrollingFrame") then
		return {
			ok = false,
			error = ("BackpackGuiRefs: missing ScrollingFrame '%s' under %s"):format(
				Config.Backpack.SCROLL_NAME,
				wrapper:GetFullName()
			),
		}
	end

	local template = scrollFrame:FindFirstChild(Config.Backpack.ITEM_TEMPLATE_NAME)
		or scrollFrame:FindFirstChild(Config.Backpack.ITEM_TEMPLATE_NAME, true)
	if not template or not template:IsA("GuiButton") then
		return {
			ok = false,
			error = ("BackpackGuiRefs: missing template GuiButton '%s' under %s"):format(
				Config.Backpack.ITEM_TEMPLATE_NAME,
				scrollFrame:GetFullName()
			),
		}
	end

	local gridLayout = scrollFrame:FindFirstChildWhichIsA("UIGridLayout")

	return {
		ok = true,
		value = {
			root = root,
			wrapper = wrapper :: Frame,
			scrollFrame = scrollFrame :: ScrollingFrame,
			itemTemplate = template :: GuiButton,
			gridLayout = if gridLayout and gridLayout:IsA("UIGridLayout") then gridLayout else nil,
		},
	}
end

function BackpackGuiRefs.slotRefsFromButton(button: GuiButton): SlotRefs
	local imageLabel = button:FindFirstChildWhichIsA("ImageLabel", true)
	local textLabel = button:FindFirstChildWhichIsA("TextLabel", true)
	local stroke = button:FindFirstChildWhichIsA("UIStroke")
	local scale = button:FindFirstChildWhichIsA("UIScale")
	local dragDetector = button:FindFirstChildWhichIsA("UIDragDetector")

	return {
		button = button,
		imageLabel = if imageLabel and imageLabel:IsA("ImageLabel") then imageLabel else nil,
		textLabel = if textLabel and textLabel:IsA("TextLabel") then textLabel else nil,
		stroke = if stroke and stroke:IsA("UIStroke") then stroke else nil,
		scale = if scale and scale:IsA("UIScale") then scale else nil,
		dragDetector = if dragDetector and dragDetector:IsA("UIDragDetector") then dragDetector else nil,
	}
end

return BackpackGuiRefs
