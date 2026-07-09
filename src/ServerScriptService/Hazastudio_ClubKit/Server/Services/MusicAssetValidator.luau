--!strict
-- Server-side track asset checks before assign. Default: ID format only (no PreloadAsync).

local ContentProvider = game:GetService("ContentProvider")

local MusicAssetValidator = {}

local function toNumericAssetId(assetId: any): number?
	local numericId = tonumber(assetId)
	if not numericId or numericId <= 0 then
		return nil
	end
	return math.floor(numericId)
end

function MusicAssetValidator.isPartAssetIdValid(assetId: any): boolean
	return toNumericAssetId(assetId) ~= nil
end

function MusicAssetValidator.isPartAssetLoadable(assetId: any): boolean
	local numericId = toNumericAssetId(assetId)
	if not numericId then
		return false
	end
	local ok = pcall(function()
		ContentProvider:PreloadAsync({ "rbxassetid://" .. tostring(numericId) })
	end)
	return ok == true
end

function MusicAssetValidator.isTrackAssetIdsValid(track: any): boolean
	if type(track) ~= "table" then
		return false
	end
	local parts = track.parts
	if type(parts) ~= "table" or #parts == 0 then
		return false
	end
	for _, assetId in ipairs(parts) do
		if not MusicAssetValidator.isPartAssetIdValid(assetId) then
			return false
		end
	end
	return true
end

function MusicAssetValidator.isTrackPlayable(track: any, usePreload: boolean?): boolean
	if not MusicAssetValidator.isTrackAssetIdsValid(track) then
		return false
	end
	if usePreload ~= true then
		return true
	end
	local parts = track.parts
	for _, assetId in ipairs(parts :: { any }) do
		if not MusicAssetValidator.isPartAssetLoadable(assetId) then
			return false
		end
	end
	return true
end

return MusicAssetValidator
