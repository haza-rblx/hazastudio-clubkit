--!strict
-- Shared/Domain/LevelDomain.lua
-- Pure functions only. Zero Roblox service calls.
-- Semua logika XP dan level di sini.
local Config = require(script.Parent.Parent.Constants.Config)
local LevelDomain = {}
-- ============================================================
-- XP yang dibutuhkan untuk naik dari level N ke N+1
-- Formula: BASE + (level - 1) * INCREMENT
-- Level 1->2: 100, Level 2->3: 150, Level 3->4: 200, dst
-- ============================================================
function LevelDomain.xpNeeded(level: number): number
	return Config.Level.XP_BASE + (level - 1) * Config.Level.XP_INCREMENT
end
-- ============================================================
-- Hasil setelah XP ditambahkan
-- ============================================================
export type LevelUpResult = {
	newLevel    : number,
	newXp       : number,
	didLevelUp  : boolean,
	levelsGained: number,
}
-- ============================================================
-- addXp - tambah XP, handle multiple level-up sekaligus
-- Mengembalikan state baru tanpa mutasi
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
	-- Loop untuk handle multiple level-up dari satu XP gain besar
	while true do
		-- Cek batas level
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
-- Progress XP dalam level saat ini (0.0 - 1.0)
-- Berguna untuk progress bar
-- ============================================================
function LevelDomain.progress(level: number, xp: number): number
	local needed = LevelDomain.xpNeeded(level)
	if needed <= 0 then return 1 end
	return math.clamp(xp / needed, 0, 1)
end
return LevelDomain
