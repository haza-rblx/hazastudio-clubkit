--!strict
--[[
	Studio (Edit) utility — ensures AdminHub ActionTemplates live under:
	  StarterGui["04-AdminHub"].ActionTemplates._Hidden.<actionId>

	Paste into the Studio command bar / MCP execute_luau if templates appear
	under SheetBody (they would be destroyed by openSheet clearChildren).

	Does not rebuild missing trees — only rehomes known sheet root names.
]]

local gui = game.StarterGui:FindFirstChild("04-AdminHub")
assert(gui, "04-AdminHub missing")

local sheetBody = gui.MainWrapper["02-MainContentWrapper"]["04-ActionPopup"].SheetBody
local folder = gui:FindFirstChild("ActionTemplates")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "ActionTemplates"
	folder:SetAttribute(
		"KitNotes",
		"Editable sheet bodies for AdminHub. openSheet clones these into 04-ActionPopup.SheetBody."
	)
	folder.Parent = gui
end

local hold = folder:FindFirstChild("_Hidden")
if not hold then
	hold = Instance.new("Frame")
	hold.Name = "_Hidden"
	hold.Visible = false
	hold.BackgroundTransparency = 1
	hold.Size = UDim2.fromScale(0, 0)
	hold.Parent = folder
end

local moved = {}
for _, name in ipairs({ "announce", "role", "gift", "floatSpeed", "donate" }) do
	local frame = sheetBody:FindFirstChild(name) or folder:FindFirstChild(name)
	if frame and frame:IsA("GuiObject") then
		frame.Visible = false
		frame.Parent = hold
		table.insert(moved, name)
	end
end

local donate = hold:FindFirstChild("donate")
if donate then
	for _, pname in ipairs({ "Panel_test", "Panel_credit", "Panel_edit" }) do
		local p = donate:FindFirstChild(pname)
		if p and p:IsA("GuiObject") then
			p.Visible = pname == "Panel_test"
		end
	end
end

print("[RehomeAdminHubActionTemplates]", table.concat(moved, ", "))
