--!strict
-- Bounded-concurrency client boot scheduler.
-- Interactive tasks gate the loading screen; postGameplay tasks run after tap dismiss.

export type BootPhase = "interactive" | "postGameplay" | "deferred"

export type BootTask = {
	name: string,
	phase: BootPhase,
	run: () -> (),
}

export type ClientBootScheduler = {
	track: (self: ClientBootScheduler, name: string, phase: BootPhase, run: () -> ()) -> (),
	setInteractiveComplete: (self: ClientBootScheduler) -> (),
	notifyGameplayEntered: (self: ClientBootScheduler) -> (),
	notifyLoadingFinished: (self: ClientBootScheduler) -> (),
	getInteractivePending: (self: ClientBootScheduler) -> number,
	getInteractiveTotal: (self: ClientBootScheduler) -> number,
	getInteractiveDone: (self: ClientBootScheduler) -> number,
	onInteractiveProgress: (self: ClientBootScheduler, callback: () -> ()) -> (),
	onInteractiveSettled: (self: ClientBootScheduler, callback: () -> ()) -> (),
}

export type ClientBootSchedulerConfig = {
	maxConcurrentInteractive: number?,
	maxConcurrentPostGameplay: number?,
	maxConcurrentDeferred: number?,
}

local ClientBootScheduler = {} :: { create: (ClientBootSchedulerConfig?) -> ClientBootScheduler }

local function normalizePhase(phase: BootPhase): "interactive" | "postGameplay"
	if phase == "interactive" then
		return "interactive"
	end
	return "postGameplay"
end

local function runTask(
	name: string,
	phase: string,
	run: () -> (),
	onDone: () -> ()
)
	local ok, result = xpcall(function()
		local innerOk, innerResult = xpcall(run, function(err)
			return debug.traceback(tostring(err), 2)
		end)
		if not innerOk then
			error(innerResult)
		end
		return true
	end, function(err)
		return debug.traceback(string.format("[ClientBoot] %s failed: %s", name, tostring(err)), 2)
	end)

	if not ok then
		warn(result)
	end
	onDone()
end

function ClientBootScheduler.create(config: ClientBootSchedulerConfig?): ClientBootScheduler
	local cfg = config or {}
	local maxInteractive = math.max(1, math.floor(tonumber(cfg.maxConcurrentInteractive) or 2))
	local maxPostGameplay = math.max(
		1,
		math.floor(tonumber(cfg.maxConcurrentPostGameplay) or tonumber(cfg.maxConcurrentDeferred) or 1)
	)

	local interactiveQueue: { BootTask } = {}
	local postGameplayQueue: { BootTask } = {}
	local interactiveActive = 0
	local postGameplayActive = 0
	local interactivePending = 0
	local interactiveTotal = 0
	local interactiveDone = 0
	local interactiveComplete = false
	local gameplayEntered = false
	local progressCallbacks: { () -> () } = {}
	local settledCallbacks: { () -> () } = {}

	local function fireProgress()
		for _, callback in ipairs(progressCallbacks) do
			task.defer(callback)
		end
	end

	local function fireSettled()
		for _, callback in ipairs(settledCallbacks) do
			task.defer(callback)
		end
	end

	local function maybeSettled()
		if interactivePending > 0 or interactiveActive > 0 then
			return
		end
		fireSettled()
	end

	local function pumpInteractive()
		while interactiveActive < maxInteractive and #interactiveQueue > 0 do
			local taskInfo = table.remove(interactiveQueue, 1)
			if not taskInfo then
				break
			end
			interactiveActive += 1
			task.spawn(function()
				runTask(taskInfo.name, "interactive", taskInfo.run, function()
					interactiveActive = math.max(interactiveActive - 1, 0)
					interactivePending = math.max(interactivePending - 1, 0)
					interactiveDone += 1
					fireProgress()
					pumpInteractive()
					maybeSettled()
				end)
			end)
		end
	end

	local function pumpPostGameplay()
		if not gameplayEntered or not interactiveComplete then
			return
		end
		while postGameplayActive < maxPostGameplay and #postGameplayQueue > 0 do
			local taskInfo = table.remove(postGameplayQueue, 1)
			if not taskInfo then
				break
			end
			postGameplayActive += 1
			task.spawn(function()
				runTask(taskInfo.name, "postGameplay", taskInfo.run, function()
					postGameplayActive = math.max(postGameplayActive - 1, 0)
					pumpPostGameplay()
				end)
			end)
		end
	end

	local self = {} :: ClientBootScheduler

	function self:track(name: string, phase: BootPhase, run: () -> ())
		local normalizedPhase = normalizePhase(phase)
		local taskInfo: BootTask = {
			name = name,
			phase = normalizedPhase,
			run = run,
		}
		if normalizedPhase == "interactive" then
			interactiveTotal += 1
			interactivePending += 1
			table.insert(interactiveQueue, taskInfo)
			pumpInteractive()
			return
		end
		table.insert(postGameplayQueue, taskInfo)
		pumpPostGameplay()
	end

	function self:setInteractiveComplete()
		interactiveComplete = true
		pumpPostGameplay()
	end

	function self:notifyGameplayEntered()
		gameplayEntered = true
		pumpPostGameplay()
	end

	function self:notifyLoadingFinished()
		self:notifyGameplayEntered()
	end

	function self:getInteractivePending(): number
		return interactivePending
	end

	function self:getInteractiveTotal(): number
		return interactiveTotal
	end

	function self:getInteractiveDone(): number
		return interactiveDone
	end

	function self:onInteractiveProgress(callback: () -> ())
		table.insert(progressCallbacks, callback)
	end

	function self:onInteractiveSettled(callback: () -> ())
		table.insert(settledCallbacks, callback)
	end

	return self
end

return ClientBootScheduler
