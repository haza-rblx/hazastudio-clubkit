--!nocheck
--[[
  Carry KeyframeSequence scan / CreateAssetAsync upload / ClubKitConfig patch.
  Used by ClubKitPanel Tools (inline). Requires local plugin + CreateAssetAsync beta.
]]

local AssetService = game:GetService("AssetService")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local CarryUploadCore = {}

local STYLE_ALIASES: { [string]: string } = {
	Pasakal = "Choke",
	PASAKAL = "Choke",
	Chokehold = "Choke",
}

local KNOWN_STYLES = {
	Piggyback = true,
	Bridal = true,
	Hug = true,
	Tandem = true,
	Fireman = true,
	Choke = true,
}

export type Planned = {
	seq: KeyframeSequence,
	style: string,
	role: string,
}

export type PlanResult = {
	planned: { Planned },
	warnings: { string },
	sourceLabel: string,
}

export type UploadOpts = {
	dryRun: boolean?,
	groupId: number?,
	onLog: ((text: string, color: Color3?) -> ())?,
}

export type UploadReport = {
	okCount: number,
	failCount: number,
	idsByStyle: { [string]: { carrier: number?, carried: number? } },
	patchLog: { string },
	aborted: boolean?,
	abortReason: string?,
}

local function normalizeStyleToken(raw: string): string
	local cleaned = (raw:gsub("^%s+", ""):gsub("%s+$", ""))
	local alias = STYLE_ALIASES[cleaned] or STYLE_ALIASES[string.upper(cleaned)]
	if alias then
		return alias
	end
	for styleName in pairs(KNOWN_STYLES) do
		if string.lower(styleName) == string.lower(cleaned) then
			return styleName
		end
	end
	return cleaned
end

local function parseKeyframeName(name: string): (string?, string?, string?)
	local stylePart, roleDigit = name:match("^(.+)%s*([12])%s*$")
	if not stylePart or not roleDigit then
		return nil, nil, "name must end with 1 (carrier) or 2 (carried)"
	end
	stylePart = stylePart:gsub("%s+$", "")
	local style = normalizeStyleToken(stylePart)
	local role = if roleDigit == "1" then "carrier" else "carried"
	return style, role, nil
end

local function findCarryFolder(): Folder?
	local carry = ReplicatedStorage:FindFirstChild("Carry")
	if carry and carry:IsA("Folder") then
		return carry
	end
	return nil
end

local function findConfigModule(): ModuleScript?
	local folder = ReplicatedStorage:FindFirstChild("Hazastudio_ClubKitConfig")
	if not folder then
		return nil
	end
	local mod = folder:FindFirstChild("ClubKitConfig")
	if mod and mod:IsA("ModuleScript") then
		return mod
	end
	return nil
end

local function collectKeyframeSequences(root: Instance): { KeyframeSequence }
	local list = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("KeyframeSequence") then
			table.insert(list, d)
		end
	end
	if root:IsA("KeyframeSequence") then
		table.insert(list, root)
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function patchAnimationsInSource(source: string, style: string, carrierId: number?, carriedId: number?): (string, boolean)
	local ok = false
	local result = source:gsub("(" .. style .. "%s*=%s*%b{})", function(block: string)
		local newBlock, n = block:gsub(
			"(animations%s*=%s*{%s*carrier%s*=%s*)(%d+)(,%s*carried%s*=%s*)(%d+)(%s*})",
			function(pre, _c, mid, _d, post)
				local c = if carrierId then tostring(carrierId) else _c
				local d = if carriedId then tostring(carriedId) else _d
				ok = true
				return pre .. c .. mid .. d .. post
			end
		)
		if n == 0 then
			newBlock, n = block:gsub(
				"(animations%s*=%s*{%s*carried%s*=%s*)(%d+)(,%s*carrier%s*=%s*)(%d+)(%s*})",
				function(_pre, _d, _mid, _c, _post)
					local c = if carrierId then tostring(carrierId) else _c
					local d = if carriedId then tostring(carriedId) else _d
					ok = true
					return string.format("animations = { carrier = %s, carried = %s }", c, d)
				end
			)
		end
		return if n > 0 then newBlock else block
	end)
	return result, ok
end

