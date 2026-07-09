--!strict
-- Shared/Utils/AssetHealthReporter.luau
-- Small helper to record asset-load failures and dedupe.

local Logger = require(script.Parent.Logger)

type AssetReport = {
	assetType: string,
	assetName: string?,
	assetId: string?,
	sourcePath: string,
	context: string,
	error: string,
	extra: { [string]: any }?,
	count: number,
	firstSeenAt: number,
	lastSeenAt: number,
}

export type AssetReporter = {
	recordInstanceFailure: (
		self: AssetReporter,
		instance: Instance,
		context: string,
		errorValue: any,
		extra: { [string]: any }?
	) -> AssetReport,
	recordSourceFailure: (
		self: AssetReporter,
		assetType: string,
		sourcePath: string,
		assetId: string?,
		context: string,
		errorValue: any,
		extra: { [string]: any }?
	) -> AssetReport,
	getReports: (self: AssetReporter) -> { AssetReport },
	clear: (self: AssetReporter) -> (),
}

type AssetReporterImpl = AssetReporter & {
	_logger: any,
	_reports: { AssetReport },
	_reportIndex: { [string]: AssetReport },
}

local function normalizeAssetId(assetId: any): string?
	if type(assetId) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(assetId, "^%s*(.-)%s*$", "%1")
	if trimmed == "" or trimmed == "rbxassetid://0" then
		return nil
	end

	return trimmed
end

local function cloneExtra(extra: { [string]: any }?): { [string]: any }?
	if type(extra) ~= "table" then
		return nil
	end

	local copy = {}
	for key, value in pairs(extra) do
		copy[key] = value
	end

	return copy
end

local function safeFullName(instance: Instance): string
	local ok, result = pcall(function()
		return instance:GetFullName()
	end)
	if ok and type(result) == "string" and result ~= "" then
		return result
	end

	return instance.Name
end

local function extractAssetId(instance: Instance): string?
	local ok, value = pcall(function()
		if instance:IsA("Animation") then
			return instance.AnimationId
		end
		if instance:IsA("Sound") then
			return instance.SoundId
		end
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			return (instance :: any).Image
		end
		if instance:IsA("Decal") then
			return instance.Texture
		end
		if instance:IsA("Texture") then
			return instance.Texture
		end
		if instance:IsA("MeshPart") then
			return instance.TextureID
		end
		if instance:IsA("SpecialMesh") then
			return instance.TextureId
		end
		if instance:IsA("ParticleEmitter") then
			return instance.Texture
		end
		if instance:IsA("Beam") or instance:IsA("Trail") then
			return instance.Texture
		end
		if instance:IsA("SurfaceAppearance") then
			return instance.ColorMap
		end
			return ""
		end)

	if ok then
		return normalizeAssetId(value)
	end

	return nil
end

local function buildKey(report: AssetReport): string
	return table.concat({
		report.assetType,
		report.sourcePath,
		report.assetId or "",
		report.context,
		report.error,
	}, "|")
end

local function cloneReport(report: AssetReport): AssetReport
	return {
		assetType = report.assetType,
		assetName = report.assetName,
		assetId = report.assetId,
		sourcePath = report.sourcePath,
		context = report.context,
		error = report.error,
		extra = cloneExtra(report.extra),
		count = report.count,
		firstSeenAt = report.firstSeenAt,
		lastSeenAt = report.lastSeenAt,
	}
end

local AssetHealthReporter = {}
AssetHealthReporter.__index = AssetHealthReporter

function AssetHealthReporter.new(logger: any?): AssetReporter
	local self = setmetatable({
		_logger = logger or Logger.new("AssetHealthReporter"),
		_reports = {} :: { AssetReport },
		_reportIndex = {} :: { [string]: AssetReport },
	}, AssetHealthReporter) :: any
	return self :: any
end

function AssetHealthReporter:_record(report: AssetReport): AssetReport
	local reporter = self :: AssetReporterImpl
	local now = os.time()
	report.firstSeenAt = now
	report.lastSeenAt = now
	report.count = 1

	local key = buildKey(report)
	local existing: AssetReport? = reporter._reportIndex[key]
	if existing then
		existing.count += 1
		existing.lastSeenAt = now
		return existing
	end

	reporter._reportIndex[key] = report
	table.insert(reporter._reports, report)

	reporter._logger:warn("Asset load failed", {
		assetType = report.assetType,
		assetName = report.assetName,
		assetId = report.assetId,
		sourcePath = report.sourcePath,
		context = report.context,
		error = report.error,
		count = report.count,
		extra = report.extra,
	})

	return report
end

function AssetHealthReporter:recordInstanceFailure(
	instance: Instance,
	context: string,
	errorValue: any,
	extra: { [string]: any }?
): AssetReport
	local report: AssetReport = {
		assetType = instance.ClassName,
		assetName = instance.Name,
		assetId = extractAssetId(instance),
		sourcePath = safeFullName(instance),
		context = context,
		error = tostring(errorValue),
		extra = cloneExtra(extra),
		count = 0,
		firstSeenAt = 0,
		lastSeenAt = 0,
	}

	return self:_record(report)
end

function AssetHealthReporter:recordSourceFailure(
	assetType: string,
	sourcePath: string,
	assetId: string?,
	context: string,
	errorValue: any,
	extra: { [string]: any }?
): AssetReport
	local report: AssetReport = {
		assetType = assetType,
		assetName = nil,
		assetId = normalizeAssetId(assetId),
		sourcePath = sourcePath,
		context = context,
		error = tostring(errorValue),
		extra = cloneExtra(extra),
		count = 0,
		firstSeenAt = 0,
		lastSeenAt = 0,
	}

	return self:_record(report)
end

function AssetHealthReporter:getReports(): { AssetReport }
	local results = table.create(#self._reports)
	for index, report in ipairs(self._reports) do
		results[index] = cloneReport(report)
	end
	return results
end

function AssetHealthReporter:clear()
	self._reports = {}
	self._reportIndex = {}
end

return AssetHealthReporter
