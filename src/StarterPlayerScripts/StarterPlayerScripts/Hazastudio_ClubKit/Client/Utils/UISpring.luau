--!strict
-- Critically-damped spring for UI (same formula as Freecam). No overshoot; soft settle.
-- Drive from Heartbeat so open/close can retarget mid-flight without hard cuts.

local RunService = game:GetService("RunService")

export type NumberSpring = {
	f: number,
	p: number,
	v: number,
}

export type DriveHandle = {
	retarget: (self: DriveHandle, goal: number) -> (),
	setFrequency: (self: DriveHandle, frequency: number) -> (),
	stop: (self: DriveHandle) -> (),
	getPosition: (self: DriveHandle) -> number,
	getVelocity: (self: DriveHandle) -> number,
	isRunning: (self: DriveHandle) -> boolean,
}

local UISpring = {}

local TWO_PI = math.pi * 2

function UISpring.newNumber(frequency: number, position: number): NumberSpring
	return {
		f = math.max(0.01, frequency),
		p = position,
		v = 0,
	}
end

function UISpring.reset(spring: NumberSpring, position: number)
	spring.p = position
	spring.v = 0
end

function UISpring.step(spring: NumberSpring, dt: number, goal: number): number
	local f = spring.f * TWO_PI
	local p0 = spring.p
	local v0 = spring.v
	local offset = goal - p0
	local decay = math.exp(-f * dt)
	local p1 = goal + (v0 * dt - offset * (f * dt + 1)) * decay
	local v1 = (f * dt * (offset * f - v0) + v0) * decay
	spring.p = p1
	spring.v = v1
	return p1
end

function UISpring.isSettled(spring: NumberSpring, goal: number, posEpsilon: number?, velEpsilon: number?): boolean
	local pEps = posEpsilon or 0.15
	local vEps = velEpsilon or 1.5
	return math.abs(goal - spring.p) <= pEps and math.abs(spring.v) <= vEps
end

function UISpring.driveNumber(opts: {
	frequency: number,
	position: number,
	goal: number,
	velocity: number?,
	posEpsilon: number?,
	velEpsilon: number?,
	onStep: (value: number) -> (),
	onSettled: (() -> ())?,
}): DriveHandle
	local spring = UISpring.newNumber(opts.frequency, opts.position)
	spring.v = opts.velocity or 0
	local goal = opts.goal
	local connection: RBXScriptConnection? = nil
	local settled = false
	local stopped = false

	local function stopInternal()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		stopped = true
	end

	local function maybeSettle()
		if settled or stopped then
			return
		end
		if not UISpring.isSettled(spring, goal, opts.posEpsilon, opts.velEpsilon) then
			return
		end
		settled = true
		spring.p = goal
		spring.v = 0
		opts.onStep(goal)
		stopInternal()
		if opts.onSettled then
			opts.onSettled()
		end
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		if stopped then
			return
		end
		-- Cap dt so a hitch doesn't explode the integrator.
		local stepDt = math.clamp(dt, 0, 1 / 20)
		opts.onStep(UISpring.step(spring, stepDt, goal))
		maybeSettle()
	end)

	-- Apply first sample immediately so callers don't wait a frame.
	opts.onStep(spring.p)

	local handle: DriveHandle = {
		retarget = function(_self: DriveHandle, newGoal: number)
			if stopped then
				return
			end
			goal = newGoal
			settled = false
		end,
		setFrequency = function(_self: DriveHandle, frequency: number)
			spring.f = math.max(0.01, frequency)
		end,
		stop = function(_self: DriveHandle)
			stopInternal()
		end,
		getPosition = function(_self: DriveHandle): number
			return spring.p
		end,
		getVelocity = function(_self: DriveHandle): number
			return spring.v
		end,
		isRunning = function(_self: DriveHandle): boolean
			return connection ~= nil and not stopped
		end,
	}
	return handle
end

return UISpring
