--!strict

local Types = require(script.Parent.Types)

type SettingsStoredData = Types.SettingsStoredData
type SettingsSessionData = Types.SettingsSessionData
type SettingsPayload = Types.SettingsPayload

local GraphicsQuality = require(script.Parent.Parent.Utils.GraphicsQuality)

local SettingsDomain = {}

-- Schema for music volume product default (old kit default was 50%).
SettingsDomain.MUSIC_VOLUME_BASE_SCHEMA = 1

local DEFAULT_STORED: SettingsStoredData = {
	cameraFocus = "Torso",
	fov = 70,
	smooth = "Medium",
	uiScaleMode = "Normal",
	eyeComfortMode = false,
	colorBrightness = 50,
	colorContrast = 50,
	colorSaturation = 50,
	depthOfField = 0,
	playerEffects = true,
	hideAllParticles = false,
	textures = 2,
	musicVolume = 100,
	_musicVolBase = SettingsDomain.MUSIC_VOLUME_BASE_SCHEMA,
	graphicsPreset = "Balanced",
	shadowQuality = "Balanced",
	overheadDistance = "Medium",
	overheadLayerVisible = {
		["SpecialTitle"] = true,
		["BadgeGroup"] = true,
		["Level"] = true,
		["SpecialRank"] = true,
		["SpecialStatus"] = true,
		["TopSpender"] = true,
		["TopDonate"] = true,
		["Rank"] = true,
		["DisplayName"] = true,
		["CoupleName"] = false,
	},
	overheadBadgeVisible = {
		["OwnerCoOwner"] = true,
		["Developer"] = true,
		["Admin"] = true,
		["Member"] = true,
		["VIP"] = true,
		["VVIP"] = true,
		["Elite"] = true,
		["Streak"] = true,
		["LikeCounter"] = true,
		["Community"] = true,
	},
	chatBubbleVisibility = "All",
	hideAdminAnnounce = false,
	hideCoupleAnnounce = false,
	hideDonationAnnounce = false,
	hideDonationWorldEffect = false,
	hideDonationAura = false,
	hideDonatorHighlight = false,
	hideSystemAnnounce = false,
	graphicsOverrides = {},
	_version = GraphicsQuality.STORED_VERSION,
}

local DEFAULT_SESSION: SettingsSessionData = {
	overheadVisible = true,
	overheadLayerVisible = table.clone(DEFAULT_STORED.overheadLayerVisible),
	overheadBadgeVisible = table.clone(DEFAULT_STORED.overheadBadgeVisible),
	hideAllGui = false,
}

local function pickEnum<T>(value: any, allowed: { T }, fallback: T): T
	for _, item in ipairs(allowed) do
		if value == item then
			return item
		end
	end
	return fallback
end

