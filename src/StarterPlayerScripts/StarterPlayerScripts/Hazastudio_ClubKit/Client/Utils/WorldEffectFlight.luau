--!strict
-- Single-flight coordinator for world donation VFX (Nuke / Smite4 / BlackHole).
-- Only one EffectDonate sequence runs at a time; a new begin() aborts the prior
-- cleanup callback (Destroy clones, stop sounds, restore Lighting, etc.).

export type WorldEffectFlight = {
	begin: (self: WorldEffectFlight) -> number,
	isActive: (self: WorldEffectFlight, generation: number) -> boolean,
	setCleanup: (self: WorldEffectFlight, generation: number, cleanup: () -> ()) -> (),
	finish: (self: WorldEffectFlight, generation: number) -> (),
	wait: (self: WorldEffectFlight, generation: number, seconds: number) -> boolean,
	isAbortError: (err: any) -> boolean,
}

local generation = 0
local activeCleanup: (() -> ())? = nil
local ABORT_TOKEN = "WorldEffectAborted"

local WorldEffectFlight = {} :: WorldEffectFlight

--- Roblox wraps `error("WorldEffectAborted")` as `"path:line: WorldEffectAborted"`.
function WorldEffectFlight.isAbortError(err: any): boolean
	return string.find(tostring(err), ABORT_TOKEN, 1, true) ~= nil
end

function WorldEffectFlight:begin(): number
	local prev = activeCleanup
	activeCleanup = nil
	generation += 1
	if prev then
		pcall(prev)
	end
	return generation
end

function WorldEffectFlight:isActive(gen: number): boolean
	return gen == generation
end

function WorldEffectFlight:setCleanup(gen: number, cleanup: () -> ())
	if gen == generation then
		activeCleanup = cleanup
	end
end

function WorldEffectFlight:finish(gen: number)
	if gen == generation then
		activeCleanup = nil
	end
end

--- Yield up to `seconds`. Returns false if this generation was aborted.
function WorldEffectFlight:wait(gen: number, seconds: number): boolean
	if gen ~= generation then
		return false
	end
	local deadline = os.clock() + math.max(0, seconds)
	while os.clock() < deadline do
		if gen ~= generation then
			return false
		end
		local remaining = deadline - os.clock()
		if remaining <= 0 then
			break
		end
		task.wait(math.min(0.25, remaining))
	end
	return gen == generation
end

return WorldEffectFlight