local function applyConfigPatch(mod: ModuleScript, idsByStyle: { [string]: { carrier: number?, carried: number? } }): { string }
	local log = {}
	local source = mod.Source
	local changed = false
	for style, ids in pairs(idsByStyle) do
		if ids.carrier or ids.carried then
			local nextSource, ok = patchAnimationsInSource(source, style, ids.carrier, ids.carried)
			if ok then
				source = nextSource
				changed = true
				table.insert(
					log,
					string.format(
						"patched %s → carrier=%s carried=%s",
						style,
						tostring(ids.carrier or "?"),
						tostring(ids.carried or "?")
					)
				)
			else
				table.insert(log, string.format("WARN: could not find animations block for style %s", style))
			end
		end
	end
	if changed then
		mod.Source = source
		table.insert(log, "ClubKitConfig Source updated in place.")
		table.insert(log, "If Rojo syncs this file, also paste IDs into repo ClubKitConfig.luau.")
	end
	return log
end

local function uploadKeyframe(seq: KeyframeSequence, groupId: number?): (boolean, number?, string?)
	local params: { [string]: any } = {
		Name = seq.Name,
		Description = "ClubKit Carry — uploaded via Club Kit plugin",
		CreatorType = if groupId then Enum.AssetCreatorType.Group else Enum.AssetCreatorType.User,
	}
	if groupId then
		params.CreatorId = groupId
	end

	local ok, createResult, assetId = pcall(function()
		return AssetService:CreateAssetAsync(seq, Enum.AssetType.Animation, params)
	end)
	if not ok then
		return false, nil, tostring(createResult)
	end
	if createResult ~= Enum.CreateAssetResult.Success then
		return false, nil, tostring(createResult)
	end
	return true, assetId :: number, nil
end

function CarryUploadCore.findConfigModule(): ModuleScript?
	return findConfigModule()
end

