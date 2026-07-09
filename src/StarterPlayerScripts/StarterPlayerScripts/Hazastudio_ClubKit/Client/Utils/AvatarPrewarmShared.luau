--!strict
-- Single client-wide AvatarPrewarmPool (ACM + donation self preview, nearby players).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local AvatarPrewarmPool = require(script.Parent.AvatarPrewarmPool)

local sharedPool: AvatarPrewarmPool.AvatarPrewarmPool? = nil

local AvatarPrewarmShared = {}

function AvatarPrewarmShared.getPool(): AvatarPrewarmPool.AvatarPrewarmPool
	if sharedPool then
		return sharedPool
	end
	local poolSize = math.max(1, tonumber(Config.AvatarContext.VIEWPORT_POOL_SIZE) or 15)
	sharedPool = AvatarPrewarmPool.create({
		maxPoolSize = poolSize,
		proximityRadius = 30,
		-- 0.1s cooldown hanya untuk tick-based proximity scan. Event-driven
		-- prewarm (PlayerAdded, CharacterAdded, on-demand click) tetap paralel
		-- sehingga pool terisi cepat di 100 CCU.
		loadCooldown = 0.1,
		prewarmSelf = Config.AvatarContext.VIEWPORT_PREWARM_SELF ~= false,
	})
	return sharedPool
end

-- Tear down the shared pool (Heartbeat + PlayerAdded/PlayerRemoving conns +
-- live 3D models). Called from Main.client script.Destroying so a Rojo/Argon
-- hot-reload does not orphan the old pool's connections and avatar models.
function AvatarPrewarmShared.destroy()
	if sharedPool and type((sharedPool :: any).destroy) == "function" then
		pcall(function()
			(sharedPool :: any):destroy()
		end)
	end
	sharedPool = nil
end

return AvatarPrewarmShared
