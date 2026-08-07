--!strict
-- Shared/Domain/LevelDomain.lua
-- Pure functions only. Zero Roblox service calls.
-- All XP and level logic lives here.
local Config = require(script.Parent.Parent.Constants.Config)
local LevelDomain = {}
-- ============================================================
-- XP required to go from level N to N+1
-- Formula: BASE + (level - 1) * INCREMENT
-- Level 1->2: 100, Level 2->3: 150, Level 3->4: 200, dst
-- ============================================================
function LevelDomain.xpNeeded(level: number): number
	return Config.Level.XP_BASE + (level - 1) * Config.Level.XP_INCREMENT
end
-- ============================================================
-- Hasil after XP ditambahkan
-- ============================================================
export type LevelUpResult = {
	newLevel    : number,
	newXp       : number,
	didLevelUp  : boolean,
	levelsGained: number,
}
-- ============================================================
-- addXp - add XP, handle multiple level-up sekaligus
-- Returns new state without mutation
-- ============================================================
function LevelDomain.addXp(
	currentLevel : number,
	currentXp    : number,
	xpGain       : number
): LevelUpResult
	local level       = tonumber(currentLevel) or 1
	local xp          = (tonumber(currentXp) or 0) + xpGain
	local levelsGained = 0
	local maxLevel    = tonumber(Config.Level.MAX_LEVEL) or 0
	-- Loop for handle multiple level-up from satu XP gain besar
	while true do
		-- Check level cap
		if maxLevel > 0 and level >= maxLevel then
			xp = math.min(xp, LevelDomain.xpNeeded(level) - 1)
			break
		end
		local needed = LevelDomain.xpNeeded(level)
		if xp < needed then break end
		xp    = xp - needed
		level = level + 1
		levelsGained += 1
	end
	return {
		newLevel     = level,
		newXp        = xp,
		didLevelUp   = levelsGained > 0,
		levelsGained = levelsGained,
	}
end
-- ============================================================
-- Progress XP dalam level when ini (0.0 - 1.0)
-- Berguna for progress bar
-- ============================================================
function LevelDomain.progress(level: number, xp: number): number
	local needed = LevelDomain.xpNeeded(level)
	if needed <= 0 then return 1 end
	return math.clamp(xp / needed, 0, 1)
end
return LevelDomain
