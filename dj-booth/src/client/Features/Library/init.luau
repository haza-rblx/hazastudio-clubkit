--!strict
-- The Library tab (311 | 624 | 311): library views and playlists on the left, the track table in
-- the middle (a playlist opens with its own header: cover, name, order, Delete), the track editor
-- or the add form on the right. "Pads" swaps the middle and right for the pads view.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Vide = require(ReplicatedStorage.CosmicDJ.Packages.Vide)
local Shared = ReplicatedStorage.CosmicDJ.Shared
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local Actions = require(script.Parent.Parent.Actions)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.UI.Base)
local Hover = require(script.Parent.Parent.UI.Hover)
local Controls = require(script.Parent.Parent.UI.Controls)
local Covers = require(script.Parent.Parent.UI.Covers)
local CoverPop = require(script.CoverPop)
local Inspector = require(script.Inspector)
local PadsView = require(script.PadsView)
local State = require(script.State)
local Debug = require(script.Parent.Parent.Debug)

local create, source, untrack = Vide.create, Vide.source, Vide.untrack
local C, W, B, R = Theme.C, Theme.W, Theme.B, Theme.R
local frame, label, fixed, caption, corner = Base.frame, Base.label, Base.fixed, Base.caption, Base.corner

local Library = {}

local PAGE_H = Theme.PAGE_H
local HERO_H, HERO_COVER = 136, 104