local function pickBoolean(value: any, fallback: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

local function pickNumber(value: any, fallback: number, minValue: number?, maxValue: number?): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	local nextValue = value
	if minValue then
		nextValue = math.max(minValue, nextValue)
	end
	if maxValue then
		nextValue = math.min(maxValue, nextValue)
	end
	return nextValue
end

local function sanitizeMap(raw: any, defaults: { [string]: boolean }): { [string]: boolean }
	local result = table.clone(defaults)
	if type(raw) ~= "table" then
		return result
	end
	for key, defaultValue in pairs(defaults) do
		if type(raw[key]) == "boolean" then
			result[key] = raw[key]
		else
			result[key] = defaultValue
		end
	end
	return result
end

function SettingsDomain.defaultStoredData(): SettingsStoredData
	local stored = table.clone(DEFAULT_STORED)
	stored.overheadLayerVisible = table.clone(DEFAULT_STORED.overheadLayerVisible)
	stored.overheadBadgeVisible = table.clone(DEFAULT_STORED.overheadBadgeVisible)
	return stored
end

function SettingsDomain.defaultSessionData(): SettingsSessionData
	return {
		overheadVisible = DEFAULT_SESSION.overheadVisible,
		overheadLayerVisible = table.clone(DEFAULT_SESSION.overheadLayerVisible),
		overheadBadgeVisible = table.clone(DEFAULT_SESSION.overheadBadgeVisible),
		hideAllGui = DEFAULT_SESSION.hideAllGui,
	}
end

function SettingsDomain.sanitizeStored(raw: any): SettingsStoredData
	local base = SettingsDomain.defaultStoredData()
	if type(raw) ~= "table" then
		return base
	end
	local rawVersion = if type(raw._version) == "number" then raw._version else 0
	base.cameraFocus = pickEnum(raw.cameraFocus, { "Torso", "Head", "FullBody" }, base.cameraFocus)
	base.fov = pickNumber(raw.fov, base.fov, 60, 100)
	base.smooth = if raw.smooth == "Low"
		then "Medium"
		else pickEnum(raw.smooth, { "Off", "Medium", "High" }, base.smooth)
	base.uiScaleMode = pickEnum(raw.uiScaleMode, { "Small", "Normal", "Large" }, base.uiScaleMode)
	base.eyeComfortMode = pickBoolean(raw.eyeComfortMode, base.eyeComfortMode)
	base.colorBrightness = pickNumber(raw.colorBrightness, base.colorBrightness, 0, 100)
	base.colorContrast = pickNumber(raw.colorContrast, base.colorContrast, 0, 100)
	base.colorSaturation = pickNumber(raw.colorSaturation, base.colorSaturation, 0, 100)
	base.depthOfField = pickNumber(raw.depthOfField, base.depthOfField, 0, 3)
	base.playerEffects = pickBoolean(raw.playerEffects, base.playerEffects)
	base.hideAllParticles = pickBoolean(raw.hideAllParticles, base.hideAllParticles)
	base.textures = pickNumber(raw.textures, base.textures, 0, 2)
	base.musicVolume = pickNumber(raw.musicVolume, base.musicVolume, 0, 100)
	local musicVolBase = pickNumber(raw._musicVolBase, 0, 0, 999)
	if musicVolBase < SettingsDomain.MUSIC_VOLUME_BASE_SCHEMA then
		-- One-shot: remapped old kit default 50% → 100% for everyone still on it.
		if type(raw.musicVolume) ~= "number" or raw.musicVolume == 50 then
			base.musicVolume = 100
		end
		musicVolBase = SettingsDomain.MUSIC_VOLUME_BASE_SCHEMA
	end
	base._musicVolBase = musicVolBase
	base.graphicsPreset = if raw.graphicsPreset == "Ultra"
		then "High"
		else pickEnum(raw.graphicsPreset, { "Low", "Balanced", "High" }, base.graphicsPreset)
	base.shadowQuality = pickEnum(raw.shadowQuality, { "Off", "Balanced", "High" }, base.shadowQuality)
	base.overheadDistance = pickEnum(raw.overheadDistance, { "Near", "Medium", "Far" }, base.overheadDistance)
	base.overheadLayerVisible = sanitizeMap(raw.overheadLayerVisible, base.overheadLayerVisible)
	base.overheadBadgeVisible = sanitizeMap(raw.overheadBadgeVisible, base.overheadBadgeVisible)
	base.chatBubbleVisibility =
		pickEnum(raw.chatBubbleVisibility, { "All", "Nearby", "Off" }, base.chatBubbleVisibility)
	if rawVersion < 2 then
		base.cameraFocus = "Torso"
		base.chatBubbleVisibility = "All"
	end
	base.graphicsOverrides = GraphicsQuality.sanitizeOverrides(raw.graphicsOverrides)
	if rawVersion < GraphicsQuality.STORED_VERSION then
		base.graphicsOverrides = GraphicsQuality.clearOverrides()
	end
	base.hideAdminAnnounce = pickBoolean(raw.hideAdminAnnounce, base.hideAdminAnnounce)
	base.hideCoupleAnnounce = pickBoolean(raw.hideCoupleAnnounce, base.hideCoupleAnnounce)
	base.hideDonationAnnounce = pickBoolean(raw.hideDonationAnnounce, base.hideDonationAnnounce)
	base.hideDonationWorldEffect = pickBoolean(raw.hideDonationWorldEffect, base.hideDonationWorldEffect)
	base.hideDonationAura = pickBoolean(raw.hideDonationAura, base.hideDonationAura)
	base.hideDonatorHighlight = pickBoolean(raw.hideDonatorHighlight, base.hideDonatorHighlight)
	base.hideSystemAnnounce = pickBoolean(raw.hideSystemAnnounce, base.hideSystemAnnounce)
	base._version = math.max(base._version, pickNumber(raw._version, base._version, 1, 999))
	return base
end

function SettingsDomain.sanitizeSession(raw: any): SettingsSessionData
	local base = SettingsDomain.defaultSessionData()
	if type(raw) ~= "table" then
		return base
	end
	base.overheadVisible = pickBoolean(raw.overheadVisible, base.overheadVisible)
	base.overheadLayerVisible = sanitizeMap(raw.overheadLayerVisible, base.overheadLayerVisible)
	base.overheadBadgeVisible = sanitizeMap(raw.overheadBadgeVisible, base.overheadBadgeVisible)
	base.hideAllGui = pickBoolean(raw.hideAllGui, base.hideAllGui)
	return base
end

function SettingsDomain.mergeStoredPreservingSession(
	session: SettingsSessionData,
	stored: SettingsStoredData?
): SettingsPayload
	return SettingsDomain.merge(stored, session)
end

function SettingsDomain.merge(stored: SettingsStoredData?, session: SettingsSessionData?): SettingsPayload
	local storedData = SettingsDomain.sanitizeStored(stored or DEFAULT_STORED)
	local sessionData = SettingsDomain.sanitizeSession(session or DEFAULT_SESSION)
	return table.freeze({
		cameraFocus = storedData.cameraFocus,
		fov = storedData.fov,
		smooth = storedData.smooth,
		uiScaleMode = storedData.uiScaleMode,
		eyeComfortMode = storedData.eyeComfortMode,
		colorBrightness = storedData.colorBrightness,
		colorContrast = storedData.colorContrast,
		colorSaturation = storedData.colorSaturation,
		depthOfField = storedData.depthOfField,
		playerEffects = storedData.playerEffects,
		hideAllParticles = storedData.hideAllParticles,
		textures = storedData.textures,
		musicVolume = storedData.musicVolume,
		_musicVolBase = storedData._musicVolBase,
		graphicsPreset = storedData.graphicsPreset,
		shadowQuality = storedData.shadowQuality,
		overheadDistance = storedData.overheadDistance,
		overheadLayerVisible = storedData.overheadLayerVisible,
		overheadBadgeVisible = storedData.overheadBadgeVisible,
		chatBubbleVisibility = storedData.chatBubbleVisibility,
		hideAdminAnnounce = storedData.hideAdminAnnounce,
		hideCoupleAnnounce = storedData.hideCoupleAnnounce,
		hideDonationAnnounce = storedData.hideDonationAnnounce,
		hideDonationWorldEffect = storedData.hideDonationWorldEffect,
		hideDonationAura = storedData.hideDonationAura,
		hideDonatorHighlight = storedData.hideDonatorHighlight,
		hideSystemAnnounce = storedData.hideSystemAnnounce,
		graphicsOverrides = table.clone(storedData.graphicsOverrides),
		_version = storedData._version,
		overheadVisible = sessionData.overheadVisible,
		hideAllGui = sessionData.hideAllGui,
	}) :: SettingsPayload
end

-- Merge server stored fields into a client payload while keeping session fields local.
function SettingsDomain.applyStoredToPayload(
	current: SettingsPayload,
	stored: SettingsStoredData
): SettingsPayload
	local sanitized = SettingsDomain.sanitizeStored(stored)
	return SettingsDomain.merge(sanitized, {
		overheadVisible = current.overheadVisible,
		hideAllGui = current.hideAllGui,
	})
end

function SettingsDomain.cloneStored(data: SettingsStoredData): SettingsStoredData
	local cloned = table.clone(data)
	cloned.overheadLayerVisible = table.clone(data.overheadLayerVisible)
	cloned.overheadBadgeVisible = table.clone(data.overheadBadgeVisible)
	cloned.graphicsOverrides = table.clone(data.graphicsOverrides)
	return cloned
end

function SettingsDomain.defaultStored(): SettingsStoredData
	return SettingsDomain.defaultStoredData()
end

function SettingsDomain.defaultSession(): SettingsSessionData
	return SettingsDomain.defaultSessionData()
end

return SettingsDomain
