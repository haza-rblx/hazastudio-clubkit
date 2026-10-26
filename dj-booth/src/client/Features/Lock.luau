--!strict
-- The lock screen (ADR 0022), as approved live in DJX Lite (owner, 2026-10-26): solid black, a stage
-- light on a hanging "BACKSTAGE PASS" lanyard, and a compact form (one code field, Activate, "Have a
-- guest pass?" opening a sub-modal). The pass prints the code as it is typed; an accepted code
-- stamps ACCESS GRANTED and pulls the pass up. A guest pass that ran out shows the same screen with
-- an EXPIRED stamp. Only the place owner ever sees it (nobody else may open a locked DJ deck). On a
-- small screen the pass is left out and the form is shown at a readable size.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local LicensePolicy = require(ReplicatedStorage.HazaDJ.Shared.LicensePolicy)
local Actions = require(script.Parent.Parent.Actions)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.UI.Base)

local create, source, effect, untrack, cleanup = Vide.create, Vide.source, Vide.effect, Vide.untrack, Vide.cleanup
local C, W = Theme.C, Theme.W
local BLACK = Theme.BLACK
local frame, label = Base.frame, Base.label

local Lock = {}

export type Props = {
	compact: () -> boolean, -- a small screen: no pass, the form at a readable size
	boost: () -> number, -- the form's extra scale in compact mode
	onClose: () -> (),
}

local CANVAS_W, CANVAS_H = 1250, 802
local PX = 400 -- the pass hangs at this x
local PIVOT_Y, STRAP, PASS_W, PASS_H = -40, 230, 300, 430
local FORM_W = 300
local INK2 = Color3.fromHex("d0d0d0") -- the perforation on the white pass
local BTN_OVER = Color3.fromHex("dcdcdc")

local function nseq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function tween(inst: Instance, info: TweenInfo, goal: { [string]: any })
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

-- what each locked state says (the field and Activate stay the same)
type Copy = { title: string, body: string, guest: boolean, band: string, corner: string, expired: boolean }
local COPY: { [string]: Copy } = {
	locked = {
		title = "Your DJ deck is\nwaiting backstage.",
		body = "Paste the code from your Hazastudio dashboard to unlock the decks in every server.",
		guest = true,
		band = "NOT ACTIVATED",
		corner = "BACKSTAGE PASS",
		expired = false,
	},
	expired = {
		title = "Your guest pass\nhas ended.",
		body = "Paste an activation code from your Hazastudio dashboard to keep the decks on.",
		guest = false,
		band = "PASS EXPIRED",
		corner = "GUEST PASS",
		expired = true,
	},
	denied = {
		title = "Your DJ deck is\nlocked.",
		body = "Hazastudio turned this license off. Paste a new code, or contact support.",
		guest = false,
		band = "LICENSE OFF",
		corner = "BACKSTAGE PASS",
		expired = false,
	},
	-- a download stamped for another game (the reason picks this copy under `denied`)
	wrongGame = {
		title = "This copy belongs\nto another game.",
		body = "Download your own djX from your Hazastudio account, then activate it here.",
		guest = false,
		band = "WRONG GAME",
		corner = "BACKSTAGE PASS",
		expired = false,
	},
	offline = {
		title = "Waiting for\nHazastudio.",
		body = "The license couldn't be confirmed for 7 days. Keep HTTP requests on; it unlocks once confirmed.",
		guest = false,
		band = "OFFLINE",
		corner = "BACKSTAGE PASS",
		expired = false,
	},
}

-- the barcode: bars drawn from a seed (the universe, or the code being typed)
local function printBars(holder: Frame, seed: number)
	holder:ClearAllChildren()
	local r = Random.new(seed)
	local x = 0
	while x < 252 do
		local w = r:NextInteger(1, 4)
		if r:NextNumber() > 0.35 then
			Base.new("Frame", {
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.fromOffset(math.min(w, 252 - x), 32),
				BackgroundColor3 = C.ink,
				ZIndex = 62,
				Parent = holder,
			})
		end
		x += w + r:NextInteger(1, 3)
	end
