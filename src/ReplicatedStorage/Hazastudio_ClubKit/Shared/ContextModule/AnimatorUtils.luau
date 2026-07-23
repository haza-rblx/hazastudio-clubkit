--!strict
-- AnimatorUtils.lua - No Priority Logic, Let Roblox Handle It
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterReady = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CharacterReady)

local module = {}
local DANCE_PRIORITY = Enum.AnimationPriority.Action4
-- Simple cache with weak keys (auto-cleanup by Lua GC)
local trackCache = setmetatable({}, { __mode = "k" })
-- Reference to AnimationPreloader (set by EmoteHandler)
module.AnimationPreloader = nil
-- ============================================
-- Animation Set (for O(1) lookup)
-- ============================================
local function animationSetFrom(loadedAnimations)
	if not loadedAnimations then return nil end
	if loadedAnimations.__asSet then return loadedAnimations.__asSet end
	local set = setmetatable({}, { __mode = "k" })
	local ids = {}
	for _, animObj in pairs(loadedAnimations) do
		if typeof(animObj) == "Instance" and animObj:IsA("Animation") then
			set[animObj] = true
			if animObj.AnimationId ~= "" then
				ids[animObj.AnimationId] = true
			end
		end
	end
	loadedAnimations.__asSet = set
	loadedAnimations.__idSet = ids
	return set
end
local function animationIdSetFrom(loadedAnimations)
	if not loadedAnimations then return nil end
	if loadedAnimations.__idSet then return loadedAnimations.__idSet end
	animationSetFrom(loadedAnimations)
	return loadedAnimations.__idSet
end
-- ============================================
-- Check if track is a dance track
-- ============================================
local function isDanceTrack(track, loadedAnimations)
	if not track then return false end
	if not track.Animation then return false end
	-- Carry poses reuse Action4 on the carried role; never treat them as dances.
	local animName = track.Animation.Name
	if type(animName) == "string" and string.sub(animName, 1, 6) == "Carry_" then
		return false
	end
	if track.Priority == DANCE_PRIORITY then
		return true
	end
	if not loadedAnimations then
		return false
	end
	local asSet = animationSetFrom(loadedAnimations)
	if asSet and asSet[track.Animation] then
		return true
	end
	local idSet = animationIdSetFrom(loadedAnimations)
	if idSet and track.Animation.AnimationId ~= "" and idSet[track.Animation.AnimationId] then
		return true
	end
	if track.Name and loadedAnimations[track.Name] then
		return true
	end
	return false
end
-- ============================================
-- Character Readiness Check
-- ============================================
function module.isCharacterReady(player)
	return CharacterReady.isReady(player, "anim")
end
function module.getAnimator(player)
	if not module.isCharacterReady(player) then
		return nil
	end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid:FindFirstChildOfClass("Animator")
end
-- ============================================
-- Get or Create Animation Track
-- ============================================
function module.getOrCreateTrack(animator, animation)
	if not animator or not animation then return nil end
	-- Validate animator hierarchy
	if not animator.Parent or not animator.Parent.Parent then
		return nil
	end
	-- Try preloaded track first (client-side only)
	if module.AnimationPreloader then
		local preloadedTrack = module.AnimationPreloader.getPreloadedTrack(animation)
		if preloadedTrack then
			-- Validate preloaded track
			local isValid = pcall(function()
				return preloadedTrack.IsPlaying, preloadedTrack.Animation
			end)
			if isValid and preloadedTrack.Parent == animator then
				return preloadedTrack
			else
				-- Preloaded track is invalid, clear it
				if module.AnimationPreloader then
					module.AnimationPreloader.invalidateTrack(animation)
				end
			end
		end
	end
	-- Fallback to cache system
	local perAnimator = trackCache[animator]
	if not perAnimator then
		perAnimator = setmetatable({}, { __mode = "k" })
		trackCache[animator] = perAnimator
	end
	local track = perAnimator[animation]
	-- Validate cached track
	if track then
		local isValid = pcall(function()
			if not track.Parent or track.Parent ~= animator then
				return false
			end
			return track.IsPlaying, track.Animation
		end)
		-- Important: Invalidate stopped tracks
		-- Stopped tracks can't be reliably replayed, must reload fresh
		if isValid and track.IsPlaying == false and track.WeightCurrent <= 0.01 then
			isValid = false
		end
		if not isValid then
			pcall(function()
				if track and track.Parent then
					track:Stop(0)
					track:Destroy()
				end
			end)
			perAnimator[animation] = nil
			track = nil
		end
	end
	-- Create new track if needed
	if not track then
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok then
			return nil, tostring(loaded)
		end
		if not loaded then
			return nil, "LoadAnimation returned nil"
		end
		-- No priority override here; let Roblox handle it.
		perAnimator[animation] = loaded
		track = loaded
	end
	return track
