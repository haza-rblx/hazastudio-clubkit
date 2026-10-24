--!strict
-- The library under the decks, in the Library tab's language (owner: "bener2 samain semantiknya kek
-- library"): cover rows on the left, the same table on the right with a compact 40 px head (list |
-- Queue N tabs, search, sort). Rows load with D1 / D2; Q adds a track to the end of the queue.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Shared = ReplicatedStorage.HazaDJ.Shared
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local Actions = require(script.Parent.Parent.Parent.Actions)
local Store = require(script.Parent.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.Parent.UI.Base)
local Controls = require(script.Parent.Parent.Parent.UI.Controls)
local Covers = require(script.Parent.Parent.Parent.UI.Covers)
local Layout = require(script.Parent.Parent.Parent.UI.Layout)
local Debug = require(script.Parent.Parent.Parent.Debug)
local DragLoad = require(script.Parent.DragLoad)

local create, source, untrack = Vide.create, Vide.source, Vide.untrack
local C, W, B, R = Theme.C, Theme.W, Theme.B, Theme.R
local frame, label, fixed, caption, corner = Base.frame, Base.label, Base.fixed, Base.caption, Base.corner

local DeckLibrary = {}

local HEAD = 40

function DeckLibrary.new(height: number, props: Base.Props?): Frame
	local view = source("all") -- "all" | a playlist id | "queue"
	local browse = source("all") -- what the left column has selected
	local autoMix = source(Store.session().automix) -- follows the server's flag (the toggle writes it too)
	Vide.effect(function()
		autoMix(Store.session().automix)
	end)
	local query = source("")
	local sortBy = source(1)
	local selected = source(nil :: string?)

	local function playlist(id: string): Types.Playlist?
		for _, p in Store.library().playlists do
			if p.id == id then
				return p
			end
		end
		return nil
	end
	Debug.on("decklib", function(cmd: string, arg: any)
		if cmd == "browse" and arg == "all" then
			view("all")
			browse("all")
		elseif cmd == "browse" then
			for _, p in untrack(Store.library).playlists do
				if p.name == arg then
					view(p.id)
					browse(p.id)
				end
			end
		elseif cmd == "queue" then
			view("queue")
		end
		return "ok"
	end)
	-- a browsed playlist that was deleted falls back to All tracks
	Vide.effect(function()
		local b = browse()
		if b ~= "all" and not playlist(b) then
			browse("all")
			if untrack(view) ~= "queue" then
				view("all")
			end
		end
	end)

	-- ── left: All tracks + playlists ──
	local nav = Base.rebuild(function()
		return { Store.library(), browse() }
	end, function(v)
		local lib: Types.Library, b = v[1], v[2]
		local nx = Layout.counter()
		local total = 0
		for _ in lib.tracks do
			total += 1
		end
		local kids = { Layout.sideCaption(nx(), "Library") }
		table.insert(
			kids,
			Covers.row({
				order = nx(),
				on = b == "all",
				title = "All tracks",
				coverText = "All Tracks",
				count = Format.plural(total),
				onClick = function()
					view("all")
					browse("all")
				end,
			})
		)
		if #lib.playlists > 0 then
			table.insert(kids, Layout.sideCaption(nx(), "Playlists"))
		end
		for _, pl in lib.playlists do
			table.insert(
				kids,
				Covers.row({
					order = nx(),
					on = b == pl.id,
					title = pl.name,
					coverText = pl.coverText or pl.name,
					count = Format.plural(#pl.tracks),
					image = pl.image,
					color = Covers.playlistColor(pl),
					onClick = function()
						view(pl.id)
						browse(pl.id)
					end,
				})
			)
		end
		return kids
	end)

	-- ── right: head tabs, search, sort ──
	local function headTab(order: number, text: () -> string, on: () -> boolean, onClick: () -> ())
		return create("TextButton")({
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = order,
			Activated = onClick,
			label(text, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				FontFace = B,
				TextSize = 14,
				TextColor3 = function()
					return if on() then W else C.dim
				end,
			}),
			Base.new("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 2),
				BackgroundColor3 = C.red,
				Visible = on,
			}),
		})
	end
	local onQueue = function()
		return view() == "queue"
	end
	local top = frame({
		Size = UDim2.new(1, 0, 0, HEAD),
		Base.pad(16, 16, 0, 0),
		frame({
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Base.hlist(20),
			headTab(1, function()
				local b = browse()
				local p = if b ~= "all" then playlist(b) else nil
				return if p then p.name else "All tracks"
			end, function()
				return not onQueue()
			end, function()
				view(untrack(browse))
			end),
			headTab(
				2,
				function()
					local n = #Store.session().queue
					return if n > 0 then "Queue  " .. n else "Queue"
				end,
				onQueue,
				function()
					view("queue")
				end
			),
		}),
		-- the right of the head is one flowed cluster per view, ending on the 16 px gutter, 28 px tall.
		-- A list: (Queue all, for a playlist) · search · sort.
		frame({
			Name = "ListTools",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			Visible = function()
				return not onQueue()
			end,
			Base.hlist(8),
			Base.rebuild(function()
				local v = view()
				return if v ~= "all" and v ~= "queue" and playlist(v) then v else nil
			end, function(pid: string?)
				if not pid then
					return nil
				end
				return Controls.button({
					text = "Queue all",
					kind = "ghost",
					h = 28,
					onClick = function()
						Actions.send({ Kind = "QueueAll", Playlist = pid })
					end,
				}, { LayoutOrder = 1 })
			end),
			Controls.input({
				placeholder = "Search title or artist",
				w = 280,
				onText = function(t)
					query(t)
				end,
			}, { Size = UDim2.fromOffset(280, 28), LayoutOrder = 2 }),
			Controls.dropdown(
				{ "Newest first", "Title A–Z", "BPM" },
				sortBy,
				function() end,
				176,
				{ Size = UDim2.fromOffset(176, 28), LayoutOrder = 3 }
			),
		}),
		-- the queue: Clear (while it has entries) · Auto mix and its switch
		frame({
			Name = "QueueBar",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			Visible = onQueue,
			Base.hlist(16),
			Base.rebuild(function()
				return #Store.session().queue > 0
			end, function(any: boolean)
				return if any
					then Controls.button({
						text = "Clear",
						kind = "ghost",
						h = 28,
						onClick = function()
							Actions.send({ Kind = "QueueClear" })
						end,
					}, { LayoutOrder = 1 })
					else nil
			end),
			frame({
				Size = UDim2.fromOffset(0, 28),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = 2,
				Base.hlist(8),
				label("Auto mix", { TextSize = 13, TextColor3 = C.soft, LayoutOrder = 1 }),
				Controls.toggle(autoMix, function(on: boolean)
					Actions.send({ Kind = "Automix", On = on })
				end, { LayoutOrder = 2 }),
			}),
		}),
	})

	-- One column grid for both views, read from the right gutter (921). Two action slots: the load
	-- pair (D1 D2) at `load`, and a 72 px `side` slot for the row's secondary actions, which is Q on a
	-- list row and move / remove on a queue row (those show only on the hovered or selected row).
	-- The data columns sit 24 px left of the load pair; a queue row drops Speed (the tuning lives in
	-- the track) and its title takes the room. Speed / BPM / time are right-aligned, key reads left.
	local G = { speed = 529, bpm = 589, key = 645, time = 697, load = 769, side = 849 }
	local function colHead(text: string, x: number, w: number, align: Enum.TextXAlignment?, props: Base.Props?)
		return caption(
			text,
			Base.with({
				AutomaticSize = Enum.AutomaticSize.None,
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.fromOffset(w, 32),
				TextXAlignment = align or Enum.TextXAlignment.Left,
			}, props)
		)
	end
	local RIGHT = Enum.TextXAlignment.Right
	-- queue rows: place 16..36, cover 48..84, title from here (12 px between each, like cover to title)
	local QX = 96
	local cols = frame({
		Position = UDim2.fromOffset(0, HEAD),
		Size = UDim2.new(1, 0, 0, 32),
		-- the queue puts its place number before the cover, so its titles start one slot further in
		colHead("Title", 64, 400, nil, {
			Position = function()
				return UDim2.fromOffset(if onQueue() then QX else 64, 0)
			end,
		}),
		colHead("Speed", G.speed, 44, RIGHT, {
			Visible = function()
				return not onQueue()
			end,
		}),
		colHead("BPM", G.bpm, 40, RIGHT),
		colHead("Key", G.key, 36),
		colHead("Time", G.time, 48, RIGHT),
		Base.rule(true, 16),
	})

	type Row = { track: Types.Track, entry: Types.QueueEntry?, pos: number? }
	local function rows(lib: Types.Library, v: string, q: string, sort: number, queue: { Types.QueueEntry }): { Row }
		local out: { Row } = {}
		local ql = string.lower(q)
		local function hit(t: Types.Track): boolean
			return ql == ""
				or string.find(string.lower(t.title), ql, 1, true) ~= nil
				or string.find(string.lower(t.artist), ql, 1, true) ~= nil
		end
		if v == "queue" then
			-- unfiltered: the search box isn't shown on the queue
			for pos, e in queue do
				local t = lib.tracks[e.trackId]
				if t then
					table.insert(out, { track = t, entry = e, pos = pos })
				end
			end
			return out -- the queue keeps its own order
		end
		local p = if v ~= "all" then playlist(v) else nil
		if p then
			for _, id in p.tracks do
				local t = lib.tracks[id]
				if t and hit(t) then
					table.insert(out, { track = t })
				end
			end
		else
			for _, t in lib.tracks do
				if hit(t) then
					table.insert(out, { track = t })
				end
			end
		end
		if sort == 2 then
			table.sort(out, function(a, b)
				return a.track.title < b.track.title
			end)
		elseif sort == 3 then
			table.sort(out, function(a, b)
				return (Format.effectiveBpm(a.track.bpm, a.track.speed) or 0)
					< (Format.effectiveBpm(b.track.bpm, b.track.speed) or 0)
			end)
		elseif v == "all" then
			table.sort(out, function(a, b)
				return a.track.added > b.track.added
			end)
		end
		return out
	end

	-- a row key (D1, D2, Q): 32 × 28, flat, lighter on hover
	-- outline: a secondary key (Q) drawn as a rim only, filled on hover
	local function actionButton(text: string, order: number, onClick: () -> (), outline: boolean?)
		local hover = source(false)
		return create("TextButton")({
			Text = text,
			FontFace = B,
			TextSize = 12,
			TextColor3 = W,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(32, 28),
			BackgroundColor3 = function()
				return if hover() then C.card2 else C.flat
			end,
			BackgroundTransparency = function()
				return if outline and not hover() then 1 else 0
			end,
			if outline
				then create("UIStroke")({
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = C.flat,
					Thickness = 1,
				})
				else nil,
			BorderSizePixel = 0,
			LayoutOrder = order,
			ZIndex = 3,
			MouseEnter = function()
				hover(true)
			end,
			MouseLeave = function()
				hover(false)
			end,
			Activated = onClick,
			corner(4),
		})
	end

	-- a quiet queue edit (move, remove): no fill until hovered, the mark dim until hovered
	local function editButton(x: number, mark: (Color3) -> Instance, onClick: () -> ())
		local hover = source(false)
		return create("TextButton")({
			Text = "",
			AutoButtonColor = false,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(24, 28),
			BackgroundColor3 = C.flat,
			BackgroundTransparency = function()
				return if hover() then 0 else 1
			end,
			BorderSizePixel = 0,
			ZIndex = 3,
			MouseEnter = function()
				hover(true)
			end,
			MouseLeave = function()
				hover(false)
			end,
			Activated = onClick,
			corner(4),
			frame({ Size = UDim2.fromScale(1, 1), Visible = hover, ZIndex = 3, mark(W) }),
			frame({
				Size = UDim2.fromScale(1, 1),
				Visible = function()
					return not hover()
				end,
				ZIndex = 3,
				mark(C.dim),
			}),
		})
	end
	-- the edit marks: square-ended 1 px strokes (owner: an arrow with a stem, nothing rounded)
	local function stroke(color: Color3, x: number, y: number, w: number, h: number, rot: number?): Frame
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			Rotation = rot or 0,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		})
	end
	local function arrow(down: boolean): (Color3) -> Instance
		return function(color: Color3)
			-- drawn pointing up in a 9 x 9 box, 1 px: stem, then the two head strokes meeting at the tip
			return frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(9, 9),
				Rotation = if down then 180 else 0,
				stroke(color, 4.5, 5, 1, 8),
				stroke(color, 3.3, 2.2, 3.5, 1, -45),
				stroke(color, 5.7, 2.2, 3.5, 1, 45),
			})
		end
	end
	local function cross(color: Color3): Instance
		return frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(9, 9),
			stroke(color, 4.5, 4.5, 10, 1, 45),
			stroke(color, 4.5, 4.5, 10, 1, -45),
		})
	end

	-- the queue on its own: the session changes on every re-anchor and fader move, the queue's table
	-- only when the queue does, so the rows don't rebuild (and lose hover / a drag) while decks play
	local queueOnly = Vide.derive(function()
		return Store.session().queue
	end)
	local list = Base.scroll({
		Position = UDim2.fromOffset(0, HEAD + 32),
		Size = UDim2.new(1, 0, 1, -(HEAD + 32)),
		ScrollBarThickness = 4,
		Base.vlist(0),
		Base.rebuild(function()
			return { Store.library(), view(), query(), sortBy(), queueOnly(), selected() }
		end, function(v)
			local lib: Types.Library, vw: string, q: string = v[1], v[2], v[3]
			local queue: { Types.QueueEntry } = v[5]
			local sel: string? = v[6]
			local rs = rows(lib, vw, q, v[4], queue)
			local out = {}
			if #rs == 0 then
				-- one line, plus a hint under it where there's something to do
				local title, hint
				if vw == "queue" then
					title, hint = "The queue is empty", "Press Q on a track to add it"
				elseif q ~= "" then
					title = "Nothing matches “" .. q .. "”"
				elseif vw == "all" then
					title, hint = "No tracks yet", "Add tracks in the Library tab"
				else
					title = "This playlist is empty"
				end
				table.insert(
					out,
					frame({
						Size = UDim2.new(1, 0, 0, 120),
						label(title, {
							AnchorPoint = Vector2.new(0.5, 0),
							Position = UDim2.new(0.5, 0, 0, if hint then 40 else 50),
							TextColor3 = C.soft,
						}),
						if hint
							then label(hint, {
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.new(0.5, 0, 0, 62),
								FontFace = R,
								TextSize = 12,
								TextColor3 = C.dim,
							})
							else nil,
					})
				)
				return out
			end
			for i, r in rs do
				local t = r.track
				local pos = r.pos or 0 -- a queue row's place (1 = Next)
				local on = t.id == sel
				local hover = source(false)
				local dead = t.status == "unavailable"
				local tuned = math.abs(t.speed - 1) > 0.001
				-- D1 / D2 and a drop onto a deck both load through here
				local function loadOnto(n: number)
					local load = function()
						Actions.send({ Kind = "Load", Deck = n, Track = t.id })
					end
					-- "Loading onto a playing deck: Ask" (the server blocks for "Block")
					local d = untrack(Store.session).decks[n]
					if d.playing and untrack(Store.settings).busyDeck == 1 then
						Controls.confirm({
							title = "Load onto deck " .. n .. "?",
							body = "Deck "
								.. n
								.. " is playing. "
								.. t.title
								.. " replaces it and the room hears the cut.",
							action = "Load D" .. n,
							onConfirm = load,
						})
					else
						load()
					end
				end
				local isQ = r.entry ~= nil
				local tx = if isQ then QX else 64
				local titleW = (if isQ then G.bpm else G.speed) - 24 - tx
				local function num(text: string, x: number, w: number, color: Color3, align: Enum.TextXAlignment?)
					return fixed(
						text,
						x,
						0,
						w,
						52,
						{ TextSize = 13, TextXAlignment = align or RIGHT, TextColor3 = color }
					)
				end
				-- the load pair, or "Revoked" in its place
				local keys = {}
				if dead then
					keys = { label("Revoked", { TextSize = 12, TextColor3 = C.redText, LayoutOrder = 1 }) }
				else
					for n = 1, 2 do
						table.insert(
							keys,
							actionButton("D" .. n, n, function()
								loadOnto(n)
							end)
						)
					end
				end
				-- a list row's side slot: Q, on the slot's right edge
				local side: Instance? = if not isQ and not dead
					then actionButton("Q", 1, function()
						Actions.send({ Kind = "QueueAdd", Track = t.id })
					end, true)
					else nil
				if side then
					(side :: TextButton).Position = UDim2.fromOffset(G.side + 40, 12)
				end
				-- a queue row's edits (up, down, remove) at fixed slots, shown on the hovered or selected row
				local edits = nil
				if isQ then
					local e = r.entry :: Types.QueueEntry
					edits = frame({
						Position = UDim2.fromOffset(G.side, 12),
						Size = UDim2.fromOffset(72, 28),
						ZIndex = 2,
						Visible = function()
							return on or hover()
						end,
						if pos > 1
							then editButton(0, arrow(false), function()
								Actions.send({ Kind = "QueueMove", Key = e.key, By = -1 })
							end)
							else nil,
						if pos < #queue
							then editButton(24, arrow(true), function()
								Actions.send({ Kind = "QueueMove", Key = e.key, By = 1 })
							end)
							else nil,
						editButton(48, cross, function()
							Actions.send({ Kind = "QueueRemove", Key = e.key })
						end),
					})
				end
				local row = create("TextButton")({
					Text = "",
					AutoButtonColor = false,
					Size = UDim2.new(1, 0, 0, 52),
					BorderSizePixel = 0,
					LayoutOrder = i,
					BackgroundColor3 = if on then C.select else C.hover,
					BackgroundTransparency = function()
						return if on or hover() then 0 else 1
					end,
					MouseEnter = function()
						hover(true)
					end,
					MouseLeave = function()
						hover(false)
					end,
					Activated = function()
						-- the release that ends a drag is not a click
						if not DragLoad.recent() then
							selected(t.id)
						end
					end,
					-- a queue row: its place, then the cover (owner: a plain 1, not "Next")
					if isQ
						then label(tostring(pos), {
							AutomaticSize = Enum.AutomaticSize.None,
							Position = UDim2.fromOffset(16, 8),
							Size = UDim2.fromOffset(20, 36),
							TextXAlignment = Enum.TextXAlignment.Center,
							TextSize = 12,
							TextColor3 = if pos == 1 then W else C.dim,
						})
						else nil,
					Covers.track(
						t.title,
						Covers.trackColor(lib, t.id),
						36,
						{ Position = UDim2.fromOffset(if isQ then QX - 48 else 16, 8) }
					),
					fixed(t.title, tx, 9, titleW, 18, {
						TextSize = 14,
						TextColor3 = if dead then C.dim else W,
					}),
					fixed(t.artist, tx, 28, titleW, 16, {
						FontFace = R,
						TextSize = 12,
						TextColor3 = C.dim,
					}),
					if isQ then nil else num(Format.speed(t.speed), G.speed, 44, if tuned then W else C.faint),
					num(
						if t.bpm then tostring(Format.effectiveBpm(t.bpm, t.speed)) else "—",
						G.bpm,
						40,
						if t.bpm then C.soft else C.faint
					),
					num(t.key or "—", G.key, 36, if t.key then C.soft else C.faint, Enum.TextXAlignment.Left),
					num(Format.mmss(t.len and t.len / t.speed), G.time, 48, if t.len then C.soft else C.faint),
					frame({
						Position = UDim2.fromOffset(G.load, 12),
						Size = UDim2.fromOffset(68, 28),
						ZIndex = 2,
						Base.hlist(4),
						keys,
					}),
					edits,
					side,
					if i < #rs then Base.rule(true, 16) else nil,
				})
				if not dead then
					DragLoad.bind(row, t.title, Covers.trackColor(lib, t.id), loadOnto)
				end
				table.insert(out, row)
			end
			return out
		end),
	})

	return frame(Base.with({
		Name = "DeckLibrary",
		Size = UDim2.new(1, 0, 0, height),
		Base.tile(0, 0, 311, height, {
			Base.scroll({
				Size = UDim2.fromScale(1, 1),
				ScrollingDirection = Enum.ScrollingDirection.XY,
				Base.pad(0, 0, 12, 12),
				Base.vlist(0),
				nav,
			}),
		}),
		Base.tile(313, 0, 937, height, { top, cols, list }),
	}, props))
end

return DeckLibrary
