--!strict
-- Pure domain logic for sync chain traversal and cycle protection.

local SyncDomain = {}

function SyncDomain.getSyncSource(
	playerName: string,
	syncMap: { [string]: string },
	maxDepth: number
): string?
	local current = playerName
	local depth = 0

	while depth < maxDepth do
		local leaderName = syncMap[current]
		if not leaderName then
			if current ~= playerName then
				return current
			end
			return nil
		end

		current = leaderName
		depth += 1
	end

	return current
end

function SyncDomain.wouldCreateCircular(
	playerName: string,
	targetName: string,
	syncMap: { [string]: string }
): boolean
	local current = targetName
	local visited: { [string]: boolean } = {}

	for _ = 1, 200 do
		local leaderName = syncMap[current]
		if not leaderName then
			return false
		end

		if leaderName == playerName then
			return true
		end

		if visited[leaderName] then
			return false
		end

		visited[leaderName] = true
		current = leaderName
	end

	return false
end

return SyncDomain