end

local function seedOf(text: string): number
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483647
	end
	return h
end

-- a code field: 36 px, corner 6, a white edge while focused, red on an error
local function field(
	placeholder: string,
	text: (string) -> any,
	bad: () -> boolean,
	onEnter: () -> ()
): (Frame, TextBox)
	local focused = source(false)
	local box = create("TextBox")({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = C.faint,
		TextColor3 = W,
		FontFace = Theme.SB,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		ZIndex = 62,
		Focused = function()
			focused(true)
		end,
		FocusLost = function(enter: boolean)
			focused(false)
			if enter then
				onEnter()
			end
		end,
	}) :: TextBox
	box:GetPropertyChangedSignal("Text"):Connect(function()
		text(box.Text)
	end)
	local f = Base.new("Frame", {
		Size = UDim2.fromOffset(FORM_W, 36),
		BackgroundColor3 = C.field,
		ZIndex = 62,
		Base.corner(6),
		Base.pad(12, 12, 0, 0),
		create("UIStroke")({
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Thickness = 1,
			Color = function()
				return if bad() then C.red else W
			end,
			Transparency = function()
				return if bad() then 0 elseif focused() then 0.6 else 1
			end,
		}),
		box,
	})
	return f, box
end

-- a 36 px primary button that greys out until it can be pressed
local function primary(text: () -> string, enabled: () -> boolean, onClick: () -> (), w: number?): TextButton
	local hover = source(false)
	return create("TextButton")({
		Size = UDim2.fromOffset(w or FORM_W, 36),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = text,
		FontFace = Theme.SB,
		TextSize = 13,
		ZIndex = 62,
		BackgroundColor3 = function()
			return if not enabled() then C.flat elseif hover() then BTN_OVER else W
		end,
		TextColor3 = function()
			return if enabled() then C.ink else C.faint
		end,
		MouseEnter = function()
			hover(true)
		end,
		MouseLeave = function()
			hover(false)
		end,
		Activated = function()
			if untrack(enabled) then
				onClick()
			end
		end,
		Base.corner(6),
	}) :: TextButton
end

