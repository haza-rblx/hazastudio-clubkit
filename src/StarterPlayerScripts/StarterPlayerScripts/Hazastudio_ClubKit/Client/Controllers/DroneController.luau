--!strict
-- Client drone: pilot streams freecam; spectators lock Scriptable camera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local CinematicCameraSystem = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.CinematicCameraSystem)

local function createDroneController(deps: {
	freecamController: any?,
	mobileFreecamController: any?,
	remotes: Folder?,
})
	local localPlayer = Players.LocalPlayer
	local remotes = deps.remotes
		or ReplicatedStorage:WaitForChild("Remotes", 30) :: Folder
	local droneConfig = Config.Drone
	local freecam = deps.freecamController
	local mobileFreecam = deps.mobileFreecamController

	local stateRemote = remotes:WaitForChild(droneConfig.REMOTE_STATE, 30) :: RemoteEvent?
	local cameraRemote = remotes:WaitForChild(droneConfig.REMOTE_CAMERA, 30) :: RemoteEvent?

	local sessionActive = false
	local isPilot = false
	local streamConn: RBXScriptConnection? = nil
	local applyConn: RBXScriptConnection? = nil
	local lastSendAt = 0
	local lastCf: CFrame? = nil
	local lastFov: number? = nil
	local savedCameraType: Enum.CameraType? = nil
	local savedCameraSubject: Instance? = nil

	local function getCamera(): Camera?
		return Workspace.CurrentCamera
	end

	local function stopLocalFreecams()
		if freecam and type(freecam.setActive) == "function" and freecam.isActive and freecam.isActive() then
			freecam.setActive(false)
		end
		if mobileFreecam and type(mobileFreecam.setActive) == "function" and mobileFreecam.isActive and mobileFreecam.isActive() then
			mobileFreecam.setActive(false)
		end
	end

	local function stopStreaming()
		if streamConn then
			streamConn:Disconnect()
			streamConn = nil
		end
	end

	local function stopApplying()
		if applyConn then
			applyConn:Disconnect()
			applyConn = nil
		end
	end

	local function restoreCamera()
		stopStreaming()
		stopApplying()
		local cam = getCamera()
		if cam == nil then
			return
		end
		if savedCameraType then
			cam.CameraType = savedCameraType
		else
			cam.CameraType = Enum.CameraType.Custom
		end
		if savedCameraSubject then
			cam.CameraSubject = savedCameraSubject :: Humanoid | BasePart
		else
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				cam.CameraSubject = humanoid
			end
		end
		savedCameraType = nil
		savedCameraSubject = nil
		cam:SetAttribute("DroneLock", false)
		cam:SetAttribute("FreecamActive", false)
	end

	local function startPilot()
		isPilot = true
		sessionActive = true
		pcall(function()
			CinematicCameraSystem.stopCinematic()
		end)
		stopLocalFreecams()
		if freecam and type(freecam.setActive) == "function" then
			freecam.setActive(true)
		end
		stopStreaming()
		local minInterval = 1 / math.max(1, tonumber(droneConfig.STREAM_HZ) or 15)
		streamConn = RunService.RenderStepped:Connect(function()
			if not sessionActive or not isPilot or cameraRemote == nil then
				return
			end
			local now = os.clock()
			if now - lastSendAt < minInterval then
				return
			end
			lastSendAt = now
			local cam = getCamera()
			if cam == nil then
				return
			end
			local cf = cam.CFrame
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			cameraRemote:FireServer({
				c = { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 },
				fov = cam.FieldOfView,
			})
		end)
	end

	local function applyFrame(components: { number }, fov: number)
		if type(components) ~= "table" or #components < 12 then
			return
		end
		local ok, cf = pcall(function()
			return CFrame.new(
				components[1],
				components[2],
				components[3],
				components[4],
				components[5],
				components[6],
				components[7],
				components[8],
				components[9],
				components[10],
				components[11],
				components[12]
			)
		end)
		if not ok or typeof(cf) ~= "CFrame" then
			return
		end
		lastCf = cf
		lastFov = fov
		local cam = getCamera()
		if cam == nil then
			return
		end
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = cf
		cam.FieldOfView = fov
	end

	local function startSpectator()
		isPilot = false
		sessionActive = true
		pcall(function()
			CinematicCameraSystem.stopCinematic()
		end)
		stopLocalFreecams()
		local cam = getCamera()
		if cam then
			savedCameraType = cam.CameraType
			savedCameraSubject = cam.CameraSubject
			cam.CameraType = Enum.CameraType.Scriptable
			cam:SetAttribute("DroneLock", true)
		end
		stopApplying()
		applyConn = RunService.RenderStepped:Connect(function()
			if not sessionActive or isPilot then
				return
			end
			-- Keep freecam from stealing camera while spectating.
			stopLocalFreecams()
			local cam = getCamera()
			if cam == nil then
				return
			end
			cam.CameraType = Enum.CameraType.Scriptable
			if lastCf then
				cam.CFrame = lastCf
			end
			if lastFov then
				cam.FieldOfView = lastFov
			end
		end)
	end

	local function onState(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local phase = tostring(payload.phase or "")
		if phase == "start" then
			local pilotUserId = tonumber(payload.pilotUserId)
			if pilotUserId == localPlayer.UserId then
				startPilot()
			else
				startSpectator()
			end
		elseif phase == "frame" then
			if not sessionActive or isPilot then
				return
			end
			local fov = tonumber(payload.fov) or 70
			applyFrame(payload.c, fov)
		elseif phase == "stop" then
			local wasPilot = isPilot
			sessionActive = false
			isPilot = false
			lastCf = nil
			lastFov = nil
			if wasPilot and freecam and type(freecam.setActive) == "function" then
				freecam.setActive(false)
			end
			restoreCamera()
		end
	end

	local controller = {}

	function controller:init()
		if Config.FeatureFlags.DroneEnabled ~= true then
			return
		end
		if stateRemote and stateRemote:IsA("RemoteEvent") then
			stateRemote.OnClientEvent:Connect(onState)
		end
	end

	function controller:destroy()
		sessionActive = false
		isPilot = false
		restoreCamera()
	end

	return controller
end

return createDroneController
