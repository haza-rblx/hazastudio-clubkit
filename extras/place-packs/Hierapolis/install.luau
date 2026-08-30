--!nocheck
--[[
  Hierapolis add-on — one-time INSTALL (Studio Edit, Command Bar or MCP execute_luau):
    loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8798/repo/extras/place-packs/Hierapolis/install.luau"))()

  This does NOT toggle anything. It only puts the pack's pieces in the place:
    1. ReplicatedStorage.Hazastudio_ClubKitConfig.HierapolisCustom  (overlay ModuleScript, source from repo)
    2. ServerStorage.Tools/<role folders>                             (cloned from OWNER / STAFF / LEAD DANCE if absent)
    3. ReplicatedFirst.CinematicLoading                               (LocalScript source from the CinematicLoading pack)
  The switch is ClubKitConfig.Features.HierapolisCustom = true | false (plugin Config panel or the file).
  Re-running is safe: it refreshes the module / script sources and skips folders that exist.
]]
local HttpService = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8798/repo/"
local function fetch(p) return HttpService:GetAsync(BASE .. p) end
local report = {}

-- 1. overlay module (buyer-owned folder)
local cfgFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Hazastudio_ClubKitConfig")
assert(cfgFolder, "Hazastudio_ClubKitConfig missing — install the kit first")
local overlay = cfgFolder:FindFirstChild("HierapolisCustom")
if not overlay then
	overlay = Instance.new("ModuleScript")
	overlay.Name = "HierapolisCustom"
	overlay.Parent = cfgFolder
	table.insert(report, "overlay: created HierapolisCustom")
end
overlay.Source = fetch("extras/place-packs/Hierapolis/HierapolisCustom.luau")
table.insert(report, "overlay: source refreshed")

-- 2. tool folders
local tools = game:GetService("ServerStorage"):FindFirstChild("Tools")
if tools then
	for _, p in ipairs({
		{ name = "CO-OWNER", from = "OWNER" },
		{ name = "THE EMPEROR", from = "STAFF" },
		{ name = "THE ECHOBORN", from = "STAFF" },
		{ name = "THE MINISTER", from = "STAFF" },
		{ name = "THE SENATOR", from = "LEAD DANCE" },
	}) do
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

-- 3. loading pack (gates itself on the flag at runtime; stays enabled)
local rf = game:GetService("ReplicatedFirst")
local cl = rf:FindFirstChild("CinematicLoading")
if not cl then
	cl = Instance.new("LocalScript")
	cl.Name = "CinematicLoading"
	cl.Parent = rf
end
cl.Source = fetch("extras/place-packs/CinematicLoading/bridge/CinematicLoading.client.luau")
cl.Disabled = false
table.insert(report, "loading: CinematicLoading installed, LoadingUI=" .. tostring(cl:FindFirstChild("LoadingUI") ~= nil))

local flag = cfgFolder.ClubKitConfig.Source:match("HierapolisCustom%s*=%s*(%a+)")
table.insert(report, "flag: Features.HierapolisCustom = " .. tostring(flag) .. (flag == nil and " (key absent — run Update Engine / add it)" or ""))
print("[Hierapolis add-on] INSTALLED\n" .. table.concat(report, "\n"))
return table.concat(report, "\n")
