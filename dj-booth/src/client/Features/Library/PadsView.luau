--!strict
-- The Library's Pads view (937 | 311): the 4 x 2 pad grid and the Sounds list on the left, the
-- selected pad's editor on the right. Sounds preview locally; edits go to the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Vide = require(ReplicatedStorage.CosmicDJ.Packages.Vide)
local Shared = ReplicatedStorage.CosmicDJ.Shared
local Defaults = require(Shared.Defaults)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local Actions = require(script.Parent.Parent.Parent.Actions)
local Store = require(script.Parent.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.Parent.UI.Base)
local Hover = require(script.Parent.Parent.Parent.UI.Hover)
local Controls = require(script.Parent.Parent.Parent.UI.Controls)
local Covers = require(script.Parent.Parent.Parent.UI.Covers)
local Layout = require(script.Parent.Parent.Parent.UI.Layout)
local State = require(script.Parent.State)

local create, source, untrack = Vide.create, Vide.source, Vide.untrack
local C, W, B, R = Theme.C, Theme.W, Theme.B, Theme.R
local frame, label, fixed, caption, corner = Base.frame, Base.label, Base.fixed, Base.caption, Base.corner

local PadsView = {}

local PAGE_H = Theme.PAGE_H
local PW, PH, GAP = 142, 60, 8
local GRID_H = 56 + PH * 2 + GAP + 16

-- one local preview Sound for the sounds list and the editor
local preview = Instance.new("Sound")
preview.Name = "CosmicDJ_Preview"
preview.Volume = 0.6
preview.Parent = SoundService

local function soundById(lib: Types.Library, id: string?): Types.Sound?
	for _, s in lib.sounds do
		if s.id == id then
			return s
		end
	end
	return nil
end

local function padCaption(lib: Types.Library, p: Types.Pad): string
	if p.kind == "sfx" then
		local s = soundById(lib, p.sound)
		return "SFX · " .. (if s then s.name else "no sound")
	end
	return "World · " .. (Defaults.EFFECTS[p.effect or 1] or "")
end

-- the pad tile (as the deck pad row): name and what it plays at the bottom, a cooldown chip top-right
local function padFace(lib: Types.Library, p: Types.Pad, w: number, h: number, props: Base.Props?): TextButton
	if not p.kind then
		return create("TextButton")(Base.with({
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = C.field,
			Base.frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				AutomaticSize = Enum.AutomaticSize.XY,
				Base.hlist(6, Enum.HorizontalAlignment.Center),
				Base.frame({ Size = UDim2.fromOffset(10, 10), LayoutOrder = 1, Base.glyph("plus", 10, C.faint) }),
				label("Assign", { TextSize = 13, TextColor3 = C.faint, LayoutOrder = 2 }),
			}),
		}, props))
	end
	return create("TextButton")(Base.with({
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = C.field,
		fixed(if p.label ~= "" then p.label else "Untitled", 14, 11, w - 28, 18, { FontFace = B, TextSize = 14 }),
		fixed(padCaption(lib, p), 14, 31, w - 66, 16, { FontFace = R, TextSize = 12, TextColor3 = C.dim }),
		create("TextLabel")({
			Text = p.cooldown .. "s",
			FontFace = B,
			TextSize = 11,
			TextColor3 = C.dim,
			BackgroundColor3 = C.tile,
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 18),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 30),
			corner(3),
			Base.pad(6),
		}),
	}, props))
end

-- a drawn play triangle / stop square (Inter has no reliable media glyphs)
local function playIcon(on: boolean): Frame
	if on then
		return Base.new("Frame", {
			Size = UDim2.fromOffset(7, 7),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = W,
			corner(1),
		})
	end
	local cols = {}
	for col = 0, 6 do
		local hgt = 2 * math.floor((9 - col * 1.35) / 2) + 1
		cols[col + 1] = Base.new("Frame", {
			Size = UDim2.fromOffset(1, hgt),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, col, 0.5, 0),
			BackgroundColor3 = W,
		})
	end
	return frame({
		Size = UDim2.fromOffset(7, 9),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 1, 0.5, 0),
		cols,
	})
