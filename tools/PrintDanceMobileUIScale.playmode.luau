-- Paste ke Command Bar saat Play (atau Edit).
local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
	or game:GetService("StarterGui")
local ig = pg and pg:FindFirstChild("IconGroup")
local mobile = ig and ig:FindFirstChild("DancePanelGUIWrapperv2Mobile")
if not mobile then
	warn("[DanceMobileUIScale] DancePanelGUIWrapperv2Mobile tidak ditemukan di", ig and ig:GetFullName() or "PlayerGui")
	return
end
local scales = {}
for _, c in mobile:GetDescendants() do
	if c:IsA("UIScale") then
		table.insert(scales, string.format("%s Scale=%.4f", c:GetFullName(), c.Scale))
	end
end
print(string.format("[DanceMobileUIScale] %s | Visible=%s | Layout=%s", mobile:GetFullName(), tostring((mobile :: GuiObject).Visible), tostring(mobile:GetAttribute("DancePanelLayout"))))
local rootScale = mobile:FindFirstChild("UIScale")
local animScale = mobile:FindFirstChild("DancePanelRootScale")
if rootScale and rootScale:IsA("UIScale") then
	print(string.format("[DanceMobileUIScale] baked UIScale=%.4f (target mobile ~0.75)", rootScale.Scale))
end
if animScale and animScale:IsA("UIScale") then
	print(string.format("[DanceMobileUIScale] DancePanelRootScale=%.4f (anim, should stay 1)", animScale.Scale))
end
if #scales == 0 then
	print("[DanceMobileUIScale] (tidak ada UIScale di subtree)")
else
	for _, line in ipairs(scales) do
		print("[DanceMobileUIScale]", line)
	end
end
