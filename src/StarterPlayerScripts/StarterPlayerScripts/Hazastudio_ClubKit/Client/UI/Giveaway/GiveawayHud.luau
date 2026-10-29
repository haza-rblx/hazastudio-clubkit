--!strict
-- Client/UI/Giveaway/GiveawayHud.luau
-- Giveaway HUD for every player: the hourly card at the top of the screen (title + minimise,
-- prize, countdown or live state, players, requirement footer) and the winner toast with the reel
-- of headshots that lands on the winner. The winner cinematic is GiveawayWinFx. Styling: KitLook.
-- Layout constants and copy are the approved prototype values.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent.Parent
local KitLook = require(Client.UI.KitLook)
local AccentSurfaceTint = require(Client.Services.AccentSurfaceTint)
local GiveawayWinFx = require(script.Parent.GiveawayWinFx)

local LOG = "[Giveaway]"
local EDGE = 12
local CARD_W = 248
local TOAST_W, TOAST_H = 320, 182
local REEL_H = 92
local TILE_SPACING = 110
local TILE_SMALL, TILE_BIG = 52, 76
local WINNER_HOLD = 8
local TOAST_HOLD = 6
local LAPS = 3

export type HudState = {
	phase: string,
	nextAt: number,
	count: number,
	min: number,
	anchor: string,
	prize: string,
	enabled: boolean,
	interval: number,
	spinDuration: number,
	winFxVariant: number,
}

type Entry = { userId: number, displayName: string, username: string, fake: boolean }

local GiveawayHud = {}

