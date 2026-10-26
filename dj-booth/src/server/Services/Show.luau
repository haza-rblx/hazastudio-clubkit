--!strict
-- What the room sees: "… is live" and now-playing toasts, the live DJ's name over the DJ deck, the
-- beat for club lights, and the DJ deck's prompt / floor. The game opts in by tagging parts:
--   HazaDJ_DjDeck  - the DJ deck (name billboard, "Open the decks" prompt, near-DJ deck pads);
--                    the older HazaDJ_Booth tag still works
--   HazaDJ_Stand   - the floor behind the decks (kept for DJs when "DJs only" is on)
--   HazaDJ_Speaker - where the decks are heard from in club-zone / DJ deck area mode
-- Lights listen to workspace attributes HazaDJ_BPM and HazaDJ_BeatAt (server time of a beat).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.HazaDJ.Packages.Charm)
local DjDeck = require(script.Parent.DjDeck)
local Net = require(script.Parent.Parent.Net)
local Roles = require(script.Parent.Roles)
local State = require(script.Parent.State)

local Show = {}

local function nameOf(userId: number?): string?
	if not userId then
		return nil
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		return p.DisplayName
	end
	local person = State.access().people[tostring(userId)]
	return person and person.name
end

local function billboard()
	local djDeck = CollectionService:GetTagged("HazaDJ_DjDeck")[1] or CollectionService:GetTagged("HazaDJ_Booth")[1]
	if not djDeck or not djDeck:IsA("BasePart") then
		return
	end
	local bb = djDeck:FindFirstChild("HazaDJ_Name") :: BillboardGui?
	local name = nameOf(State.session().live)
	local on = State.settings().billboard and name ~= nil
	if not on then
		if bb then
			bb:Destroy()
		end
		return
	end
	if not bb then
		local g = Instance.new("BillboardGui")
		g.Name = "HazaDJ_Name"
		g.Size = UDim2.fromOffset(240, 40)
		g.StudsOffset = Vector3.new(0, djDeck.Size.Y / 2 + 3, 0)
		g.AlwaysOnTop = false
		g.MaxDistance = 200
		local l = Instance.new("TextLabel")
		l.Name = "Name"
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.FontFace = Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold)
		l.TextScaled = true
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0.6
		l.Parent = g
		g.Parent = djDeck
		bb = g
	end
	((bb :: BillboardGui):FindFirstChild("Name") :: TextLabel).Text = name :: string
end

local function prompt()
	local djDeck = CollectionService:GetTagged("HazaDJ_DjDeck")[1] or CollectionService:GetTagged("HazaDJ_Booth")[1]
	if not djDeck or not djDeck:IsA("BasePart") then
		return
	end
	local pp = djDeck:FindFirstChild("HazaDJ_Open") :: ProximityPrompt?
	if State.settings().openAtDjDeck then
		if not pp then
			local p = Instance.new("ProximityPrompt")
			p.Name = "HazaDJ_Open"
			p.ActionText = "Open the decks"
			p.ObjectText = "DJ deck"
			p.MaxActivationDistance = 12
			p.RequiresLineOfSight = false
			p.Parent = djDeck
		end
	elseif pp then
		pp:Destroy()
	end
end

-- non-DJs standing on the DJ deck floor are moved off it
local function guardStand()
	if not State.settings().standLock then
		return
	end
	for _, stand in CollectionService:GetTagged("HazaDJ_Stand") do
		if not stand:IsA("BasePart") then
			continue
		end
		for _, p in Players:GetPlayers() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and not Roles.caps(p).canOpen then
				local rel = stand.CFrame:PointToObjectSpace(root.Position)
				local half = stand.Size / 2
				if math.abs(rel.X) < half.X and math.abs(rel.Z) < half.Z and rel.Y > -half.Y and rel.Y < half.Y + 8 then
					local out = stand.CFrame * CFrame.new(0, 0, half.Z + 4)
					root.CFrame = CFrame.new(out.Position + Vector3.new(0, 3, 0))
				end
			end
		end
	end
end

local function beat()
	local s = State.session()
	local from = if s.xfader <= 0.5 then 1 else 2
	local d = s.decks[from]
	local t = d.trackId and State.library().tracks[d.trackId]
	if State.settings().lights and d.playing and t and t.bpm then
		workspace:SetAttribute("HazaDJ_BPM", t.bpm * t.speed * (1 + d.pitch))
		workspace:SetAttribute("HazaDJ_BeatAt", d.at - (d.pos % (60 / t.bpm)))
	else
		workspace:SetAttribute("HazaDJ_BPM", 0)
	end
end

function Show.start()
	DjDeck.onLiveChanged(function(live)
		billboard()
		local name = nameOf(live)
		if live and name and State.settings().announce then
			Net.Toast.FireAll(name .. " is live")
		end
	end)
	-- now playing: when the deck the fader favours starts a new track
	local lastAnnounced: string? = nil
	Charm.subscribe(function()
		local s = State.session()
		local from = if s.xfader <= 0.5 then 1 else 2
		local d = s.decks[from]
		return if d.playing then d.trackId else nil
	end, function(id)
		if id and id ~= lastAnnounced and State.settings().nowPlaying then
			lastAnnounced = id
			local t = State.library().tracks[id]
			if t then
				Net.Toast.FireAll("Now playing  " .. t.title .. (if t.artist ~= "—" then " · " .. t.artist else ""))
			end
		end
	end)
	Charm.subscribe(State.settings, function()
		billboard()
		prompt()
	end)
	Charm.subscribe(State.session, beat)
	billboard()
	prompt()
	task.spawn(function()
		while true do
			task.wait(0.5)
			guardStand()
		end
	end)
end

return Show