end

function PadsView.new(S: State.S, props: Base.Props?): Frame
	local playing = S.previewing
	local function togglePreview(s: Types.Sound)
		if untrack(playing) == s.assetId and preview.IsPlaying then
			preview:Stop()
			playing(nil)
		else
			preview:Stop()
			preview.SoundId = "rbxassetid://" .. string.format("%d", s.assetId)
			preview.TimePosition = 0
			preview:Play()
			playing(s.assetId)
		end
	end
	local endConn = preview.Ended:Connect(function()
		playing(nil)
	end)
	Vide.cleanup(function()
		endConn:Disconnect()
		preview:Stop()
	end)
	local function playButton(s: Types.Sound, x: number, y: number): TextButton
		local hover = source(false)
		return create("TextButton")({
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = function()
				return if hover() then Color3.fromHex("3d3d3d") else C.card2
			end,
			Hover.track(hover),
			Activated = function()
				togglePreview(s)
			end,
			corner(14),
			Base.rebuild(function()
				return playing() == s.assetId
			end, playIcon),
		})
	end

	-- ── grid ──
	local grid = frame({
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.fromOffset(592, PH * 2 + GAP),
		Base.rebuild(function()
			return { Store.library(), S.padSelected() }
		end, function(v)
			local lib: Types.Library, sel: number = v[1], v[2]
			local out = {}
			for i, p in lib.pads do
				local col, row = (i - 1) % 4, (i - 1) // 4
				local hover = source(false)
				local rest = C.field
				out[i] = padFace(lib, p, PW, PH, {
					Position = UDim2.fromOffset(col * (PW + GAP), row * (PH + GAP)),
					BackgroundColor3 = function()
						-- lighter = picked, like the track rows (the tiles sit one step up from the page)
						return if i == sel then C.raised elseif hover() then C.flat else rest
					end,
					Hover.track(hover),
					Activated = function()
						if not p.kind then
							Actions.send({ Kind = "PadAssign", Index = i })
						end
						S.padSelected(i)
					end,
				})
			end
			return out
		end),
	})
	local gridTile = Base.tile(0, 0, 624, GRID_H, {
		frame({
			Size = UDim2.new(1, 0, 0, 56),
			Base.pad(16, 16, 0, 0),
			label("Pads", { FontFace = B, TextSize = 16, Position = UDim2.fromOffset(0, 18) }),
			Controls.button({
				text = "Reset to default",
				kind = "ghost",
				h = 32,
				onClick = function()
					Controls.confirm({
						title = "Reset all pads?",
						body = "All 8 pads go back to the kit's defaults. Your sounds stay in the Sounds list.",
						action = "Reset pads",
						onConfirm = function()
							Actions.send({ Kind = "PadsReset" })
						end,
					})
				end,
			}, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) }),
		}),
		grid,
	})

	-- ── sounds ──
	local msg = source("")
	local idBox: TextBox
	local function addSound()
		local id = tonumber(string.match(idBox.Text, "(%d%d%d%d%d%d+)") or "")
		if not id then
			msg("Paste a numeric asset ID")
			return
		end
		msg("")
		idBox.Text = ""
		Actions.send({ Kind = "SoundAdd", AssetId = id })
	end
	local titleRef: TextLabel
	local sh = frame({
		Size = UDim2.new(1, 0, 0, 64),
		Base.pad(16, 16, 0, 0),
		label("Sounds", {
			FontFace = B,
			TextSize = 16,
			Position = UDim2.fromOffset(0, 22),
			Vide.action(function(l: Instance)
				titleRef = l :: TextLabel
			end),
		}),
		label(function()
			return tostring(#Store.library().sounds)
		end, {
			FontFace = R,
			TextSize = 13,
			TextColor3 = C.dim,
			Position = UDim2.fromOffset(63, 25),
			-- sits 10 px after the title, whatever its width
			Vide.action(function(l: Instance)
				local function place()
					if titleRef then
						(l :: TextLabel).Position = UDim2.fromOffset(titleRef.TextBounds.X + 10, 25)
					end
				end
				task.defer(function()
					place()
					if titleRef then
						titleRef:GetPropertyChangedSignal("TextBounds"):Connect(place)
					end
				end)
			end),
		}),
		Controls.button(
			{ text = "Add sound", kind = "primary", w = 104, h = 32, onClick = addSound },
			{ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) }
		),
		Controls.input({
			placeholder = "Sound asset ID",
			w = 220,
			ref = function(tb)
				idBox = tb
			end,
			onCommit = function(_, enter)
				if enter then
					addSound()
				end
			end,
		}, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -112, 0.5, 0) }),
		label(msg, {
			FontFace = R,
			TextSize = 12,
			TextColor3 = C.redText,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -344, 0.5, 0),
		}),
	})
	local scols = frame({
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, 28),
		caption("Name", {
			AutomaticSize = Enum.AutomaticSize.None,
			Position = UDim2.fromOffset(56, 0),
			Size = UDim2.fromOffset(150, 28),
		}),
		caption("Asset", {
			AutomaticSize = Enum.AutomaticSize.None,
			Position = UDim2.fromOffset(216, 0),
			Size = UDim2.fromOffset(110, 28),
		}),
		caption("Length", {
			AutomaticSize = Enum.AutomaticSize.None,
			Position = UDim2.fromOffset(326, 0),
			Size = UDim2.fromOffset(48, 28),
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
		caption("Used by", {
			AutomaticSize = Enum.AutomaticSize.None,
			Position = UDim2.fromOffset(392, 0),
			Size = UDim2.fromOffset(170, 28),
		}),
		Base.rule(true, 16),
	})
	local slist = Base.scroll({
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 1, -92),
		ScrollBarThickness = 4,
		Base.vlist(0),
		Base.rebuild(function()
			return Store.library()
		end, function(lib: Types.Library)
			local out = {}
			for i, s in lib.sounds do
				local hover = source(false)
				local users = {}
				for _, p in lib.pads do
					if p.kind == "sfx" and p.sound == s.id then
						table.insert(users, p.label)
					end
				end
				local lead
				if s.status == "checking" then
					lead = fixed("Checking…", 16, 0, 40, 48, { TextSize = 11, TextColor3 = C.soft })
				elseif s.status == "unavailable" then
					lead = Base.new("Frame", {
						Size = UDim2.fromOffset(8, 8),
						Position = UDim2.fromOffset(26, 20),
						BackgroundColor3 = C.red,
						corner(4),
					})
				else
					lead = playButton(s, 16, 10)
				end
				out[i] = Base.new("Frame", {
					Size = UDim2.new(1, 0, 0, 48),
					BackgroundColor3 = C.raised,
					LayoutOrder = i,
					BackgroundTransparency = function()
						return if hover() then 0 else 1
					end,
					Hover.track(hover),
					lead,
					fixed(
						s.name,
						56,
						0,
						150,
						48,
						{ TextSize = 14, TextColor3 = if s.status == "unavailable" then C.dim else W }
					),
					fixed(
						string.format("%d", s.assetId),
						216,
						0,
						110,
						48,
						{ FontFace = R, TextSize = 12, TextColor3 = C.dim }
					),
					fixed(
						if s.len then string.format("%.1fs", s.len) else "—",
						326,
						0,
						48,
						48,
						{ TextSize = 12, TextColor3 = C.soft, TextXAlignment = Enum.TextXAlignment.Right }
					),
					fixed(
						if #users > 0
							then table.concat(users, ", ")
							elseif s.status == "unavailable" then "Can't load — remove it"
							else "Not on a pad",
						392,
						0,
						180,
						48,
						{
							FontFace = R,
							TextSize = 12,
							TextColor3 = if s.status == "unavailable"
								then C.redText
								elseif #users > 0 then C.soft
								else C.faint,
						}
					),
					Controls.button({
						text = "",
						glyph = "cross",
						kind = "ghost",
						w = 32,
						h = 32,
						onClick = function()
							Controls.confirm({
								title = "Remove “" .. s.name .. "”?",
								body = if #users > 0
									then ("It comes off " .. table.concat(users, ", ") .. "; " .. (if #users
											== 1
										then "that pad goes"
										else "those pads go") .. " silent until you pick another sound.")
									else "No pad uses it.",
								action = "Remove sound",
								onConfirm = function()
									if untrack(playing) == s.assetId then
										preview:Stop()
									end
									Actions.send({ Kind = "SoundRemove", Id = s.id })
								end,
							})
						end,
					}, {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -16, 0.5, 0),
						BackgroundTransparency = 1, -- flush on the row, like the playlist row tools
					}),
					if i < #lib.sounds then Base.rule(true, 16) else nil,
				})
			end
			return out
		end),
	})
	local soundTile = Base.tile(0, GRID_H + 2, 624, PAGE_H - GRID_H - 2, { sh, scols, slist })

	-- ── editor ──
	local editor = Base.rebuild(function()
		local i = S.padSelected()
		local p = Store.library().pads[i]
		-- rebuild when the pad changes kind or sound (the rest edits in place)
		return if p and p.kind
			then i .. "|" .. p.kind .. "|" .. tostring(p.sound) .. "|" .. tostring(p.effect)
			else "none"
	end, function(key: string)
		if key == "none" then
			return label("Pick a pad to edit it", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				TextColor3 = C.dim,
				TextSize = 13,
			})
		end
		local i = untrack(S.padSelected)
		local pad = function(): Types.Pad
			return Store.library().pads[i] or { label = "", cooldown = 0 }
		end
		local p0 = untrack(pad)
		local lib0 = untrack(Store.library)
		local function edit(field: string, text: string?, number: number?)
			Actions.send({ Kind = "PadEdit", Index = i, Field = field :: any, Text = text, Number = number })
		end
		local function settle(field: string, number: number)
			Actions.settle("pad" .. i .. field, { Kind = "PadEdit", Index = i, Field = field :: any, Number = number })
		end
		local localLabel = source(p0.label)
		local items: { any } = {
			Layout.field(1, "Label", nil, {
				Controls.input({
					placeholder = "Shown on the pad",
					text = p0.label,
					onText = function(t)
						localLabel(t)
					end,
					onCommit = function(t)
						edit("Label", t)
					end,
				}),
			}),
			Layout.field(2, "Type", nil, {
				Controls.segmented({ "SFX", "World effect" }, if p0.kind == "sfx" then 1 else 2, function(k)
					edit("Kind", if k == 1 then "sfx" else "world")
				end, 279),
			}),
		}
		if p0.kind == "sfx" then
			local names = {}
			local current
			for k, s in lib0.sounds do
				names[k] = s.name
				if s.id == p0.sound then
					current = k
				end
			end
			local snd = soundById(lib0, p0.sound)
			table.insert(
				items,
				Layout.field(3, "Sound", nil, {
					Controls.dropdown(names, current, function(k)
						local s = lib0.sounds[k]
						if s then
							edit("Sound", s.id)
						end
					end, 243),
					if snd and snd.status == nil then playButton(snd, 251, 2) else nil,
				})
			)
			table.insert(
				items,
				Layout.field(4, "Volume", Controls.RULER_H, {
					Controls.ruler(279, {
						min = 0,
						max = 100,
						step = 5,
						value = p0.volume or 80,
						default = 80,
						origin = 0,
						ticks = 20,
						major = 5,
						label = function(v)
							return tostring(v)
						end,
						fmt = function(v)
							return string.format("%d%%", v)
						end,
						parse = function(text)
							return tonumber(string.match(text, "[%d%.]+") or "")
						end,
						onChange = function(v)
							settle("Volume", v)
						end,
					}),
				})
			)
			table.insert(
				items,
				Layout.field(5, "Heard by", nil, {
					Controls.segmented({ "Everyone", "Near the DJ deck" }, p0.reach or 1, function(k)
						edit("Reach", nil, k)
					end, 279),
				})
			)
		else
			table.insert(
				items,
				Layout.field(3, "Effect", nil, {
					Controls.dropdown(Defaults.EFFECTS, p0.effect or 1, function(k)
						edit("Effect", nil, k)
					end),
				})
			)
			table.insert(
				items,
				Layout.field(4, "Intensity", nil, {
					Controls.dots(279, {
						min = 0,
						max = 100,
						step = 10,
						value = p0.intensity or 50,
						default = 50,
						fmt = Format.pct,
						onChange = function(v)
							settle("Intensity", v)
						end,
					}),
				})
			)
			table.insert(
				items,
				Layout.field(5, "Lasts", nil, {
					Controls.stepper(p0.duration or 3, 1, 15, 1, Format.seconds, function(v)
						settle("Duration", v)
					end),
				})
			)
		end
		table.insert(
			items,
			Layout.field(6, "Cooldown", nil, {
				Controls.stepper(p0.cooldown, 0, 60, 1, Format.seconds, function(v)
					settle("Cooldown", v)
				end),
				label(
					"deck-wide",
					{ Position = UDim2.fromOffset(132, 8), FontFace = R, TextSize = 12, TextColor3 = C.dim }
				),
			})
		)
		-- the header follows the label as it is typed (the track Inspector's cover + title + subtitle)
		local function shownLabel(): string
			return if localLabel() ~= "" then localLabel() else "Untitled"
		end
		local head = frame({
			Position = UDim2.fromOffset(16, 40),
			Size = UDim2.new(1, -32, 0, 64),
			Covers.track(shownLabel, C.raised, 64),
			fixed(shownLabel, 76, 6, 203, 36, {
				FontFace = B,
				TextSize = 16,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			fixed(
				function()
					return padCaption(Store.library(), pad())
				end,
				76,
				44,
				203,
				16,
				{
					FontFace = R,
					TextSize = 13,
					TextColor3 = C.dim,
				}
			),
		})
		return {
			caption("Pad " .. i, { Position = UDim2.fromOffset(16, 18) }),
			head,
			Base.scroll({
				Position = UDim2.fromOffset(0, 120),
				Size = UDim2.new(1, 0, 1, -120 - 64),
				Base.pad(16, 16, 0, 16),
				Base.vlist(16),
				items,
			}),
			Controls.button({
				text = "Clear this pad",
				kind = "danger",
				h = 32,
				onClick = function()
					local p = untrack(pad)
					Controls.confirm({
						title = "Clear "
							.. (if (p.label or "") ~= "" then "“" .. p.label .. "”" else "this pad")
							.. "?",
						body = "The pad goes blank: its label, sound or effect and settings are removed.",
						action = "Clear pad",
						onConfirm = function()
							Actions.send({ Kind = "PadClear", Index = i })
						end,
					})
				end,
			}, {
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.new(1, -32, 0, 32),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 16, 1, -16),
			}),
		}
	end)
	local editTile = Base.tile(626, 0, 311, PAGE_H, { frame({ Size = UDim2.fromScale(1, 1), editor }) })

	return frame(Base.with({
		Name = "PadsView",
		Position = UDim2.fromOffset(313, 0),
		Size = UDim2.new(0, 937, 1, 0),
		gridTile,
		soundTile,
		editTile,
	}, props))
end

return PadsView
