--!strict
-- The lock screen (ADR 0022): a full-bleed artwork panel with a compact form (one code field,
-- Activate, "Have a guest pass?" opening a sub-modal), the xfade mark on top and a copyright line.
-- An accepted code makes the panel rise with everything in it, then the decks are there. A guest pass
-- that ran out shows the same screen with a different title. Only the place owner ever sees it (nobody
-- else may open a locked DJ deck).
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
local Hover = require(script.Parent.Parent.UI.Hover)

local create, source, effect, untrack, cleanup = Vide.create, Vide.source, Vide.effect, Vide.untrack, Vide.cleanup
local C, W = Theme.C, Theme.W
local BLACK = Theme.BLACK
local BG = C.tile -- the deck's own surface, so the lock reads as part of the panel (owner, 2026-10-26)
local frame, label = Base.frame, Base.label

local Lock = {}

export type Props = {
	compact: () -> boolean, -- a small screen: no pass, the form at a readable size
	boost: () -> number, -- the form's extra scale in compact mode
	onClose: () -> (),
	onReveal: (() -> ())?, -- the panel starts to rise: the panel can bring its rows in
}

local CANVAS_W, CANVAS_H = 1250, 802
local FORM_W = 300
local FORM_H = 212 -- the form's height
local LOGO_TOP, LOGO_H = 40, 62 -- the xfade mark sits at the top of the right column
local COPY_TOP = CANVAS_H - 36 -- the copyright's top edge
local RIGHT_X = 937 -- centre of the right-hand column (the artwork fills the left)
local FORM_Y = math.floor((LOGO_TOP + LOGO_H + COPY_TOP) / 2) -- the form sits centred between the mark and the copyright
local ARTWORK = "rbxassetid://133559573964792"
local BTN_OVER = Color3.fromHex("dcdcdc")

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
		body = "Enter your activation code",
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
		TextXAlignment = Enum.TextXAlignment.Center,
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
		Hover.track(hover),
		Activated = function()
			if untrack(enabled) then
				onClick()
			end
		end,
		Base.corner(6),
	}) :: TextButton
end

function Lock.new(p: Props): Frame
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

	local code = source("")
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

	local shakeAt = -100
	local formShake = 0
	local function celebrate()
		celebrating(true)
		done(true)
		task.wait(0.8)
	end

	local root: Frame
	local formGroup: CanvasGroup
	local codeBox: TextBox
	-- ── the reveal to the decks (owner): the whole panel rises with everything in it, then the decks are
	-- there. In Studio, changing HazaDJ's UnlockPreview attribute replays it. ──
	local function flyAway()
		if p.onReveal then
			task.spawn(p.onReveal)
		end
		tween(root, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(-16, -CANVAS_H),
		})
		task.wait(0.7)
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
		root.Position = UDim2.fromOffset(-16, 0)
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
			Hover.track(hover),
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
		Size = UDim2.fromOffset(FORM_W, 16),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
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
	Hover.watch(guestLink, linkHover)
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
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			return if p.compact()
				then UDim2.fromOffset(CANVAS_W / 2, CANVAS_H / 2)
				else UDim2.fromOffset(RIGHT_X, FORM_Y)
		end,
		Size = UDim2.fromOffset(FORM_W + 4, FORM_H),
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
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.fromOffset(FORM_W, 0),
				TextXAlignment = Enum.TextXAlignment.Center,
				FontFace = Theme.B,
				TextSize = 26,
				LineHeight = 1.05,
				ZIndex = 62,
			}),
			label(function()
				return if done() then "The DJ deck is now live in every server of this game." else copy().body
			end, {
				AutomaticSize = Enum.AutomaticSize.None,
				Position = UDim2.fromOffset(0, 61),
				Size = UDim2.fromOffset(FORM_W, 34),
				FontFace = Theme.R,
				TextSize = 13,
				TextColor3 = C.soft,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				LineHeight = 1.25,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 62,
			}),
			frame({
				Position = UDim2.fromOffset(0, 105),
				Size = UDim2.fromOffset(FORM_W, 36),
				ZIndex = 62,
				Visible = function()
					return not wrongGame()
				end,
				codeField,
			}),
			frame({
				Position = UDim2.fromOffset(0, 149),
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
			frame({ Position = UDim2.fromOffset(0, 191), Size = UDim2.fromOffset(FORM_W, 16), ZIndex = 62, guestLink }),
			label(err, {
				Position = UDim2.fromOffset(0, 211),
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.fromOffset(FORM_W, 0),
				TextXAlignment = Enum.TextXAlignment.Center,
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
		Hover.track(closeHover),
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

	-- the xfade mark at the top of the right column (static props, so the compact-mode bindings never move it)
	local logo = frame({
		Name = "XfadeLogo",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(RIGHT_X, LOGO_TOP),
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 62,
		Visible = function()
			return not p.compact()
		end,
		Base.vlist(4, { HorizontalAlignment = Enum.HorizontalAlignment.Center }),
		label("xfade", {
			FontFace = Font.new(Theme.BRAND.Family, Enum.FontWeight.ExtraBold),
			TextSize = 19,
			LayoutOrder = 1,
			ZIndex = 62,
		}),
		frame({
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
			ZIndex = 62,
			Base.corner(2),
			Base.stroke(C.redText, 1),
			Base.pad(5, 5, 0, 0),
			label("DUAL DECK", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				FontFace = Theme.BRAND,
				TextSize = 12,
				TextColor3 = C.redText,
				ZIndex = 62,
			}),
		}),
		label("by kosmik", {
			FontFace = Theme.SB,
			TextSize = 12,
			TextTransparency = 0.5,
			LayoutOrder = 3,
			ZIndex = 62,
		}),
	})

	-- the copyright mark under the right column
	local copyright = label("© 2026 Cosmic Studio HQ", {
		Name = "Copyright",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(RIGHT_X, CANVAS_H - 20),
		Size = UDim2.fromOffset(FORM_W, 16),
		AutomaticSize = Enum.AutomaticSize.None,
		FontFace = Theme.R,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(150, 150, 150),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 62,
		Visible = function()
			return not p.compact()
		end,
	})

	-- the artwork fills the whole lock (the form, logo and copyright sit on top of it)
	local artwork = create("ImageLabel")({
		Name = "Artwork",
		BackgroundTransparency = 1,
		Image = ARTWORK,
		ScaleType = Enum.ScaleType.Crop,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 61,
	})

	root = Base.new("Frame", {
		Name = "Lock",
		Position = UDim2.fromOffset(-16, 0),
		Size = UDim2.fromOffset(CANVAS_W, CANVAS_H),
		BackgroundColor3 = BG,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
		ZIndex = 60,
		Active = true, -- clicks don't reach the panel underneath
		Visible = shown,
		Base.corner(4), -- the panel's corners (App)
		formGroup,
		logo,
		copyright,
		artwork,
		close,
		modal,
	}) :: Frame
	-- motion: a shake on a wrong code; only while it is on screen
	effect(function()
		if not shown() then
			return
		end
		local conn = RunService.RenderStepped:Connect(function()
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

	-- Studio only: replay the unlock without a code (see the reveal above)
	if RunService:IsStudio() then
		local replay = ReplicatedStorage.HazaDJ:GetAttributeChangedSignal("UnlockPreview"):Connect(function()
			if untrack(done) or not untrack(isOwner) then
				return
			end
			task.spawn(function()
				state("done")
				celebrate()
				flyAway()
			end)
		end)
		cleanup(function()
			replay:Disconnect()
		end)
	end

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
