--!strict
-- World pads on every client: camera shake, camera rotate (a roll), darken. Intensity 0..100 is
-- already scaled by the DJ deck's "Effect strength".
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local WorldFx = {}

local camera = workspace.CurrentCamera

local function shake(intensity: number, duration: number)
	local amp = 0.04 + intensity / 100 * 0.5
	local t0 = os.clock()
	local name = "HazaDJ_Shake"
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - t0
		if t >= duration then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local fade = 1 - t / duration
		local a = amp * fade
		camera.CFrame *= CFrame.new(math.noise(t * 18, 1) * a, math.noise(t * 18, 2) * a, 0)
	end)
end

local function roll(intensity: number, duration: number)
	local deg = 2 + intensity / 100 * 18
	local t0 = os.clock()
	local name = "HazaDJ_Roll"
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - t0
		if t >= duration then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local k = math.sin(math.pi * t / duration)
		camera.CFrame *= CFrame.Angles(0, 0, math.rad(deg * k))
	end)
end

local function darken(intensity: number, duration: number)
	local cc = Lighting:FindFirstChild("HazaDJ_Darken") :: ColorCorrectionEffect?
	if not cc then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "HazaDJ_Darken"
		c.Parent = Lighting
		cc = c
	end
	local fx = cc :: ColorCorrectionEffect
	local depth = -0.15 - intensity / 100 * 0.6
	TweenService:Create(fx, TweenInfo.new(0.25), { Brightness = depth, Saturation = -0.3 }):Play()
	task.delay(duration, function()
		TweenService:Create(fx, TweenInfo.new(0.6), { Brightness = 0, Saturation = 0 }):Play()
	end)
end

function WorldFx.play(effect: number, intensity: number, duration: number)
	if effect == 1 then
		shake(intensity, duration)
	elseif effect == 2 then
		roll(intensity, duration)
	elseif effect == 3 then
		darken(intensity, duration)
	end
end

return WorldFx
