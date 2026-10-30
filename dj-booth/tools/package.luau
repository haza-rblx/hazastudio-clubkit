--!nocheck
-- Packages the three install pieces into the djX download template (docs/plans/djx-stamping.md).
--   lune run tools/package     (run from dj-booth/, after the rojo builds have written build/*.rbxm)
-- Reads build/shared.rbxm, build/server.rbxm, build/client.rbxm (each one root CosmicDJ) and writes
-- build/djx-template.rbxm: a root Folder "djX" with ReplicatedStorage / ServerScriptService /
-- StarterPlayerScripts folders, each holding its CosmicDJ piece. The buyer moves each CosmicDJ into
-- the service its folder names. The licence server stamps this template per download.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local BUILD = "build/"

local function loadPiece(name)
	local roots = roblox.deserializeModel(fs.readFile(BUILD .. name .. ".rbxm"))
	if #roots ~= 1 or roots[1].Name ~= "CosmicDJ" then
		error(name .. ".rbxm must hold exactly one root CosmicDJ")
	end
	return roots[1]
end

local function newFolder(name, parent)
	local folder = roblox.Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local shared = loadPiece("shared")
local server = loadPiece("server")
local client = loadPiece("client")

-- The server piece must carry exactly one Stamp module, and it must still be the template.
local stamps = {}
for _, descendant in server:GetDescendants() do
	if descendant.Name == "Stamp" and descendant:IsA("ModuleScript") then
		table.insert(stamps, descendant)
	end
end
if #stamps ~= 1 then
	error("expected exactly one ModuleScript named Stamp in server.rbxm, found " .. #stamps)
end
if not string.find(stamps[1].Source, "TEMPLATE", 1, true) then
	error("server.rbxm Stamp is not the TEMPLATE placeholder")
end

local djX = roblox.Instance.new("Folder")
djX.Name = "djX"

shared.Parent = newFolder("ReplicatedStorage", djX)
server.Parent = newFolder("ServerScriptService", djX)
client.Parent = newFolder("StarterPlayerScripts", djX)

local bytes = roblox.serializeModel({ djX })
fs.writeFile(BUILD .. "djx-template.rbxm", bytes)

print(("djx-template.rbxm: %d bytes (%d Stamp, from server.rbxm)"):format(#bytes, #stamps))