function Library.new(props: Base.Props?): (Frame, () -> number)
	local S = State.new()
	-- a track opens selected: the newest
	Vide.effect(function()
		if S.selected() == nil and Store.ready() then
			local first = untrack(S.visibleTracks)[1]
			if first then
				S.selected(first.id)
			end
		end
	end)

	local function open(v: string)
		S.view(v)
		S.sort(1)
		S.adding(false)
		S.coverOpen(false)
	end
	local function deletePlaylist(id: string)
		local p = S.playlist(id)
		if not p then
			return
		end
		local n = #p.tracks
		Controls.confirm({
			title = "Delete “" .. p.name .. "”?",
			body = "The playlist goes away. Its "
				.. n
				.. (if n == 1 then " track stays" else " tracks stay")
				.. " in the library.",
			action = "Delete playlist",
			onConfirm = function()
				Actions.send({ Kind = "PlaylistDelete", Id = id })
				open("all")
			end,
		})
	end
	Debug.on("lib", function(cmd: string, arg: any)
		if cmd == "view" then
			-- a playlist by name, or all / attention / pads
			for _, p in untrack(Store.library).playlists do
				if p.name == arg then
					open(p.id)
					return "ok"
				end
			end
			open(arg)
		elseif cmd == "select" then
			for _, t in untrack(Store.library).tracks do
				if t.title == arg then
					S.selected(t.id)
					S.adding(false)
				end
			end
		elseif cmd == "add" then
			S.adding(true)
			S.newDraft()
		elseif cmd == "cover" then
			S.coverOpen(arg)
		elseif cmd == "pad" then
			S.padSelected(arg)
		elseif cmd == "delete" then
			deletePlaylist(untrack(S.view))
		end
		return "ok"
	end)

	-- ── left: library views + playlists (the deck library's cover rows, 76 px) ──
	local function navCaption(order: number, text: string, withPlus: boolean?)
		return frame({
			Size = UDim2.new(1, 0, 0, if order == 1 then 24 else 44),
			LayoutOrder = order,
			caption(text, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -8) }),
			if withPlus
				then Controls.button({
					text = "New",
					icon = "plus",
					kind = "ghost",
					h = 24,
					onClick = function()
						task.spawn(function()
							local r = Actions.run({ Kind = "PlaylistCreate" })
							if r.Ok and r.Id then
								-- a new playlist opens straight in its header, name focused
								open(r.Id)
								S.focusName(true)
							end
						end)
					end,
				}, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -4), TextSize = 12 })
				else nil,
		})
	end
	local nav = Base.rebuild(function()
		return { Store.library(), S.view() }
	end, function(v)
		local lib: Types.Library, view: string = v[1], v[2]
		local total, bad = 0, 0
		for _, t in lib.tracks do
			total += 1
			if t.status == "unavailable" then
				bad += 1
			end
		end
		local padCount = 0
		for _, p in lib.pads do
			if p.kind then
				padCount += 1
			end
		end
		local kids: { any } = {
			navCaption(1, "Library"),
			Covers.row({
				order = 2,
				on = view == "all",
				title = "All tracks",
				coverText = "All Tracks",
				count = Format.plural(total),
				onClick = function()
					open("all")
				end,
			}),
			Covers.row({
				order = 3,
				on = view == "attention",
				title = "Needs attention",
				coverText = "Needs Attention",
				count = Format.plural(bad),
				countColor = if bad > 0 then C.redText else nil,
				onClick = function()
					open("attention")
				end,
			}),
			Covers.row({
				order = 4,
				on = view == "pads",
				title = "Pads",
				coverText = "Pads",
				count = padCount .. " Pads · " .. #lib.sounds .. " Sounds",
				onClick = function()
					open("pads")
				end,
			}),
			navCaption(5, "Playlists", true),
		}
		for i, pl in lib.playlists do
			table.insert(
				kids,
				Covers.row({
					order = 5 + i,
					on = view == pl.id,
					title = pl.name,
					coverText = pl.coverText or pl.name,
					count = Format.plural(#pl.tracks),
					image = pl.image,
					color = function()
						return Covers.playlistColor(pl)
					end,
					onClick = function()
						open(pl.id)
					end,
				})
			)
		end
		return kids
	end)
	local navTile = Base.tile(0, 0, 311, PAGE_H, {
		Base.scroll({ Size = UDim2.fromScale(1, 1), Base.pad(0, 0, 12, 12), Base.vlist(0), nav }),
	})

	-- ── middle: the table ──
	local isPl = function()
		return S.isPlaylist(S.view())
	end
	local topH = function()
		return if isPl() then HERO_H else 56
	end
	local addBtn = Controls.button({
		text = "Add track",
		icon = "plus",
		kind = "primary",
		h = 32,
		onClick = function()
			S.adding(true)
			S.newDraft()
		end,
	}, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = function()
			return if isPl() then UDim2.new(1, 0, 0, 16 + HERO_COVER - 16) else UDim2.new(1, 0, 0, 28)
		end,
	})

	-- the playlist header: cover (click to edit), the name (edits in place), order + Delete
	local hero = Base.rebuild(function()
		local v = S.view()
		return if S.isPlaylist(v) then v else nil
	end, function(pid: string?)
		if not pid then
			return label(function()
				return if S.view() == "attention" then "Needs attention" else "All tracks"
			end, { FontFace = B, TextSize = 16, Position = UDim2.fromOffset(0, 18) })
		end
		local pl = function(): Types.Playlist
			return S.playlist(pid) or { id = pid, name = "", shuffle = false, tracks = {} }
		end
		local nameHover = source(false)
		local nameFocus = source(false)
		local x = HERO_COVER + 16
		local nameTb: TextBox
		local items = {
			Covers.cover({
				text = function()
					local p = pl()
					return p.coverText or p.name
				end,
				image = function()
					return pl().image
				end,
				color = function()
					return Covers.playlistColor(pl())
				end,
				textSize = 15,
				inset = 10,
			}, { Position = UDim2.fromOffset(0, 16), Size = UDim2.fromOffset(HERO_COVER, HERO_COVER) }),
			create("TextButton")({
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.fromOffset(HERO_COVER, HERO_COVER),
				Position = UDim2.fromOffset(0, 16),
				BackgroundColor3 = Color3.new(),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 5,
				Vide.action(function(hit: Instance)
					local h = hit :: TextButton
					local hint = h:FindFirstChildOfClass("TextLabel") :: TextLabel
					h.MouseEnter:Connect(function()
						TweenService:Create(h, Theme.FAST, { BackgroundTransparency = 0.4 }):Play()
						TweenService:Create(hint, Theme.FAST, { TextTransparency = 0 }):Play()
					end)
					h.MouseLeave:Connect(function()
						TweenService:Create(h, Theme.FAST, { BackgroundTransparency = 1 }):Play()
						TweenService:Create(hint, Theme.FAST, { TextTransparency = 1 }):Play()
					end)
				end),
				Activated = function()
					S.coverOpen(not untrack(S.coverOpen))
				end,
				corner(Covers.COVER_R),
				label("Edit cover", {
					AutomaticSize = Enum.AutomaticSize.None,
					Size = UDim2.fromScale(1, 1),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextSize = 12,
					TextTransparency = 1,
					ZIndex = 6,
				}),
			}),
			caption("Playlist", { Position = UDim2.fromOffset(x, 16) }),
			create("Frame")({
				Position = UDim2.fromOffset(x - 8, 32),
				Size = UDim2.new(1, -(x - 8), 0, 32),
				BackgroundColor3 = C.field,
				BorderSizePixel = 0,
				BackgroundTransparency = function()
					return if nameFocus() or nameHover() then 0 else 1
				end,
				Hover.track(nameHover),
				corner(4),
				create("TextBox")({
					Name = "PlaylistNameBox",
					Size = UDim2.new(1, -16, 1, 0),
					Position = UDim2.fromOffset(8, 0),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Text = untrack(pl).name,
					PlaceholderText = "Playlist name",
					PlaceholderColor3 = C.faint,
					TextColor3 = W,
					FontFace = B,
					TextSize = 22,
					TextXAlignment = Enum.TextXAlignment.Left,
					ClearTextOnFocus = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Focused = function()
						nameFocus(true)
					end,
					Vide.action(function(tb: Instance)
						nameTb = tb :: TextBox
						nameTb.FocusLost:Connect(function()
							nameFocus(false)
							local text = nameTb.Text
							if string.match(text, "%S") and text ~= untrack(pl).name then
								Actions.send({ Kind = "PlaylistEdit", Id = pid, Field = "Name", Text = text })
							else
								nameTb.Text = untrack(pl).name
							end
						end)
					end),
				}),
			}),
		}
		if untrack(S.focusName) then
			S.focusName(false)
			task.defer(function()
				if nameTb and nameTb.Parent then
					nameTb:CaptureFocus()
				end
			end)
		end
		return items
	end)
	-- the controls row under the name: In order / Shuffle, Delete (bottom-aligned with the cover)
	local heroControls = Base.rebuild(function()
		local v = S.view()
		return if S.isPlaylist(v) then v else nil
	end, function(pid: string?)
		if not pid then
			return nil
		end
		local x = HERO_COVER + 16
		local p0 = untrack(function()
			return S.playlist(pid)
		end)
		return frame({
			Name = "HeroControls",
			Position = UDim2.fromOffset(x, 16 + HERO_COVER - 32),
			Size = UDim2.new(1, -x - 98 - 8, 0, 32),
			Controls.segmented({ "In order", "Shuffle" }, if p0 and p0.shuffle then 2 else 1, function(i)
				Actions.send({ Kind = "PlaylistEdit", Id = pid, Field = "Shuffle", Flag = i == 2 })
			end, 150),
			Controls.button({
				text = "Queue all",
				kind = "secondary",
				h = 32,
				onClick = function()
					Actions.send({ Kind = "QueueAll", Playlist = pid })
				end,
			}, { Position = UDim2.fromOffset(158, 0) }),
			Controls.button({
				text = "Delete",
				kind = "danger",
				h = 32,
				onClick = function()
					deletePlaylist(pid)
				end,
			}, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0) }),
		})
	end)

	local top = frame({
		Size = function()
			return UDim2.new(1, 0, 0, topH())
		end,
		Base.pad(16, 16, 0, 0),
		frame({ Name = "TitleSlot", Size = UDim2.fromScale(1, 1), hero }),
		addBtn,
		heroControls,
	})

	-- search + sort
	local sortOptions = function()
		return { if isPl() then "Playlist order" else "Newest first", "Title A–Z", "BPM" }
	end
	local tools = frame({
		Position = function()
			return UDim2.fromOffset(0, topH())
		end,
		Size = UDim2.new(1, 0, 0, 48),
		Controls.input({
			placeholder = "Search title or artist",
			w = 408,
			onText = function(t)
				S.query(t)
			end,
		}, { Position = UDim2.fromOffset(16, 4) }),
		Controls.dropdown(sortOptions, S.sort, function() end, 176, { Position = UDim2.fromOffset(432, 4) }),
	})

	-- columns: cover 16 | title 64 | speed 272 | BPM 324 | key 380 | time 416 | status 492..608
	local function colHead(text: string, x: number, w: number, align: Enum.TextXAlignment?)
		return caption(text, {
			AutomaticSize = Enum.AutomaticSize.None,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(w, 32),
			TextXAlignment = align or Enum.TextXAlignment.Left,
		})
	end
	local cols = frame({
		Position = function()
			return UDim2.fromOffset(0, topH() + 48)
		end,
		Size = UDim2.new(1, 0, 0, 32),
		colHead("Title", 64, 200),
		colHead("Speed", 272, 44, Enum.TextXAlignment.Right),
		colHead("BPM", 324, 40, Enum.TextXAlignment.Right),
		colHead("Key", 380, 36),
		colHead("Time", 416, 48, Enum.TextXAlignment.Right),
		colHead("Status", 492, 116),
		Base.rule(true, 16),
	})

	local function statusCell(t: Types.Track, x: number, y: number): Frame
		local dead = t.status == "unavailable"
		local checking = t.status == "checking"
		local dot = Base.new("Frame", {
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = if dead then C.red elseif checking then W else C.ok,
			LayoutOrder = 1,
			corner(3),
		})
		if checking then
			TweenService:Create(
				dot,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.8 }
			):Play()
		end
		return frame({
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(116, 20),
			Base.hlist(6),
			dot,
			label(
				if dead then "Revoked" elseif checking then "Checking…" else "Available",
				{ TextSize = 12, TextColor3 = if dead then C.redText else C.dim, LayoutOrder = 2 }
			),
		})
	end

	local list = Base.scroll({
		Position = function()
			return UDim2.fromOffset(0, topH() + 80)
		end,
		Size = function()
			return UDim2.new(1, 0, 1, -(topH() + 80))
		end,
		ScrollBarThickness = 4,
		Base.vlist(0),
		Base.rebuild(function()
			return {
				S.visibleTracks(),
				S.selected(),
				S.adding(),
				S.view(),
				S.sort(),
				S.query(),
				Store.library().playlists,
			}
		end, function(v)
			local rows: { Types.Track } = v[1]
			local sel: string?, adding: boolean, view: string, sort: number, q: string = v[2], v[3], v[4], v[5], v[6]
			local lib = untrack(Store.library)
			if #rows == 0 then
				local pl = S.isPlaylist(view)
				return frame({
					Size = UDim2.new(1, 0, 0, 160),
					label(
						if q ~= ""
							then "Nothing matches “" .. q .. "”"
							elseif view == "attention" then "Every track plays fine"
							elseif pl then "This playlist is empty"
							else "No tracks yet",
						{
							AnchorPoint = Vector2.new(0.5, 0),
							Position = UDim2.new(0.5, 0, 0, 56),
							TextColor3 = C.soft,
						}
					),
					label(
						if view == "attention"
							then "Tracks Roblox can't load show up here."
							elseif pl then "Add a track here, or tick this playlist on any track."
							else "Add a track with its asset ID and details.",
						{
							AnchorPoint = Vector2.new(0.5, 0),
							Position = UDim2.new(0.5, 0, 0, 80),
							FontFace = R,
							TextSize = 12,
							TextColor3 = C.dim,
						}
					),
				})
			end
			local out = {}
			local reorder = S.isPlaylist(view) and sort == 1 and q == ""
			local pl = if reorder then S.playlist(view) else nil
			for i, t in rows do
				local on = t.id == sel and not adding
				local hover = source(false)
				local dead = t.status == "unavailable"
				local tuned = math.abs(t.speed - 1) > 0.001
				local status = statusCell(t, 492, 16)
				local tools = nil
				if pl then
					-- in a playlist's own order: up / down, or out of this playlist (hover swaps the status)
					local at = table.find(pl.tracks, t.id) or 0
					local function tool(text: string, order: number, enabled: boolean, fn: () -> ())
						local th = source(false)
						return Controls.button({
							text = text,
							glyph = if text == "×" then "cross" else nil,
							kind = "ghost",
							w = 28,
							h = 28,
							onClick = function()
								if enabled then
									fn()
								end
							end,
							fg = function()
								return if not enabled then C.faint elseif th() then W else C.soft
							end,
						}, {
							LayoutOrder = order,
							TextSize = 14,
							BackgroundTransparency = 1,
							Hover.track(th),
						})
					end
					tools = frame({
						Visible = hover,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -16, 0.5, 0),
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, 28),
						Base.hlist(4, Enum.HorizontalAlignment.Right),
						tool("↑", 1, at > 1, function()
							Actions.send({ Kind = "TrackMove", Playlist = view, Track = t.id, By = -1 })
						end),
						tool("↓", 2, at < #pl.tracks, function()
							Actions.send({ Kind = "TrackMove", Playlist = view, Track = t.id, By = 1 })
						end),
						tool("×", 3, true, function()
							Actions.send({ Kind = "TrackInPlaylist", Track = t.id, Playlist = view, On = false })
						end),
					})
					status.Visible = true
					Vide.effect(function()
						status.Visible = not hover()
					end)
				end
				table.insert(
					out,
					create("TextButton")({
						Text = "",
						AutoButtonColor = false,
						Size = UDim2.new(1, 0, 0, 52),
						BorderSizePixel = 0,
						LayoutOrder = i,
						BackgroundColor3 = if on then C.select else C.hover,
						BackgroundTransparency = function()
							return if on or hover() then 0 else 1
						end,
						Hover.track(hover),
						Activated = function()
							S.selected(t.id)
							S.adding(false)
						end,
						Covers.track(t.title, function()
							return Covers.trackColor(lib, t.id)
						end, 36, { Position = UDim2.fromOffset(16, 8) }),
						fixed(t.title, 64, 9, 200, 18, { TextSize = 14, TextColor3 = if dead then C.dim else W }),
						fixed(t.artist, 64, 28, 200, 16, { FontFace = R, TextSize = 12, TextColor3 = C.dim }),
						fixed(Format.speed(t.speed), 272, 0, 44, 52, {
							TextSize = 13,
							TextXAlignment = Enum.TextXAlignment.Right,
							TextColor3 = if tuned then W else C.faint,
						}),
						fixed(if t.bpm then tostring(Format.effectiveBpm(t.bpm, t.speed)) else "—", 324, 0, 40, 52, {
							TextSize = 13,
							TextXAlignment = Enum.TextXAlignment.Right,
							TextColor3 = if t.bpm then C.soft else C.faint,
						}),
						fixed(
							t.key or "—",
							380,
							0,
							36,
							52,
							{ TextSize = 13, TextColor3 = if t.key then C.soft else C.faint }
						),
						fixed(Format.mmss(t.len and t.len / t.speed), 416, 0, 48, 52, {
							TextSize = 13,
							TextXAlignment = Enum.TextXAlignment.Right,
							TextColor3 = if t.len then C.soft else C.faint,
						}),
						status,
						tools,
						if i < #rows then Base.rule(true, 16) else nil,
					})
				)
			end
			return out
		end),
	})

	local tableTile = Base.tile(313, 0, 624, PAGE_H, {
		Visible = function()
			return S.view() ~= "pads"
		end,
		top,
		tools,
		cols,
		list,
		Base.rebuild(function()
			local v = S.view()
			return if S.coverOpen() and S.isPlaylist(v) then v else nil
		end, function(pid: string?)
			return if pid then CoverPop.new(S, pid, { Position = UDim2.fromOffset(16, 16 + HERO_COVER + 6) }) else nil
		end),
	})

	local inspTile = Base.tile(939, 0, 311, PAGE_H, {
		Visible = function()
			return S.view() ~= "pads"
		end,
		Inspector.new(S),
	})

	local page = frame(Base.with({
		Name = "Tracks",
		Size = UDim2.fromScale(1, 1),
		navTile,
		tableTile,
		inspTile,
		PadsView.new(S, {
			Visible = function()
				return S.view() == "pads"
			end,
		}),
	}, props))
	return page, S.attention
end

return Library
