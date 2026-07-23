--!strict
-- Server/Init/ServerRestartHooks.luau
--
-- Early flush + player warn when Creator Hub / Open Cloud schedules a delayed
-- server restart (`game.ServerRestartScheduled`). BindToClose remains the final
-- safety net; this runs earlier so session buffers are not racing the 30s close
-- window.
--
-- Kept out of Main.server top-level locals (Luau register budget).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

export type FlushEarlyFn = () -> ()

export type NotifyApi = {
	all: (messageOrPayload: any, notifType: string?) -> (),
}

export type ConnectDeps = {
	log: any,
	notify: NotifyApi?,
	flushEarly: FlushEarlyFn,
	-- Optional Cleaner with :add(RBXScriptConnection) for hot-reload teardown.
	connectionCleaner: any?,
}

local ServerRestartHooks = {}

local handled = false

local function restartConfig(): any
	local cfg = (Config :: any).ServerRestart
	if type(cfg) == "table" then
		return cfg
	end
	return {}
end

local function formatEta(restartTime: DateTime): string
	local nowUnix = DateTime.now().UnixTimestamp
	local targetUnix = restartTime.UnixTimestamp
	local secs = math.max(0, targetUnix - nowUnix)
	if secs < 60 then
		return string.format("%ds", secs)
	end
	local mins = math.floor(secs / 60)
	local rem = secs % 60
	if rem == 0 then
		return string.format("%dm", mins)
	end
	return string.format("%dm %ds", mins, rem)
end

local function buildMessage(restartTime: DateTime, attributes: { [string]: any }?): string
	local cfg = restartConfig()
	local custom = attributes and attributes.message
	if type(custom) == "string" and custom ~= "" then
		local template = if type(cfg.MSG_WITH_REASON) == "string"
			then cfg.MSG_WITH_REASON
			else "[System] Server restart in ~{eta}. {reason} Progress is being saved."
		return (template:gsub("{eta}", formatEta(restartTime)):gsub("{reason}", custom))
	end

	local template = if type(cfg.MSG_DEFAULT) == "string"
		then cfg.MSG_DEFAULT
		else "[System] Server restart in ~{eta}. Your progress is being saved."
	return template:gsub("{eta}", formatEta(restartTime))
end

--- Connect once. Safe if Studio lacks the API (pcall). Idempotent on repeat fire.
function ServerRestartHooks.connect(deps: ConnectDeps)
	handled = false

	local log = deps.log
	local notify = deps.notify
	local flushEarly = deps.flushEarly
	local cleaner = deps.connectionCleaner

	local ok, signalOrErr = pcall(function()
		return (game :: any).ServerRestartScheduled
	end)
	if not ok or typeof(signalOrErr) ~= "RBXScriptSignal" then
		if log and type(log.debug) == "function" then
			log:debug("ServerRestartScheduled unavailable — skip early-restart hook", {
				error = if not ok then tostring(signalOrErr) else "not a signal",
			})
		end
		return
	end

	local connection = (signalOrErr :: RBXScriptSignal):Connect(function(restartTime: any, source: any, attributes: any)
		if handled then
			return
		end
		handled = true

		local eta = if typeof(restartTime) == "DateTime" then formatEta(restartTime) else "?"
		if log and type(log.info) == "function" then
			log:info("ServerRestartScheduled — early flush + notify", {
				eta = eta,
				source = tostring(source),
				hasAttributes = type(attributes) == "table",
			})
		end

		if notify and type(notify.all) == "function" and typeof(restartTime) == "DateTime" then
			local notifType = restartConfig().NOTIF_TYPE
			if type(notifType) ~= "string" or notifType == "" then
				notifType = "WARNING"
			end
			pcall(function()
				notify.all(buildMessage(restartTime, attributes), notifType)
			end)
		end

		-- Flush in a spawned thread so the event callback returns quickly.
		task.spawn(function()
			local flushOk, flushErr = pcall(flushEarly)
			if not flushOk then
				if log and type(log.warn) == "function" then
					log:warn("ServerRestartScheduled early flush failed", {
						error = tostring(flushErr),
					})
				end
			elseif log and type(log.info) == "function" then
				log:info("ServerRestartScheduled early flush complete")
			end
		end)
	end)

	if cleaner and type(cleaner.add) == "function" then
		cleaner:add(connection)
	end
end

--- Test / hot-reload helper.
function ServerRestartHooks.resetHandled()
	handled = false
end

return ServerRestartHooks
