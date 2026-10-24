--!strict
-- Everything the UI asks the server for. Edits go through `Do` (with a result; a refusal shows as
-- a toast); dragged controls stream through `Live`, throttled to ~30 Hz with a trailing send.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- fire and forget (handlers that must not yield)
function Actions.send(cmd: NetTypes.Command)
	task.spawn(Actions.run, cmd)
end

function Actions.probe(ids: { number }): { NetTypes.ProbeResult }
	local ok, result = pcall(Net.Probe.Invoke, ids)
	return if ok then result else {}
end

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
			task.delay(RATE, function()
				local p = pending[key]
				if p then
					pending[key] = nil
					lastSent[key] = os.clock()
					Net.Live.Fire(p.deck, p.param :: any, p.v)
				end
			end)
		end
	end
end

-- an edit sent once the value settles (drags on rulers, meters, steppers): the latest value for a
-- key goes out after `delay`
local settle: { [string]: { cmd: NetTypes.Command, at: number } } = {}
function Actions.settle(key: string, cmd: NetTypes.Command, delay: number?)
	local first = settle[key] == nil
	settle[key] = { cmd = cmd, at = os.clock() }
	if first then
		local d = delay or 0.2
		local function check()
			local e = settle[key]
			if not e then
				return
			end
			local wait = e.at + d - os.clock()
			if wait > 0 then
				task.delay(wait, check)
				return
			end
			settle[key] = nil
			Actions.run(e.cmd)
		end
		task.delay(d, check)
	end
end

function Actions.nudge(deck: number, seconds: number)
	Net.Nudge.Fire(deck, math.clamp(seconds, -4, 4))
end

return Actions
