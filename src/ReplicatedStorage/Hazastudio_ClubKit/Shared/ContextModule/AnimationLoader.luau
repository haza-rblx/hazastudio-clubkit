--!strict
-- Loads emote animations from ReplicatedStorage.Emotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationLoader = {}

local function getEmotesFolder(): Folder?
	local emotes = ReplicatedStorage:FindFirstChild("Emotes")
	if emotes and emotes:IsA("Folder") then
		return emotes
	end
	return nil
end

function AnimationLoader.loadAnimations(): { [string]: Animation }
	local animations: { [string]: Animation } = {}
	local emotesFolder = getEmotesFolder()
	if not emotesFolder then
		return animations
	end

	for _, child in ipairs(emotesFolder:GetChildren()) do
		if child:IsA("Animation") then
			animations[child.Name] = child
		end
	end

	local poseFolder = emotesFolder:FindFirstChild("Pose")
	if poseFolder and poseFolder:IsA("Folder") then
		for _, child in ipairs(poseFolder:GetChildren()) do
			if child:IsA("Animation") then
				animations[child.Name] = child
			end
		end
	end

	-- Preload dihapus dari sini karena DanceWarmupService sudah handle preload
	-- dengan lebih baik (generation check, retry logic, dll.)
	-- Menghindari double preload yang bisa bikin memory usage 2x lipat
	return animations
end

function AnimationLoader.getAnimationsByCategory(category: string): { Animation }
	local results: { Animation } = {}
	local emotesFolder = getEmotesFolder()
	if not emotesFolder then
		return results
	end

	if category == "Pose" then
		local poseFolder = emotesFolder:FindFirstChild("Pose")
		if poseFolder and poseFolder:IsA("Folder") then
			for _, child in ipairs(poseFolder:GetChildren()) do
				if child:IsA("Animation") then
					table.insert(results, child)
				end
			end
		end
	else
		for _, child in ipairs(emotesFolder:GetChildren()) do
			if child:IsA("Animation") then
				table.insert(results, child)
			end
		end
	end

	table.sort(results, function(a, b)
		return a.Name < b.Name
	end)

	return results
end

return AnimationLoader