-- state is the controller's table (updated in place); the HUD only reads it.
function GiveawayHud.new(playerGui: PlayerGui, state: HudState)
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "GiveawayHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = playerGui
	pcall(AccentSurfaceTint.attach, gui)

	local COLOR = KitLook.COLOR
	local lastWinner = ""
	local minimised = false
	local winnerName = ""
	local winnerUntil = 0
	local toastToken = 0
	local tiles: { ImageLabel } = {}
	local spin: any = { active = false }
	local lastPill = 0
	local lastLayoutKey = ""
	local lastCopy = ""
	local hasState = false

	local function topY(): number
		return GuiService:GetGuiInset().Y + 8
	end

	local function placeTop(frame: GuiObject, anchor: string, y: number)
		if anchor == "TopLeft" then
			frame.AnchorPoint = Vector2.new(0, 0)
			frame.Position = UDim2.fromOffset(EDGE, y)
		elseif anchor == "TopRight" then
			frame.AnchorPoint = Vector2.new(1, 0)
			frame.Position = UDim2.new(1, -EDGE, 0, y)
		else
			frame.AnchorPoint = Vector2.new(0.5, 0)
			frame.Position = UDim2.new(0.5, 0, 0, y)
		end
	end

	-- ============================================================
	-- Pill
	-- ============================================================
	-- Card = 1 Header + 1 Body (check-in popup split corners). Layout from the client reference:
	-- title + minimise, prize, "Next giveaway in", big clock | players, requirement footer.
	local pill = KitLook.box(gui, "Card", UDim2.fromOffset(CARD_W, 0), 0, nil)
	pill.AutomaticSize = Enum.AutomaticSize.Y
	pill.Visible = false -- shown once the server state arrives
	KitLook.list(pill, Enum.FillDirection.Vertical, 2)
	KitLook.shadow(pill)

	local header = KitLook.box(pill, "Header", UDim2.new(1, 0, 0, 34), 1, COLOR.header)
	local headerCorner = KitLook.splitCorner(header, 14, 4)
	KitLook.padding(header, 12, 0, 6, 0)
	local titleLabel = KitLook.text(header, "HOURLY GIVEAWAY", 13, Enum.FontWeight.Bold, COLOR.white, 0, { truncate = true })
	titleLabel.Size = UDim2.new(1, -60, 1, 0)
	local miniClock = KitLook.text(header, "", 13, Enum.FontWeight.SemiBold, COLOR.sub, 0, { truncate = true, align = Enum.TextXAlignment.Right })
	miniClock.AnchorPoint = Vector2.new(1, 0)
	miniClock.Position = UDim2.new(1, -30, 0, 0)
	miniClock.Size = UDim2.new(0, 60, 1, 0)
	local minButton = Instance.new("TextButton")
	minButton.Name = "Minimise"
	minButton.AutoButtonColor = false
	minButton.AnchorPoint = Vector2.new(1, 0.5)
	minButton.Position = UDim2.new(1, 0, 0.5, 0)
	minButton.Size = UDim2.fromOffset(24, 24)
	minButton.BackgroundColor3 = COLOR.closeDisc
	minButton.BorderSizePixel = 0
	minButton.Text = "–"
	minButton.TextSize = 16
	minButton.FontFace = KitLook.font(Enum.FontWeight.Bold)
	minButton.TextColor3 = COLOR.closeGlyph
	KitLook.corner(minButton, UDim.new(1, 0))
	minButton.Parent = header

	local body = KitLook.box(pill, "Body", UDim2.new(1, 0, 0, 0), 2, COLOR.body)
	body.AutomaticSize = Enum.AutomaticSize.Y
	KitLook.splitCorner(body, 4, 14)
	KitLook.padding(body, 12, 10, 12, 12)
	KitLook.list(body, Enum.FillDirection.Vertical, 2)

	local topLine = KitLook.text(body, "", 15, Enum.FontWeight.Bold, COLOR.white, 1, { truncate = true })
	local captionLine = KitLook.text(body, "Next giveaway in", 13, Enum.FontWeight.SemiBold, COLOR.sub, 2, { truncate = true })
	local clockRow = KitLook.box(body, "ClockRow", UDim2.new(1, 0, 0, 34), 3, nil)
	local bottomLine = KitLook.text(clockRow, "", 28, Enum.FontWeight.Bold, COLOR.white, 0, { truncate = true })
	bottomLine.Size = UDim2.new(0.62, 0, 1, 0)
	local playersLine = KitLook.text(clockRow, "", 14, Enum.FontWeight.SemiBold, COLOR.white, 0, { truncate = true, align = Enum.TextXAlignment.Right })
	playersLine.AnchorPoint = Vector2.new(1, 0)
	playersLine.Position = UDim2.fromScale(1, 0)
	playersLine.Size = UDim2.new(0.38, 0, 1, 0)

	local bar = KitLook.box(body, "Bar", UDim2.new(1, 0, 0, 4), 4, COLOR.header)
	KitLook.corner(bar, UDim.new(1, 0))
	local barFill = KitLook.box(bar, "Fill", UDim2.fromScale(0, 1), 0, COLOR.white)
	KitLook.corner(barFill, UDim.new(1, 0))

	local footLine = KitLook.text(body, "", 13, Enum.FontWeight.SemiBold, COLOR.sub, 5, { truncate = true })

	-- Creative touches (kit colours only): live dot in the header, shimmer on the bar fill,
	-- rotating footer (requirement / last winner).
	local liveDot = KitLook.box(header, "LiveDot", UDim2.fromOffset(6, 6), 0, COLOR.white)
	liveDot.AnchorPoint = Vector2.new(0, 0.5)
	liveDot.Position = UDim2.new(0, 0, 0.5, 0)
	KitLook.corner(liveDot, UDim.new(1, 0))
	titleLabel.Position = UDim2.fromOffset(12, 0)
	TweenService:Create(liveDot, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		BackgroundTransparency = 0.75,
	}):Play()

	local shimmer = Instance.new("UIGradient")
	shimmer.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	shimmer.Offset = Vector2.new(-1, 0)
	shimmer.Parent = barFill
	TweenService:Create(shimmer, TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		Offset = Vector2.new(1, 0),
	}):Play()

	minButton.Activated:Connect(function()
		minimised = not minimised
		body.Visible = not minimised
		minButton.Text = if minimised then "+" else "–"
		-- Collapsed header stands alone: same radius top and bottom.
		local bottom = UDim.new(0, if minimised then 14 else 4)
		pcall(function()
			local c = headerCorner :: any
			c.BottomLeftRadius = bottom
			c.BottomRightRadius = bottom
		end)
	end)

	-- ============================================================
	-- Toast
	-- ============================================================
	local toast = Instance.new("CanvasGroup")
	toast.Name = "Toast"
	toast.Size = UDim2.fromOffset(TOAST_W, TOAST_H)
	toast.BackgroundColor3 = COLOR.panel
	toast.BorderSizePixel = 0
	toast.GroupTransparency = 1
	toast.Visible = false
	toast.Parent = gui
	KitLook.corner(toast, UDim.new(0, 24))
	KitLook.shadow(toast)
	local hudScale = Instance.new("UIScale")
	hudScale.Parent = pill
	local toastScale = Instance.new("UIScale")
	toastScale.Parent = toast

	local reel = KitLook.box(toast, "Reel", UDim2.new(1, 0, 0, REEL_H), 0, nil)
	reel.Position = UDim2.fromOffset(0, 20)
	reel.ClipsDescendants = true

	local nameLabel = KitLook.text(toast, "", 20, Enum.FontWeight.Bold, COLOR.white, 0, { truncate = true, align = Enum.TextXAlignment.Center })
	nameLabel.Position = UDim2.fromOffset(16, 122)
	nameLabel.Size = UDim2.new(1, -32, 0, 24)
	nameLabel.TextTransparency = 1

	local userLabel = KitLook.text(toast, "", 14, Enum.FontWeight.Medium, COLOR.sub, 0, { truncate = true, align = Enum.TextXAlignment.Center })
	userLabel.Position = UDim2.fromOffset(16, 148)
	userLabel.Size = UDim2.new(1, -32, 0, 18)
	userLabel.TextTransparency = 1

	local function setToastVisible(show: boolean)
		toastToken += 1
		local token = toastToken
		if show then
			toast.Visible = true
			local toastY = if state.anchor == "TopCenter" then topY() + pill.AbsoluteSize.Y + 10 else topY()
			-- Clear the winner cinematic's letterbox band (10% of the screen) so the card is never cut.
			toastY = math.max(toastY, gui.AbsoluteSize.Y * 0.1 + 16)
			toast.Position = UDim2.new(0.5, 0, 0, toastY - 24)
			TweenService:Create(toast, TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				GroupTransparency = 0,
				Position = UDim2.new(0.5, 0, 0, toastY),
			}):Play()
		else
			local t = TweenService:Create(toast, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				GroupTransparency = 1,
			})
			t:Play()
			t.Completed:Connect(function()
				if token == toastToken then
					toast.Visible = false
				end
			end)
		end
	end

	local function clearReel()
		for _, t in ipairs(tiles) do
			t:Destroy()
		end
		table.clear(tiles)
	end

	local function buildReel(pool: { Entry })
		clearReel()
		for i, entry in ipairs(pool) do
			local face = KitLook.headshot(reel, entry.userId, TILE_SMALL, i)
			face.AnchorPoint = Vector2.new(0.5, 0.5)
			face.Position = UDim2.fromOffset(TOAST_W / 2, REEL_H / 2)
			local ring = Instance.new("UIStroke")
			ring.Color = COLOR.white
			ring.Thickness = 3
			ring.Transparency = 1
			ring.Parent = face
			table.insert(tiles, face)
		end
	end

	local function layoutReel(p: number)
		local n = #tiles
		if n == 0 then
			return
		end
		for j, face in ipairs(tiles) do
			local o = (j - 1) - p
			o = o - n * math.floor(o / n + 0.5)
			local w = math.clamp(1 - math.abs(o), 0, 1)
			local size = TILE_SMALL + (TILE_BIG - TILE_SMALL) * w
			face.Visible = math.abs(o) <= 1.6
			face.Size = UDim2.fromOffset(size, size)
			face.Position = UDim2.fromOffset(TOAST_W / 2 + o * TILE_SPACING, REEL_H / 2)
			face.ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(70, 70, 70), 1 - w)
			local ring = face:FindFirstChildOfClass("UIStroke")
			if ring then
				ring.Transparency = 1 - w
			end
			face.ZIndex = 1 + math.floor(w * 10)
		end
	end

	local function fadeText(label: TextLabel, text: string)
		label.Text = text
		label.TextTransparency = 1
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
	end

	local function castWinner(entry: Entry)
		task.spawn(function()
			if spin.winFxVariant ~= 0 then
				local character: Model? = nil
				if not entry.fake then
					local wp = Players:GetPlayerByUserId(entry.userId)
					character = wp and wp.Character or nil
				end
				character = character or player.Character
				if character then
					local okWin, errWin = pcall(function()
						GiveawayWinFx.play(spin.winFxVariant, character)
					end)
					if not okWin then
						warn(LOG .. " WinFx.play failed: " .. tostring(errWin))
					end
				else
					warn(LOG .. " no character for WinFx")
				end
			end
		end)
	end

	local function beginSpin(payload: any)
		if type(payload) ~= "table" or type(payload.pool) ~= "table" or #payload.pool == 0 then
			return
		end
		spin = {
			active = true,
			pool = payload.pool,
			winnerIndex = payload.winnerIndex,
			startAt = payload.startAt,
			duration = payload.duration,
			winFxVariant = payload.winFxVariant,
			landed = false,
		}
		buildReel(payload.pool)
		layoutReel(0)
		-- While spinning the reel sits in the vertical centre of the card; it rises on landing
		-- to make room for the name.
		reel.Position = UDim2.fromOffset(0, (TOAST_H - REEL_H) / 2)
		nameLabel.Text = ""
		userLabel.Text = ""
		nameLabel.TextTransparency = 1
		userLabel.TextTransparency = 1
		setToastVisible(true)
	end

	local function land()
		spin.landed = true
		spin.active = false
		local entry: Entry = spin.pool[spin.winnerIndex]
		layoutReel((spin.winnerIndex - 1) + LAPS * #spin.pool)
		winnerName = entry.displayName
		winnerUntil = os.clock() + WINNER_HOLD
		TweenService:Create(reel, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 20),
		}):Play()
		fadeText(nameLabel, entry.displayName)
		fadeText(userLabel, "@" .. entry.username)
		castWinner(entry)
		local token = toastToken
		task.delay(TOAST_HOLD, function()
			if token == toastToken and not spin.active then
				setToastVisible(false)
			end
		end)
	end

	local function updateReel(now: number)
		local u = math.clamp((now - spin.startAt) / spin.duration, 0, 1)
		if u >= 1 then
			if not spin.landed then
				land()
			end
			return
		end
		if u <= 0 then
			return
		end
		local n = #spin.pool
		local f = 1 - (1 - u) ^ 3
		local travel = (spin.winnerIndex - 1) + LAPS * n
		layoutReel(f * travel)
	end

	-- ============================================================
	-- Pill text + bar
	-- ============================================================
	-- (caption, big line, mini clock for the minimised header)
	local function pillCopy(now: number): (string, string, string)
		if spin.active or state.phase == "spinning" then
			return "Giveaway is live", "Drawing…", "LIVE"
		end
		if os.clock() < winnerUntil then
			return "Winner", winnerName, "WON"
		end
		if state.phase == "waiting" then
			return "Starts when the server is full", "Waiting", string.format("%d/%d", state.count, state.min)
		end
		local clock = KitLook.clock(state.nextAt - now)
		return "Next giveaway in", clock, clock
	end

	local function applyLayout()
		-- Phones: the card and toast shrink with the viewport (toast goes smaller still).
		local view = gui.AbsoluteSize
		local k = math.min(view.X / 1100, view.Y / 620)
		hudScale.Scale = math.clamp(k, 0.8, 1)
		toastScale.Scale = math.clamp(k, 0.68, 1)
		local y = topY()
		local cardH = pill.AbsoluteSize.Y
		local key = state.anchor .. "|" .. tostring(y) .. "|" .. tostring(cardH) .. "|" .. tostring(view)
		if key == lastLayoutKey then
			return
		end
		lastLayoutKey = key
		placeTop(pill, state.anchor, y)
		-- Toast always sits top-centre; below the card only when the card is centred too.
		toast.AnchorPoint = Vector2.new(0.5, 0)
		if not spin.active then
			local toastY = if state.anchor == "TopCenter" then y + cardH + 10 else y
			toastY = math.max(toastY, gui.AbsoluteSize.Y * 0.1 + 16)
			toast.Position = UDim2.new(0.5, 0, 0, toastY)
		end
	end

	local function updatePill(now: number)
		local caption, big, mini = pillCopy(now)
		local top = "Prize: " .. state.prize .. " R$"
		local players = string.format("%d/%d players", state.count, state.min)
		local foot
		if lastWinner ~= "" and math.floor(os.clock() / 5) % 2 == 1 then
			foot = "Last winner · " .. lastWinner
		elseif state.count >= state.min then
			foot = "Server is full · giveaway is on"
		else
			foot = string.format("Needs %d+ players · %d more to go", state.min, state.min - state.count)
		end
		-- Final 10 seconds: the big clock blinks to pull attention.
		local remaining = state.nextAt - now
		local urgent = state.phase == "counting" and remaining <= 10 and remaining > 0 and not spin.active
		bottomLine.TextTransparency = if urgent and (os.clock() % 1) > 0.5 then 0.45 else 0
		if os.clock() < winnerUntil then
			lastWinner = winnerName
		end
		local key = top .. caption .. big .. mini .. players .. foot
		if key ~= lastCopy then
			lastCopy = key
			topLine.Text = top
			captionLine.Text = caption
			bottomLine.Text = big
			miniClock.Text = mini
			playersLine.Text = players
			footLine.Text = foot
		end
		miniClock.Visible = minimised
		bar.Visible = hasState and state.phase ~= "spinning" and not spin.active
		barFill.Size = UDim2.fromScale(math.clamp(state.count / math.max(state.min, 1), 0, 1), 1)
		applyLayout()
	end

	local HUD = {}

	-- Called on every server state snapshot.
	function HUD.refresh()
		hasState = true
		pill.Visible = state.enabled
		applyLayout()
	end

	function HUD.beginSpin(payload: any)
		beginSpin(payload)
	end

	function HUD.isSpinning(): boolean
		return spin.active == true
	end

	-- Render loop (every frame). The countdown is local; no per-second remote.
	function HUD.update(now: number)
		if os.clock() - lastPill >= 0.2 or spin.active then
			lastPill = os.clock()
			updatePill(now)
		end
		if spin.active then
			local okReel, errReel = pcall(updateReel, now)
			if not okReel then
				warn(LOG .. " reel error: " .. tostring(errReel))
				spin.active = false
			end
		end
	end

	function HUD.destroy()
		gui:Destroy()
	end

	return HUD
end

return GiveawayHud
