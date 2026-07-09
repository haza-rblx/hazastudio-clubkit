--!nocheck
-- ============================================================
-- HOTBAR / BACKPACK / STICKER — structural audit (Play Mode)
-- ============================================================
-- Guidelines v3: shape/count/flags only — no tool instances, no payloads.
--
-- CARA PAKAI:
-- 1. Play test di Studio.
-- 2. Paste script ini ke Command Bar → Enter.
-- 3. Salin baris [WARN][HotbarInventoryAudit] dari Output.
-- 4. Opsional: ketik /hotbaraudit di chat saat Play (jika Rojo sudah sync).
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then
	warn("[HotbarInventoryAudit] LocalPlayer tidak ada — jalankan saat Play.")
	return
end

local ok, auditModule = pcall(function()
	local sps = player:WaitForChild("PlayerScripts", 5)
	if not sps then
		return nil
	end
	local main = sps:WaitForChild("Main", 5)
	if not main then
		return nil
	end
	return require(main.Parent.Client.Debug.HotbarInventoryAudit)
end)

if ok and auditModule then
	auditModule.log(auditModule.collect(player, "command_bar"))
	print("[HotbarInventoryAudit] Audit dikirim ke Output via Logger (cari [HotbarInventoryAudit]).")
	return
end

-- Fallback jika Main belum load: audit manual minimal
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"):WaitForChild("Config"))

local function countTools(container: Instance?): number
	if not container then
		return 0
	end
	local n = 0
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("Tool") then
			n += 1
		end
	end
	return n
end

local playerGui = player:FindFirstChild("PlayerGui")
local lines = {
	"================================================",
	"HOTBAR INVENTORY AUDIT (fallback — Main belum load)",
	"userId=" .. tostring(player.UserId),
	"hotbarEnabled=" .. tostring(Config.FeatureFlags.HotbarEnabled),
	"hasPlayerGui=" .. tostring(playerGui ~= nil),
}

if playerGui then
	for _, name in ipairs(Config.Hotbar.GUI_NAMES) do
		local g = playerGui:FindFirstChild(name) or playerGui:FindFirstChild(name, true)
		lines[#lines + 1] = ("gui_%s=%s"):format(name, tostring(g ~= nil))
	end
	lines[#lines + 1] = "backpackGui=" .. tostring(playerGui:FindFirstChild(Config.Backpack.GUI_NAME) ~= nil)
	lines[#lines + 1] = "stickerGui=" .. tostring(playerGui:FindFirstChild(Config.Sticker.GUI_NAME) ~= nil)
end

lines[#lines + 1] = "backpackToolCount=" .. tostring(countTools(player:FindFirstChild("Backpack")))
lines[#lines + 1] = "characterToolCount=" .. tostring(countTools(player.Character))
lines[#lines + 1] = "================================================"

for _, line in ipairs(lines) do
	warn(line)
end