end
-- ============================================
-- Get Currently Playing Dance Track
-- Optional expectedAnimationId prefers that track; otherwise highest WeightCurrent wins.
-- ============================================
function module.getPlayingDanceTrack(animator, loadedAnimations, expectedAnimationId)
	if not animator or not animator.Parent then return nil end
	local tracks
	local success = pcall(function()
		tracks = animator:GetPlayingAnimationTracks()
	end)
	if not success or not tracks then return nil end

	local bestTrack = nil
	local bestName = nil
	local bestWeight = -1
	local expectedId = if type(expectedAnimationId) == "string" and expectedAnimationId ~= ""
		then expectedAnimationId
		else nil

	for _, t in ipairs(tracks) do
		if isDanceTrack(t, loadedAnimations) then
			if t.IsPlaying and t.WeightCurrent > 0.01 then
				local trackAnimation = t.Animation
				local trackId = if trackAnimation then trackAnimation.AnimationId else ""
				local hit = nil
				for name, animObj in pairs(loadedAnimations or {}) do
					if typeof(animObj) == "Instance" and animObj:IsA("Animation") then
						if trackAnimation and (trackAnimation == animObj or trackId == animObj.AnimationId) then
							hit = name
							break
						end
					end
				end
				local nameOrDefault = hit or t.Name
				if expectedId and trackId == expectedId then
					return t, nameOrDefault
				end
				local weight = t.WeightCurrent
				if weight > bestWeight then
					bestWeight = weight
					bestTrack = t
					bestName = nameOrDefault
				end
			end
		end
	end
	if bestTrack then
		return bestTrack, bestName
	end
	return nil
end
-- ============================================
-- Stop All Dance Tracks
-- ============================================
function module.stopAllDances(animator, loadedAnimations, fadeOut)
	if not animator or not animator.Parent then return end
	fadeOut = (fadeOut ~= nil) and fadeOut or 0.06
	local tracks
	local success = pcall(function()
		tracks = animator:GetPlayingAnimationTracks()
	end)
	if not success or not tracks then return end
	for _, t in ipairs(tracks) do
		if isDanceTrack(t, loadedAnimations) then
			pcall(function() t:Stop(fadeOut) end)
		end
	end
end
-- ============================================
-- Stop all dances EXCEPT the specified track
-- ============================================
function module.stopOtherDances(animator, excludeTrack, loadedAnimations, fadeOut)
	if not animator or not animator.Parent then return end
	fadeOut = (fadeOut ~= nil) and fadeOut or 0.06
	local tracks
	local success = pcall(function()
		tracks = animator:GetPlayingAnimationTracks()
	end)
	if not success or not tracks then return end
	for _, t in ipairs(tracks) do
		if t ~= excludeTrack and isDanceTrack(t, loadedAnimations) then
			pcall(function() t:Stop(fadeOut) end)
		end
	end
end

-- Crossfade helper: at most one soft-out + one soft-in.
-- Mid-fade / low-weight dance tracks are hard-cleared (Stop after Stop is unreliable
-- on Roblox — that's what stacked into "broken arms"). Full-weight dances soft-out.
function module.prepareDanceCrossfade(animator, excludeTrack, loadedAnimations, fadeOut)
	if not animator or not animator.Parent then
		return
	end
	fadeOut = (fadeOut ~= nil) and fadeOut or 0.06
	local tracks
	local success = pcall(function()
		tracks = animator:GetPlayingAnimationTracks()
	end)
	if not success or not tracks then
		return
	end

	-- Only hard-clear near-dead zombies. Soft-stop anything still visible so
	-- SwitchFade actually blends (old 0.98 threshold hard-killed mid-weight tracks).
	local ZOMBIE_WEIGHT = 0.2
	for _, t in ipairs(tracks) do
		if t ~= excludeTrack and isDanceTrack(t, loadedAnimations) then
			local weight = 0
			pcall(function()
				weight = t.WeightCurrent
			end)
			if (not t.IsPlaying) or weight < ZOMBIE_WEIGHT then
				pcall(function()
					t:Stop(0)
				end)
			else
				pcall(function()
					t:Stop(fadeOut)
				end)
			end
		end
	end
end
-- ============================================
-- Clear Cache (call on character death)
-- ============================================
function module.clearCacheForPlayer(player)
	if not player or not player.Character then return end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	-- Clear this animator's cache
	trackCache[animator] = nil
end
return module
