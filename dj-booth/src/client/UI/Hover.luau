--!strict
-- Hover that respects what is on top (owner, 2026-10-26). Roblox fires MouseEnter, and sets
-- GuiState, on everything under the pointer, so a pad under an open menu or modal lit up as well.
-- One watcher asks PlayerGui what is at the pointer, takes the topmost object that catches input
-- (a tracked object, an Active one, a button or a text box) and lights the tracked objects on its
-- path. Nothing lights while a control is being dragged (see Hover.hold).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)

local Hover = {}

local tracked: { [GuiObject]: (boolean) -> () } = {}
local lit: { [GuiObject]: true } = {}
local drags = 0
local pointer: Vector2? = nil
local started = false
-- GetGuiObjectsAtPosition and the mouse disagree on the top-bar inset depending on where the game
-- runs, so the offset is learned: the first time Roblox says the pointer entered a tracked object,
-- whichever offset puts that object under the pointer wins
local offset: Vector2? = nil

local function catches(o: GuiObject): boolean
	return tracked[o] ~= nil or o.Active or o:IsA("GuiButton") or o:IsA("TextBox")
end

local function refresh()
	local hit: GuiObject? = nil
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if drags == 0 and pointer and offset and pg then
		local at = pointer - offset
		for _, o in pg:GetGuiObjectsAtPosition(at.X, at.Y) do
			if o:IsA("GuiObject") and catches(o) then
				hit = o
				break
			end
		end
	end
	for o in lit do
		if not (hit and (hit == o or hit:IsDescendantOf(o))) then
			lit[o] = nil
			local set = tracked[o]
			if set then
				set(false)
			end
		end
	end
	local at: Instance? = hit
	while at and at ~= pg do
		if at:IsA("GuiObject") and tracked[at] and not lit[at] then
			lit[at] = true;
			(tracked[at] :: (boolean) -> ())(true)
		end
		at = at.Parent
	end
end

local function start()
	if started then
		return
	end
	started = true
	UserInputService.InputChanged:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseMovement then
			pointer = UserInputService:GetMouseLocation()
			refresh()
		end
	end)
	-- things also open, close and scroll under a still pointer
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			if pointer then
				refresh()
			end
		end
	end)
end

-- `set` follows whether `inst` (or something inside it) is what the pointer is on
local function learn(inst: GuiObject)
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if offset or not pg then
		return
	end
	local m = UserInputService:GetMouseLocation()
	local fits = {}
	for _, o in { GuiService:GetGuiInset(), Vector2.zero } do
		local at = m - o
		if table.find(pg:GetGuiObjectsAtPosition(at.X, at.Y), inst) then
			table.insert(fits, o)
		end
	end
	-- an object tall enough to sit under both settles nothing; the next one will
	if #fits == 1 then
		offset = fits[1]
		pointer = m
		refresh()
	end
end

function Hover.watch(inst: GuiObject, set: (boolean) -> ())
	start()
	tracked[inst] = set
	inst.MouseEnter:Connect(function()
		learn(inst)
	end)
	inst.Destroying:Connect(function()
		tracked[inst] = nil
		lit[inst] = nil
	end)
end

-- the same as a Vide child: `Hover.track(hover)` in place of MouseEnter / MouseLeave
function Hover.track(set: (boolean) -> ())
	return Vide.action(function(inst: Instance)
		Hover.watch(inst :: GuiObject, set)
	end)
end

-- a drag has started: nothing lights until the returned release is called (safe to call twice)
function Hover.hold(): () -> ()
	drags += 1
	refresh()
	local released = false
	return function()
		if not released then
			released = true
			drags -= 1
			refresh()
		end
	end
end

return Hover
