--!nocheck
--[[
  Hierapolis add-on — APPLY (toggle ON). Run in Studio Edit (Command Bar or MCP execute_luau):
    loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8798/repo/extras/place-packs/Hierapolis/apply.luau"))()
  (dev-serve.ps1 must be running; BASE below can point at a GitHub raw tag instead.)

  Idempotent. Does, in order:
    1. ClubKitConfig: Hierapolis role catalog (Leadership / DPC / Content), chip flags, aliases,
       Features.LoadingScreen = false                       → apply-config.luau
    2. ServerStorage.Tools: one folder per role (cloned from OWNER / STAFF / LEAD DANCE if absent)
    3. ReplicatedFirst.CinematicLoading: LocalScript source from the CinematicLoading pack, enabled
       (LoadingUI child must be inserted once from CinematicLoadingUI.rbxm — see README)
  Engine files are NOT touched; run the normal engine sync separately.
]]
local HttpService = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8798/repo/"
local function fetch(p) return HttpService:GetAsync(BASE .. p) end

local report = {}

-- 1. config
local applyConfig, err = loadstring(fetch("extras/place-packs/Hierapolis/apply-config.luau"), "=apply-config")
assert(applyConfig, err)
table.insert(report, "config: " .. tostring(applyConfig()))

-- 2. tool folders
local tools = game:GetService("ServerStorage"):FindFirstChild("Tools")
if tools then
	local plan = {
		{ name = "CO-OWNER", from = "OWNER" },
		{ name = "THE EMPEROR", from = "STAFF" },
		{ name = "THE ECHOBORN", from = "STAFF" },
		{ name = "THE MINISTER", from = "STAFF" },
		{ name = "THE SENATOR", from = "LEAD DANCE" },
	}
	for _, p in ipairs(plan) do
		if not tools:FindFirstChild(p.name) then
			local src = tools:FindFirstChild(p.from)
			local folder = src and src:Clone() or Instance.new("Folder")
			folder.Name = p.name
			folder.Parent = tools
			table.insert(report, "tools: created " .. p.name)
		end
	end
else
	table.insert(report, "tools: ServerStorage.Tools missing — insert HierapolisToolFolders.rbxm manually")
end

-- 3. loading pack
local rf = game:GetService("ReplicatedFirst")
local cl = rf:FindFirstChild("CinematicLoading")
if not cl then
	cl = Instance.new("LocalScript")
	cl.Name = "CinematicLoading"
	cl.Parent = rf
end
cl.Source = fetch("extras/place-packs/CinematicLoading/bridge/CinematicLoading.client.luau")
cl.Disabled = false
table.insert(report, "loading: CinematicLoading enabled, LoadingUI=" .. tostring(cl:FindFirstChild("LoadingUI") ~= nil))

print("[Hierapolis add-on] APPLIED\n" .. table.concat(report, "\n"))
return table.concat(report, "\n")
