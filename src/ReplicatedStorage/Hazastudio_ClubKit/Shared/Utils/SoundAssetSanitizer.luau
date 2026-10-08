--!strict
-- Strips Sound instances that use asset IDs blocked for this experience.

local BLOCKED_SOUND_IDS: { [string]: boolean } = {
	["8578316223"] = true, -- not approved for requester (Smite3/4 MainChargeSound)
	["9009370950"] = true, -- file not found (Smite3/4 hammer charge sounds)
}

local SoundAssetSanitizer = {}

local function normalizeAssetId(soundId: string): string
	local id = string.match(soundId, "(%d+)")
	return if id then id else ""
end

function SoundAssetSanitizer.getBlockedSoundIds(): { string }
	local ids: { string } = {}
	for id in pairs(BLOCKED_SOUND_IDS) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function SoundAssetSanitizer.isBlockedSoundId(soundId: string): boolean
	local normalized = normalizeAssetId(soundId)
	return normalized ~= "" and BLOCKED_SOUND_IDS[normalized] == true
end

function SoundAssetSanitizer.safePlay(sound: Instance?)
	if not sound or not sound:IsA("Sound") or not sound.Parent then
		return
	end
	if SoundAssetSanitizer.isBlockedSoundId(sound.SoundId) then
		return
	end
	pcall(function()
		sound:Play()
	end)
end

function SoundAssetSanitizer.safeStop(sound: Instance?)
	if not sound or not sound:IsA("Sound") or not sound.Parent then
		return
	end
	pcall(function()
		sound:Stop()
	end)
end

-- Donation effect templates keep their audio unloaded (2026-10-07): a Sound with a SoundId holds
-- its decoded audio in memory wherever it sits, so the four WorldEffects templates cost every
-- client ~40 MB for effects that play a few times a session (measured: Sounds tag -40.4 MB).
-- The id moves to this attribute on the template and comes back on each clone.
SoundAssetSanitizer.DEFERRED_ATTRIBUTE = "DeferredSoundId"

function SoundAssetSanitizer.deferSound(sound: Sound)
	if sound.SoundId ~= "" then
		sound:SetAttribute(SoundAssetSanitizer.DEFERRED_ATTRIBUTE, sound.SoundId)
		sound.SoundId = ""
	end
end

function SoundAssetSanitizer.deferSounds(root: Instance): number
	local deferred = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") and descendant.SoundId ~= "" then
			SoundAssetSanitizer.deferSound(descendant)
			deferred += 1
		end
	end
	return deferred
end

-- Call on every effect clone before it plays: drops blocked sounds, puts deferred ids back and
-- starts loading them. Not awaited, so the effect timeline is unchanged; a sound played before its
-- audio arrives starts when it loads (0.48 s for BlackHole's 26 sounds from the disk cache).
function SoundAssetSanitizer.sanitizeClone(root: Instance)
	SoundAssetSanitizer.removeBlockedSounds(root)
	local restored: { Instance } = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			local id = descendant:GetAttribute(SoundAssetSanitizer.DEFERRED_ATTRIBUTE)
			if type(id) == "string" and id ~= "" then
				descendant.SoundId = id
				table.insert(restored, descendant)
			end
		end
	end
	if #restored > 0 then
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(restored)
			end)
		end)
	end
end

function SoundAssetSanitizer.removeBlockedSounds(root: Instance): number
	local removed = 0

	local function maybeRemove(sound: Sound)
		if SoundAssetSanitizer.isBlockedSoundId(sound.SoundId) then
			sound:Destroy()
			removed += 1
		end
	end

	if root:IsA("Sound") then
		maybeRemove(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound") then
			maybeRemove(descendant)
		end
	end

	return removed
end

return SoundAssetSanitizer