function CarryUploadCore.planUploads(): PlanResult
	local warnings = {}
	local planned: { Planned } = {}
	local sourceLabel = "Source: —"

	local selected = Selection:Get()
	local sequences: { KeyframeSequence } = {}
	local usedSelection = false
	for _, obj in ipairs(selected) do
		if obj:IsA("KeyframeSequence") then
			table.insert(sequences, obj)
			usedSelection = true
		elseif obj:IsA("Folder") or obj:IsA("Model") then
			for _, kfs in ipairs(collectKeyframeSequences(obj)) do
				table.insert(sequences, kfs)
			end
			usedSelection = true
		end
	end

	if #sequences == 0 then
		local carry = findCarryFolder()
		if not carry then
			table.insert(warnings, "No Selection and ReplicatedStorage.Carry folder missing.")
			return { planned = planned, warnings = warnings, sourceLabel = sourceLabel }
		end
		sequences = collectKeyframeSequences(carry)
		sourceLabel = "Source: ReplicatedStorage.Carry (" .. #sequences .. " clips)"
	else
		sourceLabel = if usedSelection
			then ("Source: Selection (" .. #sequences .. " clips)")
			else sourceLabel
	end

	for _, seq in ipairs(sequences) do
		local styleAttr = seq:GetAttribute("CarryStyle")
		local roleAttr = seq:GetAttribute("CarryRole")
		local style: string?
		local role: string?
		local err: string?

		if type(styleAttr) == "string" and type(roleAttr) == "string" then
			style = normalizeStyleToken(styleAttr)
			role = if string.lower(roleAttr) == "carried" then "carried" else "carrier"
		else
			style, role, err = parseKeyframeName(seq.Name)
		end

		if err or not style or not role then
			table.insert(warnings, string.format("skip '%s': %s", seq.Name, err or "parse failed"))
			continue
		end
		if not KNOWN_STYLES[style] then
			table.insert(
				warnings,
				string.format("skip '%s': unknown style '%s' (add STYLE_ALIASES or rename)", seq.Name, style)
			)
			continue
		end
		table.insert(planned, { seq = seq, style = style, role = role })
	end

	return { planned = planned, warnings = warnings, sourceLabel = sourceLabel }
end

function CarryUploadCore.formatPlanLines(result: PlanResult): { { text: string, color: Color3? } }
	local lines = {}
	local muted = Color3.fromRGB(120, 180, 255)
	local warn = Color3.fromRGB(240, 180, 60)
	local ok = Color3.fromRGB(100, 210, 130)
	local err = Color3.fromRGB(220, 80, 80)

	table.insert(lines, { text = "── Scan ──", color = muted })
	for _, w in ipairs(result.warnings) do
		table.insert(lines, { text = "! " .. w, color = warn })
	end
	if #result.planned == 0 then
		table.insert(lines, { text = "Nothing to upload.", color = err })
		return lines
	end

	local byStyle: { [string]: { carrier: string?, carried: string? } } = {}
	for _, p in ipairs(result.planned) do
		byStyle[p.style] = byStyle[p.style] or {}
		byStyle[p.style][p.role] = p.seq.Name
		table.insert(lines, { text = string.format("%s → %s.%s", p.seq.Name, p.style, p.role) })
	end

	table.insert(lines, { text = "── Expected pairs ──", color = muted })
	for style, roles in pairs(byStyle) do
		local okPair = roles.carrier and roles.carried
		table.insert(lines, {
			text = string.format(
				"%s: carrier=%s carried=%s%s",
				style,
				roles.carrier or "MISSING",
				roles.carried or "MISSING",
				if okPair then "" else "  ← incomplete"
			),
			color = if okPair then ok else warn,
		})
	end

	local cfg = findConfigModule()
	table.insert(lines, {
		text = if cfg then "ClubKitConfig: found" else "ClubKitConfig: MISSING",
		color = if cfg then ok else err,
	})
	return lines
end

function CarryUploadCore.runUpload(planned: { Planned }, opts: UploadOpts): UploadReport
	local onLog = opts.onLog
	local function log(text: string, color: Color3?)
		if onLog then
			onLog(text, color)
		end
	end

	local report: UploadReport = {
		okCount = 0,
		failCount = 0,
		idsByStyle = {},
		patchLog = {},
	}

	if opts.dryRun then
		log("Dry run only — turn Dry run off to upload.", Color3.fromRGB(240, 180, 60))
		report.aborted = true
		report.abortReason = "dry_run"
		return report
	end

	if #planned == 0 then
		report.aborted = true
		report.abortReason = "empty"
		return report
	end

	local groupId = opts.groupId
	if groupId then
		local okInfo, info = pcall(function()
			return GroupService:GetGroupInfoAsync(groupId)
		end)
		if not okInfo then
			log("Group lookup failed.", Color3.fromRGB(220, 80, 80))
			report.aborted = true
			report.abortReason = "group"
			return report
		end
		log("Upload as group: " .. tostring(info.Name), Color3.fromRGB(160, 160, 160))
	end

	log("── Upload ──", Color3.fromRGB(120, 180, 255))
	for _, p in ipairs(planned) do
		local ok, assetId, err = uploadKeyframe(p.seq, groupId)
		if ok and assetId then
			report.idsByStyle[p.style] = report.idsByStyle[p.style] or {}
			report.idsByStyle[p.style][p.role] = assetId
			p.seq:SetAttribute("UploadedAnimationId", assetId)
			log(
				string.format("✔ %s → %d (%s.%s)", p.seq.Name, assetId, p.style, p.role),
				Color3.fromRGB(100, 210, 130)
			)
			report.okCount += 1
		else
			log(string.format("✖ %s — %s", p.seq.Name, tostring(err)), Color3.fromRGB(220, 80, 80))
			report.failCount += 1
		end
		task.wait(0.12)
	end

	log(
		string.format("Upload done: %d ok, %d failed", report.okCount, report.failCount),
		Color3.fromRGB(200, 200, 200)
	)

	local mod = findConfigModule()
	if mod then
		log("── Patch ClubKitConfig ──", Color3.fromRGB(120, 180, 255))
		report.patchLog = applyConfigPatch(mod, report.idsByStyle)
		for _, line in ipairs(report.patchLog) do
			log(line)
		end
	else
		log("Skip patch: ClubKitConfig module not found.", Color3.fromRGB(240, 180, 60))
	end

	log("── Paste into repo (if Rojo) ──", Color3.fromRGB(120, 180, 255))
	for style, ids in pairs(report.idsByStyle) do
		if ids.carrier and ids.carried then
			log(
				string.format(
					"%s: animations = { carrier = %d, carried = %d },",
					style,
					ids.carrier,
					ids.carried
				),
				Color3.fromRGB(180, 220, 255)
			)
		end
	end

	return report
end

return CarryUploadCore
