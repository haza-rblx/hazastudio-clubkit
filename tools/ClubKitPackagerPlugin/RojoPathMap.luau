--!nocheck
-- Map repo src/ paths to Roblox instances (mirrors default.project.json + Rojo naming).

local StarterPlayer = game:GetService("StarterPlayer")

local RojoPathMap = {}

export type ParsedPath = {
	repoPath: string,
	serviceKey: string,
	folderSegments: { string },
	instanceName: string,
	className: string,
}

local SERVICE_PREFIXES: { { prefix: string, key: string } } = {
	{ prefix = "src/StarterPlayerScripts/StarterPlayerScripts/", key = "StarterPlayerScripts" },
	{ prefix = "src/ReplicatedStorage/", key = "ReplicatedStorage" },
	{ prefix = "src/ReplicatedFirst/", key = "ReplicatedFirst" },
	{ prefix = "src/ServerScriptService/", key = "ServerScriptService" },
}

local function stripSuffix(fileName: string, suffix: string): string?
	if string.sub(fileName, -#suffix) == suffix then
		return string.sub(fileName, 1, #fileName - #suffix)
	end
	return nil
end

local function parseFileName(fileName: string): (string, string, boolean)
	if fileName == "init.luau" then
		return "init", "ModuleScript", true
	end
	if fileName == "init.server.luau" then
		return "init", "Script", true
	end
	if fileName == "init.client.luau" then
		return "init", "LocalScript", true
	end

	local base = stripSuffix(fileName, ".server.luau")
	if base then
		return base, "Script", false
	end

	base = stripSuffix(fileName, ".client.luau")
	if base then
		return base, "LocalScript", false
	end

	base = stripSuffix(fileName, ".local.luau")
	if base then
		return base, "LocalScript", false
	end

	base = stripSuffix(fileName, ".luau")
	if base then
		return base, "ModuleScript", false
	end

	error("Not a Luau source file: " .. fileName)
end

function RojoPathMap.parseRepoPath(repoPath: string): ParsedPath?
	repoPath = string.gsub(repoPath, "\\", "/")
	if string.sub(repoPath, 1, 1) == "/" then
		repoPath = string.sub(repoPath, 2)
	end

	local serviceKey: string? = nil
	local relative = ""
	for _, entry in SERVICE_PREFIXES do
		if string.sub(repoPath, 1, #entry.prefix) == entry.prefix then
			serviceKey = entry.key
			relative = string.sub(repoPath, #entry.prefix + 1)
			break
		end
	end
	if not serviceKey or relative == "" then
		return nil
	end

	local segments = string.split(relative, "/")
	local fileName = segments[#segments]
	if not fileName or not string.match(fileName, "%.luau$") then
		return nil
	end

	local instanceName, className, isInit = parseFileName(fileName)
	local folderSegments: { string } = {}

	if isInit then
		if #segments < 2 then
			return nil
		end
		instanceName = segments[#segments - 1]
		for i = 1, #segments - 2 do
			table.insert(folderSegments, segments[i])
		end
	else
		for i = 1, #segments - 1 do
			table.insert(folderSegments, segments[i])
		end
	end

	return {
		repoPath = repoPath,
		serviceKey = serviceKey,
		folderSegments = folderSegments,
		instanceName = instanceName,
		className = className,
	}
end

function RojoPathMap.repoPathToService(repoPath: string): string?
	local parsed = RojoPathMap.parseRepoPath(repoPath)
	return if parsed then parsed.serviceKey else nil
end

function RojoPathMap.getInstanceSegments(repoPath: string): (string?, { string }, string?, string?)
	local parsed = RojoPathMap.parseRepoPath(repoPath)
	if not parsed then
		return nil, {}, nil, nil
	end
	return parsed.serviceKey, parsed.folderSegments, parsed.instanceName, parsed.className
end

function RojoPathMap.getServiceRoot(serviceKey: string): Instance?
	if serviceKey == "StarterPlayerScripts" then
		return StarterPlayer:FindFirstChild("StarterPlayerScripts")
	end
	local ok, svc = pcall(function()
		return game:GetService(serviceKey)
	end)
	if ok and svc then
		return svc
	end
	return nil
end

function RojoPathMap.ensureInstanceChain(serviceRoot: Instance, folderSegments: { string }): Instance
	local parent = serviceRoot
	for _, name in folderSegments do
		local child = parent:FindFirstChild(name)
		if child and not child:IsA("Folder") then
			error(("Path conflict: %s is %s, expected Folder"):format(child:GetFullName(), child.ClassName))
		end
		if not child then
			child = Instance.new("Folder")
			child.Name = name
			child.Parent = parent
		end
		parent = child
	end
	return parent
end

local function createScript(className: string): LuaSourceContainer
	if className == "Script" then
		return Instance.new("Script")
	elseif className == "LocalScript" then
		return Instance.new("LocalScript")
	end
	return Instance.new("ModuleScript")
end

function RojoPathMap.findOrCreateScriptInstance(
	serviceRoot: Instance,
	folderSegments: { string },
	instanceName: string,
	className: string
): LuaSourceContainer
	local parent = RojoPathMap.ensureInstanceChain(serviceRoot, folderSegments)
	local existing = parent:FindFirstChild(instanceName)

	if existing and existing:IsA("LuaSourceContainer") then
		if existing.ClassName ~= className then
			warn(
				("[RojoPathMap] Replacing %s (%s) with %s"):format(
					existing:GetFullName(),
					existing.ClassName,
					className
				)
			)
			existing:Destroy()
			existing = nil
		end
	end

	if existing and existing:IsA("LuaSourceContainer") then
		return existing
	end

	if existing then
		error(("Path conflict: %s is %s, expected script"):format(existing:GetFullName(), existing.ClassName))
	end

	local scriptInst = createScript(className)
	scriptInst.Name = instanceName
	scriptInst.Parent = parent
	return scriptInst
end

return RojoPathMap
