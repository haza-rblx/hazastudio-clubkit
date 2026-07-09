--!strict
-- ServerScriptService/Server/Services/BackgroundJobScheduler.luau
--
-- Centralized scheduler for periodic background jobs with jitter.
-- Prevents thundering herd from multiple inline task.spawn loops.
--
-- Features:
-- - Jitter range per job to spread load
-- - Defer when NumPlayers exceeds threshold
-- - Named jobs for debugging
-- - Graceful start/stop

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)

type ILogger = Types.ILogger

export type JobConfig = {
	name: string,
	callback: () -> (),
	intervalMin: number,
	intervalMax: number?,
	deferThreshold: number?,
	enabled: boolean?,
}

export type RegisteredJob = {
	name: string,
	callback: () -> (),
	intervalMin: number,
	intervalMax: number,
	deferThreshold: number,
	enabled: boolean,
	lastRunAt: number,
	nextRunAt: number,
	running: boolean,
}

export type BackgroundJobScheduler = {
	register: (self: BackgroundJobScheduler, config: JobConfig) -> (),
	unregister: (self: BackgroundJobScheduler, name: string) -> (),
	setEnabled: (self: BackgroundJobScheduler, name: string, enabled: boolean) -> (),
	runNow: (self: BackgroundJobScheduler, name: string) -> (),
	start: (self: BackgroundJobScheduler) -> (),
	stop: (self: BackgroundJobScheduler) -> (),
	getJobStats: (self: BackgroundJobScheduler) -> { [string]: { lastRunAt: number, nextRunAt: number, enabled: boolean } },
}

local function createBackgroundJobScheduler(deps: {
	logger: ILogger?,
}?): BackgroundJobScheduler
	local log = if deps and deps.logger then deps.logger else Logger.new("BackgroundJobScheduler")
	
	local jobs: { [string]: RegisteredJob } = {}
	local isRunning = false
	local tickThread: thread? = nil
	
	local TICK_INTERVAL = 1
	local JOB_TIMEOUT_SECONDS = 30

	local service = {} :: BackgroundJobScheduler
	
	local function getJitteredInterval(job: RegisteredJob): number
		local min = job.intervalMin
		local max = job.intervalMax
		if min >= max then
			return min
		end
		return min + math.random() * (max - min)
	end
	
	local function shouldDefer(job: RegisteredJob): boolean
		if job.deferThreshold <= 0 then
			return false
		end
		return #Players:GetPlayers() > job.deferThreshold
	end
	
	local function runJob(job: RegisteredJob)
		if job.running then
			return
		end
		
		job.running = true
		local startedAt = os.clock()
		
		-- Watchdog: force-release if job hangs beyond timeout
		local watchdog = task.delay(JOB_TIMEOUT_SECONDS, function()
			if job.running then
				job.running = false
				job.lastRunAt = os.clock()
				job.nextRunAt = os.clock() + getJitteredInterval(job)
				log:warn("Job timed out, force-released", {
					name = job.name,
					elapsedMs = math.floor((os.clock() - startedAt) * 1000),
				})
			end
		end)
		
		local ok, err = pcall(job.callback)
		task.cancel(watchdog)
		
		local elapsed = os.clock() - startedAt
		job.lastRunAt = os.clock()
		job.nextRunAt = os.clock() + getJitteredInterval(job)
		job.running = false
		
		if not ok then
			log:warn("Job failed", {
				name = job.name,
				error = tostring(err),
				elapsedMs = math.floor(elapsed * 1000),
			})
		else
			log:debug("Job completed", {
				name = job.name,
				elapsedMs = math.floor(elapsed * 1000),
			})
		end
	end
	
	local function tick()
		local now = os.clock()
		
		for _, job in pairs(jobs) do
			if not job.enabled then
				continue
			end
			
			if now < job.nextRunAt then
				continue
			end
			
			if shouldDefer(job) then
				job.nextRunAt = now + getJitteredInterval(job) * 0.5
				log:debug("Job deferred due to player count", {
					name = job.name,
					playerCount = #Players:GetPlayers(),
					threshold = job.deferThreshold,
				})
				continue
			end
			
			task.spawn(runJob, job)
		end
	end
	
	function service:register(config: JobConfig)
		local name = config.name
		if not name or name == "" then
			log:warn("Job registration failed: missing name")
			return
		end
		
		if jobs[name] then
			log:warn("Job already registered, updating", { name = name })
		end
		
		local intervalMin = math.max(1, config.intervalMin or 60)
		local intervalMax = math.max(intervalMin, config.intervalMax or intervalMin)
		
		local job: RegisteredJob = {
			name = name,
			callback = config.callback,
			intervalMin = intervalMin,
			intervalMax = intervalMax,
			deferThreshold = config.deferThreshold or 0,
			enabled = if config.enabled == nil then true else config.enabled,
			lastRunAt = 0,
			nextRunAt = os.clock() + math.random() * intervalMin,
			running = false,
		}
		
		jobs[name] = job
		
		log:info("Job registered", {
			name = name,
			intervalMin = intervalMin,
			intervalMax = intervalMax,
			deferThreshold = job.deferThreshold,
		})
	end
	
	function service:unregister(name: string)
		if jobs[name] then
			jobs[name] = nil
			log:info("Job unregistered", { name = name })
		end
	end
	
	function service:setEnabled(name: string, enabled: boolean)
		local job = jobs[name]
		if job then
			job.enabled = enabled
			log:info("Job enabled state changed", { name = name, enabled = enabled })
		end
	end
	
	function service:runNow(name: string)
		local job = jobs[name]
		if job and job.enabled and not job.running then
			task.spawn(runJob, job)
		end
	end
	
	function service:start()
		if isRunning then
			return
		end
		
		isRunning = true
		
		tickThread = task.spawn(function()
			while isRunning do
				tick()
				task.wait(TICK_INTERVAL)
			end
		end)
		
		log:info("Scheduler started", { jobCount = 0 })
		
		local count = 0
		for _ in pairs(jobs) do
			count += 1
		end
		log:info("Scheduler running", { jobCount = count })
	end
	
	function service:stop()
		isRunning = false
		if tickThread then
			task.cancel(tickThread)
			tickThread = nil
		end
		log:info("Scheduler stopped")
	end
	
	function service:getJobStats(): { [string]: { lastRunAt: number, nextRunAt: number, enabled: boolean } }
		local stats = {}
		for name, job in pairs(jobs) do
			stats[name] = {
				lastRunAt = job.lastRunAt,
				nextRunAt = job.nextRunAt,
				enabled = job.enabled,
			}
		end
		return stats
	end
	
	return service
end

return {
	create = createBackgroundJobScheduler,
}
