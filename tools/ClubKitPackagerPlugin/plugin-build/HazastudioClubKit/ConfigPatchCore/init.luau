--!nocheck
--[[
  After Update Engine: additively patch buyer ClubKitConfig Source.
  - Insert missing Features keys into the Features block
  - Append entirely missing top-level sections before `return`
  Never overwrites existing buyer values or comments on kept lines.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigPatchCore = {}

export type PatchReport = {
	added: { string },
	skipped: { string },
	error: string?,
	message: string,
}

local TOP_LEVEL_SECTIONS = {
	"Branding",
	"Group",
	"AdminUserIds",
	"TopSpenders",
	"GameDataApi",
	"Donation",
	"Carry",
	"Loading",
	"Shop",
	"PaidBroadcast",
	"Membership",
	"RoleCategories",
	"SpenderRoles",
	"SystemRoles",
	"LegacyAliases",
	"CommandAliases",
	"JoinCommunity",
	"Features",
}

local function findSchemaModule(): ModuleScript?
	local kit = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKit")
	local shared = kit and kit:FindFirstChild("Shared")
	local configFolder = shared and shared:FindFirstChild("Config")
	local schema = configFolder and configFolder:FindFirstChild("ClubKitConfigSchema")
	if schema and schema:IsA("ModuleScript") then
		return schema
	end
	return nil
end

local function findBuyerConfigModule(): ModuleScript?
	local folder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKitConfig")
	local mod = folder and folder:FindFirstChild("ClubKitConfig")
	if mod and mod:IsA("ModuleScript") then
		return mod
	end
	return nil
end

local function serializeValue(value: any, indent: number): string
	local pad = string.rep("\t", indent)
	local valueType = typeof(value)
	if value == nil then
		return "nil"
	elseif valueType == "boolean" then
		return if value then "true" else "false"
	elseif valueType == "number" then
		if value == math.huge then
			return "math.huge"
		elseif value ~= value then
			return "0/0"
		end
		return tostring(value)
	elseif valueType == "string" then
		return string.format("%q", value)
	elseif valueType == "Vector3" then
		return ("Vector3.new(%s, %s, %s)"):format(tostring(value.X), tostring(value.Y), tostring(value.Z))
	elseif valueType == "table" then
		local isArray = true
		local count = 0
		for key in pairs(value) do
			count += 1
			if type(key) ~= "number" then
				isArray = false
			end
		end
		if count == 0 then
			return "{}"
		end
		local parts = {}
		if isArray then
			for i = 1, #value do
				table.insert(parts, serializeValue(value[i], indent + 1))
			end
			return "{ " .. table.concat(parts, ", ") .. " }"
		end
		local keys = {}
		for key in pairs(value) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, key in ipairs(keys) do
			local keyLit = if type(key) == "string" and string.match(key, "^[%a_][%w_]*$")
				then key
				else ("[%s]"):format(serializeValue(key, 0))
			table.insert(parts, ("%s%s = %s,"):format(pad .. "\t", keyLit, serializeValue(value[key], indent + 1)))
		end
		return "{\n" .. table.concat(parts, "\n") .. "\n" .. pad .. "}"
	end
	return "nil"
end

local function findFeaturesBlockRange(source: string): (number?, number?)
	local startPat = "ClubKitConfig%.Features%s*=%s*%{"
	local startAt, openBrace = string.find(source, startPat)
	if not startAt or not openBrace then
		return nil, nil
	end
	local depth = 0
	local i = openBrace
	while i <= #source do
		local ch = string.sub(source, i, i)
		if ch == "{" then
			depth += 1
		elseif ch == "}" then
			depth -= 1
			if depth == 0 then
				return openBrace, i
			end
		end
		i += 1
	end
	return nil, nil
end

local function featureKeyExistsInBlock(blockBody: string, key: string): boolean
	local pattern = "%f[%w_]" .. key .. "%f[^%w_]%s*="
	return string.find(blockBody, pattern) ~= nil
end

local function insertFeaturesKeys(source: string, missing: { { key: string, value: any } }): (string, { string })
	local added: { string } = {}
	local openBrace, closeBrace = findFeaturesBlockRange(source)
	if not openBrace or not closeBrace then
		return source, added
	end
	local blockBody = string.sub(source, openBrace + 1, closeBrace - 1)
	local lines = {}
	for _, entry in ipairs(missing) do
		if not featureKeyExistsInBlock(blockBody, entry.key) then
			table.insert(lines, ("\t%s = %s,"):format(entry.key, serializeValue(entry.value, 1)))
			table.insert(added, "Features." .. entry.key)
		end
	end
	if #lines == 0 then
		return source, added
	end
	local insertion = "\n\t-- Added by ClubKit Update Engine (fill-forward)\n" .. table.concat(lines, "\n") .. "\n"
	local before = string.sub(source, 1, closeBrace - 1)
	local after = string.sub(source, closeBrace)
	-- Trim trailing whitespace before closing brace so insertion sits cleanly.
	before = string.gsub(before, "%s*$", "")
	return before .. insertion .. after, added
end

local function sectionExistsInSource(source: string, section: string): boolean
	local pattern = "ClubKitConfig%." .. section .. "%s*="
	return string.find(source, pattern) ~= nil
end

local function appendTopLevelSections(source: string, sections: { { name: string, value: any } }): (string, { string })
	local added: { string } = {}
	if #sections == 0 then
		return source, added
	end

	local chunks = {
		"",
		"-- =============================================================================",
		"-- ADDED BY CLUBKIT UPDATE ENGINE (fill-forward missing sections)",
		"-- =============================================================================",
	}
	for _, entry in ipairs(sections) do
		if not sectionExistsInSource(source, entry.name) then
			table.insert(chunks, ("ClubKitConfig.%s = %s"):format(entry.name, serializeValue(entry.value, 0)))
			table.insert(chunks, "")
			table.insert(added, entry.name)
		end
	end
	if #added == 0 then
		return source, added
	end

	local returnPos = string.find(source, "\nreturn%s+ClubKitConfig")
	if not returnPos then
		returnPos = string.find(source, "return%s+ClubKitConfig")
	end
	if not returnPos then
		return source .. "\n" .. table.concat(chunks, "\n"), added
	end

	local before = string.sub(source, 1, returnPos - 1)
	local after = string.sub(source, returnPos)
	before = string.gsub(before, "%s*$", "\n")
	return before .. table.concat(chunks, "\n") .. "\n" .. after, added
end

function ConfigPatchCore.collectMissing(schemaDefaults: any, buyer: any): ( { { key: string, value: any } }, { { name: string, value: any } } )
	local missingFeatures: { { key: string, value: any } } = {}
	local missingSections: { { name: string, value: any } } = {}

	if type(schemaDefaults) ~= "table" or type(buyer) ~= "table" then
		return missingFeatures, missingSections
	end

	local schemaFeatures = schemaDefaults.Features
	local buyerFeatures = buyer.Features
	if type(schemaFeatures) == "table" then
		if type(buyerFeatures) ~= "table" then
			table.insert(missingSections, { name = "Features", value = schemaFeatures })
		else
			local keys = {}
			for key in pairs(schemaFeatures) do
				table.insert(keys, key)
			end
			table.sort(keys)
			for _, key in ipairs(keys) do
				if buyerFeatures[key] == nil then
					table.insert(missingFeatures, { key = key, value = schemaFeatures[key] })
				end
			end
		end
	end

	for _, section in ipairs(TOP_LEVEL_SECTIONS) do
		if section == "Features" then
			continue
		end
		if schemaDefaults[section] ~= nil and buyer[section] == nil then
			table.insert(missingSections, { name = section, value = schemaDefaults[section] })
		end
	end

	return missingFeatures, missingSections
end

function ConfigPatchCore.patchBuyerConfig(): PatchReport
	local report: PatchReport = {
		added = {},
		skipped = {},
		message = "Config patch: no changes",
	}

	local schemaMod = findSchemaModule()
	if not schemaMod then
		report.error = "ClubKitConfigSchema ModuleScript not found after engine update"
		report.message = "Config patch skipped: schema missing"
		return report
	end

	local buyerMod = findBuyerConfigModule()
	if not buyerMod then
		report.error = "Buyer ClubKitConfig ModuleScript not found"
		report.message = "Config patch skipped: ClubKitConfig missing"
		return report
	end

	local schemaOk, schemaModule = pcall(require, schemaMod)
	if not schemaOk or type(schemaModule) ~= "table" then
		report.error = "Failed to require ClubKitConfigSchema: " .. tostring(schemaModule)
		report.message = "Config patch skipped: schema require failed"
		return report
	end

	local buyerOk, buyerTable = pcall(require, buyerMod)
	if not buyerOk or type(buyerTable) ~= "table" then
		report.error = "Failed to require ClubKitConfig: " .. tostring(buyerTable)
		report.message = "Config patch skipped: buyer require failed"
		return report
	end

	local defaults = schemaModule.defaults
	if type(defaults) ~= "table" then
		report.error = "ClubKitConfigSchema.defaults missing"
		report.message = "Config patch skipped: bad schema"
		return report
	end

	local missingFeatures, missingSections = ConfigPatchCore.collectMissing(defaults, buyerTable)
	if #missingFeatures == 0 and #missingSections == 0 then
		report.message = "Config patch: added 0 keys (already complete)"
		return report
	end

	local source = buyerMod.Source
	if type(source) ~= "string" or source == "" then
		report.error = "ClubKitConfig.Source empty or unreadable"
		report.message = "Config patch skipped: empty Source"
		return report
	end

	local addedAll: { string } = {}
	local newSource = source

	if #missingFeatures > 0 and type(buyerTable.Features) == "table" then
		local inserted, added = insertFeaturesKeys(newSource, missingFeatures)
		newSource = inserted
		for _, path in ipairs(added) do
			table.insert(addedAll, path)
		end
	elseif #missingFeatures > 0 and type(buyerTable.Features) ~= "table" then
		-- Features section missing entirely — handled via missingSections.
		table.insert(missingSections, 1, { name = "Features", value = defaults.Features })
	end

	if #missingSections > 0 then
		local appended, added = appendTopLevelSections(newSource, missingSections)
		newSource = appended
		for _, path in ipairs(added) do
			table.insert(addedAll, path)
		end
	end

	if newSource == source or #addedAll == 0 then
		report.message = "Config patch: added 0 keys (source unchanged)"
		return report
	end

	local setOk, setErr = pcall(function()
		buyerMod.Source = newSource
	end)
	if not setOk then
		report.error = "Failed to set ClubKitConfig.Source: " .. tostring(setErr)
		report.message = "Config patch failed writing Source"
		return report
	end

	report.added = addedAll
	report.message = ("Config patch: added %d key(s): %s"):format(#addedAll, table.concat(addedAll, ", "))
	return report
end

return ConfigPatchCore
