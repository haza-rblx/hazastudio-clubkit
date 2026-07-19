--!strict
-- PATH: Client/Utils/RefreshCameraPreserve.luau
-- Preserve third-person orbit across /re (LoadCharacter). Roblox CameraModule
-- resets yaw/pitch when CameraSubject dies; we re-apply relative camera after
-- the new Humanoid is bound. Skips freecam / cinematic.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local CinematicCameraSystem = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CinematicCameraSystem)

local ATTR = tostring((Config.Session :: any).PENDING_REFRESH_ATTRIBUTE or "ClubKitPendingCharacterRefresh")
local BIND_NAME = "ClubKitRefreshCameraPreserve"
local FIRST_PERSON_DIST = 2.5

type Snapshot = {
	relative: CFrame,
	fov: number,
	distance: number,
}

local RefreshCameraPreserve = {}

local pending: Snapshot? = nil
local started = false

local function getAttrName(): string
	return ATTR
end

local function shouldSkipPreserve(): boolean
	if CinematicCameraSystem.isActive() then
		return true
	end
	local camera = Workspace.CurrentCamera
	if camera and camera:GetAttribute("FreecamActive") == true then
		return true
	end
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		return true
	end
	return false
end

local function captureFromCurrentCamera()
	if shouldSkipPreserve() then
		pending = nil
		return
	end
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not hrp or not hrp:IsA("BasePart") or not camera then
		return
	end
	local relative = hrp.CFrame:ToObjectSpace(camera.CFrame)
	local distance = (camera.CFrame.Position - hrp.Position).Magnitude
	if distance < FIRST_PERSON_DIST then
		-- First-person / zoomed-in: orbit restore fights CameraModule — skip.
		pending = nil
		return
	end
	pending = {
		relative = relative,
		fov = camera.FieldOfView,
		distance = distance,
	}
end

local function tryApplyCameraModule(desiredWorld: CFrame, hrp: BasePart, distance: number): boolean
	local player = Players.LocalPlayer
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if not playerScripts then
		return false
	end
	local playerModuleScript = playerScripts:FindFirstChild("PlayerModule")
	if not playerModuleScript or not playerModuleScript:IsA("ModuleScript") then
		return false
	end
	local okModule, playerModule = pcall(require, playerModuleScript)
	if not okModule or type(playerModule) ~= "table" or type(playerModule.GetCameras) ~= "function" then
		return false
	end
	local okCameras, cameras = pcall(function()
		return playerModule:GetCameras()
	end)
	if not okCameras or type(cameras) ~= "table" then
		return false
	end
	local controller = (cameras :: any).activeCameraController
	if type(controller) ~= "table" then
		return false
	end

	local offset = desiredWorld.Position - hrp.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.05 then
		return false
	end
	local yaw = math.atan2(-offset.X, -offset.Z)
	local pitch = math.atan2(offset.Y, flat.Magnitude)
	pitch = math.clamp(pitch, -1.4, 1.4)

	local applied = false
	if type((controller :: any).SetCameraToSubjectDistance) == "function" then
		pcall(function()
			(controller :: any):SetCameraToSubjectDistance(math.clamp(distance, 2, 64))
		end)
		applied = true
	end
	-- Classic/BaseCamera stores orbit as Vector2(yaw, pitch) in radians.
	if (controller :: any).cameraRotation ~= nil then
		pcall(function()
			(controller :: any).cameraRotation = Vector2.new(yaw, pitch)
		end)
		applied = true
	end
	return applied
end

local function restorePending()
	local snap = pending
	pending = nil
	if not snap then
		return
	end
	if shouldSkipPreserve() then
		return
	end

	task.spawn(function()
		local player = Players.LocalPlayer
		local character = player.Character
		if not character then
			character = player.CharacterAdded:Wait()
		end
		if typeof(character) ~= "Instance" or not character:IsA("Model") then
			return
		end

		local hrp = character:WaitForChild("HumanoidRootPart", 5)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not hrp or not hrp:IsA("BasePart") or not humanoid then
			return
		end

		-- Let CameraModule bind CameraSubject to the new Humanoid.
		for _ = 1, 3 do
			RunService.RenderStepped:Wait()
		end
		if player.Character ~= character or shouldSkipPreserve() then
			return
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		local function desiredCF(): CFrame
			return hrp.CFrame * snap.relative
		end

		tryApplyCameraModule(desiredCF(), hrp, snap.distance)
		pcall(function()
			camera.FieldOfView = snap.fov
		end)

		-- Reinforce for a few frames after CameraModule Update (priority + 1).
		pcall(function()
			RunService:UnbindFromRenderStep(BIND_NAME)
		end)
		local framesLeft = 12
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
			if framesLeft <= 0 or player.Character ~= character or not hrp.Parent then
				pcall(function()
					RunService:UnbindFromRenderStep(BIND_NAME)
				end)
				return
			end
			if shouldSkipPreserve() then
				pcall(function()
					RunService:UnbindFromRenderStep(BIND_NAME)
				end)
				return
			end
			local world = desiredCF()
			tryApplyCameraModule(world, hrp, snap.distance)
			camera.CFrame = world
			framesLeft -= 1
			if framesLeft <= 0 then
				pcall(function()
					RunService:UnbindFromRenderStep(BIND_NAME)
				end)
			end
		end)
	end)
end

function RefreshCameraPreserve.init()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer

	player.CharacterRemoving:Connect(function()
		if player:GetAttribute(getAttrName()) == true then
			captureFromCurrentCamera()
		end
	end)

	player.CharacterAdded:Connect(function()
		if pending then
			restorePending()
		end
	end)
end

return RefreshCameraPreserve