function Lock.new(p: Props): Frame
	local player = Players.LocalPlayer
	local isOwner = function()
		return Store.me().role == "Owner"
	end
	local status = function(): string
		return Store.license().status
	end
	local celebrating = source(false)
	local shown = function()
		return isOwner() and (celebrating() or not LicensePolicy.unlocked(Store.license()))
	end
	local wrongGame = function(): boolean
		local reason = Store.license().reason
		return status() == "denied" and (reason == "universe_mismatch" or reason == "owner_mismatch")
	end
	local copy = function(): Copy
		if wrongGame() then
			return COPY.wrongGame
		end
		return COPY[status()] or COPY.locked
	end

	local gameName = source("This game")
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, game.PlaceId)
		if ok and type(info) == "table" and info.Name then
			gameName(info.Name)
		end
	end)

	-- ── the stage light ──
	local strips = {}
	for i = 0, 85 do
		table.insert(
			strips,
			Base.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, i * 10),
				Size = UDim2.fromOffset(math.floor(150 + i / 85 * 480), 10),
				BackgroundColor3 = W,
				BackgroundTransparency = 0.78,
				ZIndex = 61,
				Base.gradient({
					Transparency = nseq({ { 0, 1 }, { 0.25, 0.35 }, { 0.5, 0 }, { 0.75, 0.35 }, { 1, 1 } }),
				}),
			})
		)
	end
	local beam = create("CanvasGroup")({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(PX, -20),
		Size = UDim2.fromOffset(640, 860),
		BackgroundTransparency = 1,
		ZIndex = 61,
		Base.gradient({ Rotation = 90, Transparency = nseq({ { 0, 0.15 }, { 0.5, 0.55 }, { 0.85, 0.85 }, { 1, 1 } }) }),
		strips,
	}) :: CanvasGroup

	-- ── the pass on its lanyard (a frame twice the drop tall, so Rotation pivots at the hook) ──
	local L = STRAP + PASS_H
	local passTop = L + STRAP
	local strapPrint = {}
	for i = 0, 3 do
		table.insert(
			strapPrint,
			label("djX", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 36 + i * 56),
				Size = UDim2.fromOffset(60, 14),
				AutomaticSize = Enum.AutomaticSize.None,
				Rotation = 90,
				FontFace = Theme.BRAND,
				TextSize = 12,
				TextTransparency = 0.4,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 61,
			})
		)
	end

	local cornerLbl = label(function()
		return copy().corner
	end, {
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 12,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 62,
	})
	local bandL = label("OWNER ONLY", {
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.B,
		ZIndex = 62,
	})
	local band = Base.new("Frame", {
		Position = UDim2.fromOffset(-24, 150),
		Size = UDim2.new(1, 48, 0, 36),
		BackgroundColor3 = C.red,
		ZIndex = 62,
		Base.pad(24, 24, 0, 0),
		bandL,
		label(function()
			return copy().band
		end, {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromScale(1, 1),
			TextSize = 12,
			TextTransparency = 0.12,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 62,
		}),
	})
	local bars = frame({ Position = UDim2.fromOffset(0, 320), Size = UDim2.fromOffset(252, 32), ZIndex = 62 })
	printBars(bars, game.GameId % 100000)

	local function stamp(
		text: string,
		color: Color3,
		size: number,
		w: number,
		h: number
	): (Frame, UIScale, UIStroke, TextLabel)
		local s = create("UIScale")({ Scale = 1 }) :: UIScale
		local st = Base.stroke(color, 4)
		local t = label(text, {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromScale(1, 1),
			FontFace = Theme.B,
			TextSize = size,
			LineHeight = 0.9,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 64,
		})
		local f = Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 6, 0, 292),
			Size = UDim2.fromOffset(w, h),
			Rotation = -11,
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 64,
			Base.corner(6),
			st,
			s,
			t,
		})
		return f, s, st, t
	end
	local granted, grantedScale, grantedStroke, grantedText = stamp("ACCESS\nGRANTED", C.ok, 23, 188, 70)
	local expiredStamp = stamp("EXPIRED", C.red, 28, 168, 58)
	effect(function()
		expiredStamp.Visible = copy().expired and not celebrating()
	end)

	local code = source("")
	local caption = label(function()
		local c = code()
		return if c == "" then "UNIVERSE " .. tostring(game.GameId) else "CODE  " .. c
	end, {
		AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.fromOffset(0, 358),
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = 12,
		TextColor3 = function()
			return if code() == "" then C.dim else C.ink
		end,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 62,
	})
	-- the pass reprints its barcode from what is typed
	effect(function()
		local c = code()
		untrack(function()
			printBars(bars, if c == "" then game.GameId % 100000 else seedOf(c))
		end)
	end)

	local function row(y: number, title: string, value: any)
		return {
			label(title, { Position = UDim2.fromOffset(0, y), TextSize = 12, TextColor3 = C.dim, ZIndex = 62 }),
			label(value, {
				AutomaticSize = Enum.AutomaticSize.None,
				Position = UDim2.fromOffset(0, y + 16),
				Size = UDim2.new(1, 0, 0, 18),
				TextSize = 15,
				TextColor3 = C.ink,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 62,
			}),
		}
	end
	local perforation = {}
	for i = 0, 19 do
		table.insert(
			perforation,
			Base.new("Frame", {
				Position = UDim2.fromOffset(6 + i * 12, 302),
				Size = UDim2.fromOffset(6, 2),
				BackgroundColor3 = INK2,
				ZIndex = 62,
			})
		)
	end
	local notches = {}
	for _, ax in { 0, 1 } do
		table.insert(
			notches,
			Base.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(ax, if ax == 0 then -24 else 24, 0, 303),
				Size = UDim2.fromOffset(18, 18),
				BackgroundColor3 = BLACK,
				ZIndex = 63,
				Base.round(1),
			})
		)
	end

	local pass = Base.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, passTop),
		Size = UDim2.fromOffset(PASS_W, PASS_H),
		BackgroundColor3 = W,
		ZIndex = 62,
		Base.corner(10),
		-- the hole the clip goes through
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 16),
			Size = UDim2.fromOffset(64, 12),
			BackgroundColor3 = BLACK,
			ZIndex = 62,
			Base.round(1),
		}),
		frame({
			Position = UDim2.fromOffset(24, 46),
			Size = UDim2.new(1, -48, 1, -46),
			ZIndex = 62,
			label("djX DUAL DECK", { FontFace = Theme.BRAND, TextSize = 13, TextColor3 = C.ink, ZIndex = 62 }),
			cornerLbl,
			label("BACK\nSTAGE", {
				Position = UDim2.fromOffset(0, 34),
				FontFace = Theme.B,
				TextSize = 54,
				LineHeight = 0.88,
				TextColor3 = C.ink,
				ZIndex = 62,
			}),
			band,
			row(204, "GAME", gameName),
			row(248, "HOLDER", player.DisplayName .. "  ·  @" .. player.Name),
			notches,
			perforation,
			bars,
			caption,
		}),
		granted,
		expiredStamp,
	})
	local swing = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(PX, PIVOT_Y),
		Size = UDim2.fromOffset(PASS_W + 40, L * 2),
		ZIndex = 61,
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, L),
			Size = UDim2.fromOffset(34, STRAP + 6),
			BackgroundColor3 = C.red,
			ZIndex = 61,
			Base.new(
				"Frame",
				{ Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = W, BackgroundTransparency = 0.82, ZIndex = 61 }
			),
			Base.new("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 3, 1, 0),
				BackgroundColor3 = BLACK,
				BackgroundTransparency = 0.75,
				ZIndex = 61,
			}),
			strapPrint,
		}),
		-- the clip
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, L + STRAP - 22),
			Size = UDim2.fromOffset(46, 36),
			BackgroundColor3 = C.card2,
			ZIndex = 63,
			Base.corner(7),
			Base.stroke(C.raised, 2),
			Base.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.6),
				Size = UDim2.fromOffset(22, 6),
				BackgroundColor3 = C.raised,
				ZIndex = 63,
				Base.round(1),
			}),
		}),
		pass,
	})

	-- ── the form ──
	local state = source("idle") -- idle | error | checking | done
	local err = source("")
	local done = source(false)
	local function submit(kind: "Activate" | "RedeemGuest", text: string, onError: (string) -> ()): boolean
		local r = Actions.quiet({ Kind = kind, Code = text } :: any)
		if r.Ok then
			return true
		end
		onError(r.Message or "That code isn't valid.")
		return false
	end

	local wobbleAt = -100
	local shakeAt = -100
	local formShake = 0
	local function celebrate()
		celebrating(true)
		done(true)
		granted.Visible = true
		grantedScale.Scale = 1.9
		grantedText.TextTransparency = 1
		grantedStroke.Transparency = 1
		tween(grantedScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		tween(grantedText, TweenInfo.new(0.12), { TextTransparency = 0 })
		tween(grantedStroke, TweenInfo.new(0.12), { Transparency = 0 })
		task.wait(0.2)
		wobbleAt = os.clock()
		tween(band, TweenInfo.new(0.25), { BackgroundColor3 = C.ok })
		bandL.Text = "ALL ACCESS"
		task.wait(1.2)
	end

	local root: Frame
	local formGroup: CanvasGroup
	local codeBox: TextBox
	local function flyAway()
		tween(swing, TweenInfo.new(0.7, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(PX, PIVOT_Y - 1000),
		})
		tween(beam, TweenInfo.new(0.5), { GroupTransparency = 1 })
		tween(formGroup, TweenInfo.new(0.5), { GroupTransparency = 1 })
		task.wait(0.45)
		tween(root, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
		task.wait(0.55)
		-- wait for the server's licence to land so the lock doesn't flash back
		local t0 = os.clock()
		while not LicensePolicy.unlocked(untrack(Store.license)) and os.clock() - t0 < 5 do
			task.wait(0.1)
		end
		celebrating(false)
		done(false)
		state("idle")
		codeBox.Text = "" -- the box drives `code`; clearing only the source would leave its text up
		code("")
		granted.Visible = false
		band.BackgroundColor3 = C.red
		bandL.Text = "OWNER ONLY"
		swing.Position = UDim2.fromOffset(PX, PIVOT_Y)
		beam.GroupTransparency = 0
		formGroup.GroupTransparency = 0
		root.BackgroundTransparency = 0
	end

	local function activate()
		local c = untrack(code)
		if untrack(state) == "checking" or untrack(done) or (string.gsub(c, "%s", "")) == "" then
			return
		end
		state("checking")
		task.spawn(function()
			local ok = submit("Activate", c, function(message)
				err(message)
				state("error")
				wobbleAt = os.clock()
				shakeAt = os.clock()
			end)
			if ok then
				state("done")
				celebrate()
				flyAway()
			end
		end)
	end

	local codeField
	codeField, codeBox = field("Activation code", code, function()
		return state() == "error"
	end, activate)
	effect(function()
		code()
		untrack(function()
			if untrack(state) == "error" then
				state("idle")
				err("")
			end
		end)
	end)

	-- the guest pass sub-modal
	local guestOpen = source(false)
	local guestCode = source("")
	local guestState = source("idle")
	local guestErr = source("")
	local function redeem()
		local c = untrack(guestCode)
		if untrack(guestState) == "checking" or (string.gsub(c, "%s", "")) == "" then
			return
		end
		guestState("checking")
		task.spawn(function()
			local ok = submit("RedeemGuest", c, function(message)
				guestErr(message)
				guestState("error")
			end)
			if ok then
				guestState("idle")
				guestOpen(false)
				code(c)
				state("done")
				celebrate()
				flyAway()
			end
		end)
	end

	local guestField, guestBox = field("Guest pass code", guestCode, function()
		return guestState() == "error"
	end, redeem)
	effect(function()
		guestCode()
		untrack(function()
			if untrack(guestState) == "error" then
				guestState("idle")
				guestErr("")
			end
		end)
	end)
	guestField.Size = UDim2.new(1, 0, 0, 36)

	local function secondary(text: string, onClick: () -> ()): TextButton
		local hover = source(false)
		return create("TextButton")({
			Size = UDim2.fromOffset(84, 32),
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Text = text,
			FontFace = Theme.SB,
			TextSize = 13,
			TextColor3 = W,
			ZIndex = 102,
			LayoutOrder = 1,
			BackgroundColor3 = function()
				return if hover() then Color3.fromHex("3f3f3f") else C.card2
			end,
			MouseEnter = function()
				hover(true)
			end,
			MouseLeave = function()
				hover(false)
			end,
			Activated = onClick,
			Base.corner(6),
		}) :: TextButton
	end

	local modalScale = create("UIScale")({ Scale = 0.96 }) :: UIScale
	local redeemBtn = primary(function()
		return if guestState() == "checking" then "Checking…" else "Redeem"
	end, function()
		return guestState() ~= "checking" and (string.gsub(guestCode(), "%s", "")) ~= ""
	end, redeem, 96)
	redeemBtn.Size = UDim2.fromOffset(96, 32)
	redeemBtn.ZIndex = 102
	redeemBtn.LayoutOrder = 2
	for _, d in guestField:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 102
		end
	end
	guestField.ZIndex = 102
	local modal = create("TextButton")({
		Name = "GuestPass",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 100,
		Visible = guestOpen,
		Activated = function()
			guestOpen(false)
		end,
		Base.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(360, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.raised,
			Active = true,
			ZIndex = 101,
			Base.corner(8),
			Base.stroke(C.line, 1),
			modalScale,
			Base.pad(20, 20, 20, 20),
			Base.vlist(8),
			label("Redeem a guest pass", { FontFace = Theme.B, TextSize = 16, LayoutOrder = 1, ZIndex = 102 }),
			label("Got a guest pass from Hazastudio? Paste its code to unlock the decks.", {
				FontFace = Theme.R,
				TextSize = 13,
				TextColor3 = C.soft,
				TextWrapped = true,
				LineHeight = 1.25,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				LayoutOrder = 2,
				ZIndex = 102,
			}),
			frame({ Size = UDim2.new(1, 0, 0, 4), LayoutOrder = 3 }),
			frame({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 4, ZIndex = 102, guestField }),
			label(guestErr, {
				TextSize = 12,
				FontFace = Theme.R,
				TextColor3 = C.redText,
				LayoutOrder = 5,
				ZIndex = 102,
				Visible = function()
					return guestErr() ~= ""
				end,
			}),
			frame({
				Size = UDim2.new(1, 0, 0, 44),
				LayoutOrder = 6,
				ZIndex = 102,
				frame({
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.fromScale(1, 1),
					Size = UDim2.fromOffset(0, 32),
					AutomaticSize = Enum.AutomaticSize.X,
					ZIndex = 102,
					Base.hlist(8, Enum.HorizontalAlignment.Right),
					secondary("Cancel", function()
						guestOpen(false)
					end),
					redeemBtn,
				}),
			}),
		}),
	}) :: TextButton
	effect(function()
		if guestOpen() then
			untrack(function()
				guestBox.Text = ""
				guestErr("")
				guestState("idle")
				local k = if p.compact() then p.boost() else 1
				modalScale.Scale = 0.96 * k
				tween(modalScale, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = k })
			end)
		end
	end)

	local guestLink = create("TextButton")({
		Name = "GuestLink",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Theme.SB,
		TextSize = 12,
		Text = "Have a guest pass?",
		ZIndex = 62,
		Visible = function()
			return copy().guest and not done()
		end,
		Activated = function()
			guestOpen(true)
		end,
	}) :: TextButton
	local linkHover = source(false)
	guestLink.MouseEnter:Connect(function()
		linkHover(true)
	end)
	guestLink.MouseLeave:Connect(function()
		linkHover(false)
	end)
	effect(function()
		guestLink.TextColor3 = if linkHover() then W else C.dim
	end)

	local formScale = create("UIScale")({
		Scale = function()
			return if p.compact() then p.boost() else 1
		end,
	})
	formGroup = create("CanvasGroup")({
		BackgroundTransparency = 1,
		AnchorPoint = function()
			return if p.compact() then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5)
		end,
		Position = function()
			return if p.compact() then UDim2.fromOffset(CANVAS_W / 2, CANVAS_H / 2) else UDim2.fromOffset(718, 411)
		end,
		Size = UDim2.fromOffset(FORM_W + 4, 254),
		ZIndex = 62,
		formScale,
		-- 2 px of room so the field's outer edge isn't clipped by the group
		frame({
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 62,
			label(function()
				return if done() then "You're in.\nThe decks are yours." else copy().title
			end, {
				FontFace = Theme.B,
				TextSize = 26,
				LineHeight = 1.05,
				ZIndex = 62,
			}),
			label(function()
				return if done() then "The DJ deck is now live in every server of this game." else copy().body
			end, {
				AutomaticSize = Enum.AutomaticSize.None,
				Position = UDim2.fromOffset(0, 66),
				Size = UDim2.fromOffset(FORM_W, 34),
				FontFace = Theme.R,
				TextSize = 13,
				TextColor3 = C.soft,
				TextWrapped = true,
				LineHeight = 1.25,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 62,
			}),
			frame({
				Position = UDim2.fromOffset(0, 120),
				Size = UDim2.fromOffset(FORM_W, 36),
				ZIndex = 62,
				Visible = function()
					return not wrongGame()
				end,
				codeField,
			}),
			frame({
				Position = UDim2.fromOffset(0, 164),
				Size = UDim2.fromOffset(FORM_W, 36),
				ZIndex = 62,
				Visible = function()
					return not wrongGame()
				end,
				primary(function()
					local s = state()
					return if done() then "Open the decks" elseif s == "checking" then "Checking…" else "Activate"
				end, function()
					return done() or (state() ~= "checking" and (string.gsub(code(), "%s", "")) ~= "")
				end, activate),
			}),
			frame({ Position = UDim2.fromOffset(0, 210), Size = UDim2.fromOffset(FORM_W, 16), ZIndex = 62, guestLink }),
			label(err, {
				Position = UDim2.fromOffset(0, 234),
				TextSize = 12,
				FontFace = Theme.R,
				TextColor3 = C.redText,
				ZIndex = 62,
				Visible = function()
					return err() ~= ""
				end,
			}),
		}),
	}) :: CanvasGroup

	-- the header's own close capsule, in the same spot
	local closeHover = source(false)
	local close = create("TextButton")({
		Name = "Close",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 6),
		Size = UDim2.fromOffset(28, 28),
		ZIndex = 66,
		BackgroundColor3 = function()
			return if closeHover() then C.red else C.field
		end,
		MouseEnter = function()
			closeHover(true)
		end,
		MouseLeave = function()
			closeHover(false)
		end,
		Activated = p.onClose,
		Base.corner(4),
		-- on a phone the panel is scaled down; the close keeps a finger-sized target
		create("UIScale")({
			Scale = function()
				return if p.compact() then p.boost() else 1
			end,
		}),
	}) :: TextButton
	effect(function()
		local g = close:FindFirstChild("Glyph")
		if g then
			g:Destroy()
		end
		local glyph = Base.glyph("cross", 12, if closeHover() then W else C.soft)
		for _, b in glyph:GetDescendants() do
			if b:IsA("GuiObject") then
				b.ZIndex = 66
			end
		end
		glyph.ZIndex = 66
		glyph.Parent = close
	end)

	root = Base.new("Frame", {
		Name = "Lock",
		Position = UDim2.fromOffset(-16, 0),
		Size = UDim2.fromOffset(CANVAS_W, CANVAS_H),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
		ZIndex = 60,
		Active = true, -- clicks don't reach the panel underneath
		Visible = shown,
		beam,
		swing,
		formGroup,
		close,
		modal,
	}) :: Frame
	effect(function()
		local compact = p.compact()
		beam.Visible = not compact
		swing.Visible = not compact
	end)

	-- motion: sway, a lean toward the cursor, a shake on a wrong code; only while it is on screen
	effect(function()
		if not shown() then
			return
		end
		local t0 = os.clock()
		local tilt = 0
		local conn = RunService.RenderStepped:Connect(function(dt: number)
			local t = os.clock() - t0
			local m = UserInputService:GetMouseLocation()
			local c = pass.AbsolutePosition + pass.AbsoluteSize / 2
			local want = if (m - c).Magnitude < 420 * (root.AbsoluteSize.X / CANVAS_W)
				then math.clamp((m.X - c.X) / 160, -1, 1) * -3
				else 0
			tilt += (want - tilt) * math.min(1, dt * 4)
			local w = os.clock() - wobbleAt
			local wobble = if w < 0.8 then math.sin(w * 32) * 5 * math.exp(-w * 5) else 0
			local flying = untrack(done) and swing.Position.Y.Offset < PIVOT_Y - 1
			swing.Rotation = (if flying then 0 else math.sin(t * 1.1) * 2 + tilt) + wobble
			local e = os.clock() - shakeAt
			local dx = if e < 0.45 then math.sin(e * 48) * 7 * (1 - e / 0.45) else 0
			if dx ~= formShake then
				formShake = dx
				codeField.Position = UDim2.fromOffset(dx, 0)
			end
		end)
		cleanup(function()
			conn:Disconnect()
		end)
	end)

	-- Esc closes the guest pass sub-modal
	local esc = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and untrack(guestOpen) then
			guestOpen(false)
		end
	end)
	cleanup(function()
		esc:Disconnect()
	end)
	return root
end

return Lock
