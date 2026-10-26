--!strict
-- Everything the UI asks the server for. Edits go through `Do` (with a result; a refusal shows as
-- a toast); dragged controls stream through `Live`, throttled to ~30 Hz with a trailing send.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.HazaDJ.Packages.Janitor)
local NetTypes = require(ReplicatedStorage.HazaDJ.Shared.NetTypes)
local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)
local Toast = require(script.Parent.Toast)

local Actions = {}

export type Result = NetTypes.Result

function Actions.run(cmd: NetTypes.Command): Result
	local ok, result = pcall(Net.Do.Invoke, cmd)
	if not ok then
		Toast.show("The booth didn't answer. Try again.")
		return { Ok = false }
	end
	if not result.Ok and result.Message then
		Toast.show(result.Message)
	end
	return result
end

-- like run, without the toast: for screens that show the refusal themselves (the lock screen)
function Actions.quiet(cmd: NetTypes.Command): Result
	local ok, result = pcall(Net.Do.Invoke, cmd)
	if not ok then
		return { Ok = false, Message = "The booth didn't answer. Try again." }
	end
	return result
end

-- fire and forget (handlers that must not yield)
function Actions.send(cmd: NetTypes.Command)
	task.spawn(Actions.run, cmd)
end

function Actions.probe(ids: { number }): { NetTypes.ProbeResult }
	local ok, result = pcall(Net.Probe.Invoke, ids)
	return if ok then result else {}
end

-- the delayed sends, one per key: adding under a key replaces (cancels) the one waiting there.
-- A timer takes itself out (RemoveNoClean) before it sends, so a replacement never cancels a send
-- that is already in flight
local timers = Janitor.new()

local RATE = 1 / 30
local pending: { [string]: { deck: number, param: string, v: number } } = {}
local lastSent: { [string]: number } = {}

function Actions.live(deck: number, param: NetTypes.LiveParam, v: number)
	local key = deck .. param
	Store.setLocal(key, v)
	local now = os.clock()
	if now - (lastSent[key] or 0) >= RATE then
		lastSent[key] = now
		pending[key] = nil
		Net.Live.Fire(deck, param, v)
	else
		local first = pending[key] == nil
		pending[key] = { deck = deck, param = param, v = v }
		if first then
			local index = "live:" .. key
			timers:Add(
				task.delay(RATE, function()
					timers:RemoveNoClean(index)
					local p = pending[key]
					if p then
						pending[key] = nil
						lastSent[key] = os.clock()
						Net.Live.Fire(p.deck, p.param :: any, p.v)
					end
				end),
				true,
				index
			)
		end
	end
end

-- an edit sent once the value settles (drags on rulers, meters, steppers): the latest value for a
-- key goes out `delay` after its last change (each change restarts that key's timer)
local settle: { [string]: NetTypes.Command } = {}
function Actions.settle(key: string, cmd: NetTypes.Command, delay: number?)
	settle[key] = cmd
	local index = "settle:" .. key
	timers:Add(
		task.delay(delay or 0.2, function()
			timers:RemoveNoClean(index)
			local latest = settle[key]
			settle[key] = nil
			if latest then
				Actions.run(latest)
			end
		end),
		true,
		index
	)
end

function Actions.nudge(deck: number, seconds: number)
	Net.Nudge.Fire(deck, math.clamp(seconds, -4, 4))
end

return Actions
