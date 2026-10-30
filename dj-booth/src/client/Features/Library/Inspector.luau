--!strict
-- The Library's right column: the selected track's editor, or the Add form (one ID, or up to 20 at
-- once — each checked with Roblox on the server).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Vide = require(ReplicatedStorage.CosmicDJ.Packages.Vide)
local Shared = ReplicatedStorage.CosmicDJ.Shared
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

local Inspector = {}

local KEYS = {}
for n = 1, 12 do
	table.insert(KEYS, n .. "A")
	table.insert(KEYS, n .. "B")
end
local MAX_IDS = 20
local PICK = 72

local function body(children: { any }, bottom: number): ScrollingFrame
	return Base.scroll({
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 1, -96 - bottom),
		Base.pad(16, 16, 0, 16),
		Base.vlist(16),
		children,
	})
end

local function textField(
	order: number,
	title: string,
	value: string,
	placeholder: string,
	onText: ((string) -> ())?,
	onCommit: ((string) -> ())?
): Frame
	return Layout.field(order, title, nil, {
		Controls.input({
			placeholder = placeholder,
			text = value,
			onText = onText,
			onCommit = if onCommit
				then function(t)
					onCommit(t)
				end
				else nil,
		}),
	})
end

-- BPM (typed) | key
local function bpmKeyRow(
	order: number,
	bpm: number?,
	key: string?,
	onBpm: (number?) -> (),
	onKey: (string) -> ()
): Frame
	local bpmBox: TextBox
	return frame({
		Size = UDim2.new(1, 0, 0, 52),
		LayoutOrder = order,
		frame({
			Size = UDim2.new(0, 135, 0, 52),
			caption("BPM"),
			Controls.input({
				placeholder = "—",
				w = 135,
				text = if bpm then tostring(bpm) else "",
				ref = function(tb)
					bpmBox = tb
				end,
				onCommit = function(text)
					local n = tonumber(text)
					local v = if n then math.clamp(math.floor(n + 0.5), 40, 220) else nil
					bpmBox.Text = if v then tostring(v) else ""
					onBpm(v)
				end,
			}, { Position = UDim2.fromOffset(0, 20) }),
		}),
		frame({
			Position = UDim2.fromOffset(143, 0),
			Size = UDim2.new(1, -143, 0, 52),
			caption("Key"),
			Controls.dropdown(KEYS, if key then table.find(KEYS, key) else nil, function(_, o)
				onKey(o)
			end, nil, { Position = UDim2.fromOffset(0, 20) }),
		}),
	})
end

-- playback speed as a pitch ruler: ticks light from 1.00x out to the value, 1.00x has a detent
local function speedField(order: number, value: number, onChange: (number) -> ()): Frame
	return Layout.field(order, "Playback speed", Controls.RULER_H, {
		Controls.ruler(279, {
			min = 0.5,
			max = 1.5,
			step = 0.01,
			value = value,
			default = 1,
			origin = 1,
			detent = 0.015,
			ticks = 40,
			major = 10,
			mid = 2,
			label = function(v)
				return if v == 1 then "1x" else string.format("%gx", v)
			end,
			fmt = Format.speed,
			parse = function(text)
				local n = tonumber(string.match(text, "[%d%.]+") or "")
				return n and (if string.find(text, "%%") then n / 100 else n)
			end,
			onChange = onChange,
		}),
	})
end

-- the playlists' own covers in one sideways row; in = full cover, out = dimmed
local function playlistChips(order: number, isIn: (string) -> boolean, toggleIn: (string) -> ()): Frame
	return frame({
		Size = UDim2.new(1, 0, 0, 20 + PICK + 4),
		LayoutOrder = order,
		caption("Playlists"),
		create("ScrollingFrame")({
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 16, 0, PICK + 4),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.X,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ClipsDescendants = true,
			Base.hlist(8),
			create("UIPadding")({ PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 16) }),
			Base.rebuild(function()
				return Store.library().playlists
			end, function(playlists: { Types.Playlist })
				if #playlists == 0 then
					return label(
						"No playlists yet — make one on the left.",
						{ FontFace = R, TextSize = 12, TextColor3 = C.dim }
					)
				end
				local out = {}
				for i, pl in playlists do
					local hover = source(false)
					local on = function()
						return isIn(pl.id)
					end
					out[i] = create("TextButton")({
						Text = "",
						AutoButtonColor = false,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.fromOffset(PICK, PICK),
						LayoutOrder = i,
						Hover.track(hover),
						Activated = function()
							toggleIn(pl.id)
						end,
						Covers.cover({
							text = pl.coverText or pl.name,
							image = pl.image,
							color = function()
								return Covers.playlistColor(pl)
							end,
							textSize = 11,
						}, { Size = UDim2.fromScale(1, 1) }),
						-- the dimmer sits over the cover, not in it (the cover's padding would inset it)
						Base.new("Frame", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Color3.new(),
							ZIndex = 2,
							BackgroundTransparency = function()
								return if on() then 1 elseif hover() then 0.35 else 0.55
							end,
							corner(Covers.COVER_R),
						}),
					})
				end
				return out
			end),
		}),
	})
end

-- ── the editor ──
local function editor(S: State.S, id: string): { Instance }
	local track = function(): Types.Track?
		return Store.library().tracks[id]
	end
	local t0 = untrack(track) :: Types.Track
	local lib0 = untrack(Store.library)
	local function edit(field: string, text: string?, number: number?)
		Actions.send({ Kind = "TrackEdit", Id = id, Field = field :: any, Text = text, Number = number })
	end
	local head = frame({
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(1, -32, 0, 64),
		Covers.track(function()
			local t = track()
			return if t then t.title else ""
		end, function()
			return Covers.trackColor(Store.library(), id)
		end, 64),
		fixed(
			function()
				local t = track()
				return if t then t.title else ""
			end,
			76,
			6,
			203,
			36,
			{
				FontFace = B,
				TextSize = 16,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}
		),
		fixed(
			function()
				local t = track()
				return if t then t.artist else ""
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
	local dead = t0.status == "unavailable"
	local items: { any } = {}
	if dead then
		table.insert(
			items,
			Base.new("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Color3.fromHex("2a1719"),
				LayoutOrder = 0,
				corner(4),
				Base.pad(12, 12, 10, 12),
				Base.vlist(4),
				label("Roblox can't load this audio", { TextSize = 13, TextColor3 = C.redText, LayoutOrder = 1 }),
				label(
					"It was removed, made private, or isn't shared with this experience. Swap the ID below or remove the track.",
					{
						FontFace = R,
						TextSize = 12,
						TextColor3 = C.soft,
						TextWrapped = true,
						AutomaticSize = Enum.AutomaticSize.Y,
						Size = UDim2.new(1, 0, 0, 0),
						LayoutOrder = 2,
					}
				),
			})
		)
	end
	table.insert(
		items,
		textField(1, "Title", t0.title, "Track title", nil, function(text)
			if string.match(text, "%S") and text ~= t0.title then
				edit("Title", text)
			end
		end)
	)
	table.insert(
		items,
		textField(2, "Artist", if t0.artist ~= "—" then t0.artist else "", "Artist or DJ", nil, function(text)
			edit("Artist", text)
		end)
	)
	table.insert(
		items,
		bpmKeyRow(3, t0.bpm, t0.key, function(v)
			edit("Bpm", nil, v)
		end, function(k)
			edit("Key", k)
		end)
	)
	table.insert(
		items,
		speedField(4, t0.speed, function(v)
			Actions.settle(id .. "speed", { Kind = "TrackEdit", Id = id, Field = "Speed", Number = v })
		end)
	)
	table.insert(
		items,
		playlistChips(5, function(pid)
			for _, p in Store.library().playlists do
				if p.id == pid then
					return table.find(p.tracks, id) ~= nil
				end
			end
			return false
		end, function(pid)
			local lib = untrack(Store.library)
			local isIn = false
			for _, p in lib.playlists do
				if p.id == pid then
					isIn = table.find(p.tracks, id) ~= nil
				end
			end
			Actions.send({ Kind = "TrackInPlaylist", Track = id, Playlist = pid, On = not isIn })
		end)
	)
	table.insert(
		items,
		Layout.field(6, "Gain", Controls.RULER_H, {
			Controls.ruler(279, {
				min = -6,
				max = 6,
				step = 0.5,
				value = t0.gain,
				default = 0,
				origin = 0,
				ticks = 24,
				major = 4,
				mid = 2,
				label = function(v)
					return if v == 0 then "0" else string.format("%+d", v)
				end,
				fmt = function(v)
					return (if v > 0 then "+" else "") .. string.format("%.1f", v)
				end,
				parse = function(text)
					return tonumber(string.match(text, "[%-%+]?[%d%.]+") or "")
				end,
				onChange = function(v)
					Actions.settle(id .. "gain", { Kind = "TrackEdit", Id = id, Field = "Gain", Number = v })
				end,
			}),
		})
	)
	table.insert(
		items,
		Layout.field(7, "Start at", nil, {
			Controls.stepper(
				t0.start,
				0,
				if t0.len then math.max(0, math.floor(t0.len) - 30) else 120,
				5,
				Format.mmss,
				function(v)
					Actions.settle(id .. "start", { Kind = "TrackEdit", Id = id, Field = "Start", Number = v })
				end
			),
		})
	)
	table.insert(
		items,
		Layout.field(8, "Asset ID", nil, {
			Controls.input({
				placeholder = "",
				text = tostring(string.format("%d", t0.assetId)),
				editable = dead,
				color = if dead then W else C.dim,
				onCommit = if dead
					then function(text, enter)
						local n = tonumber(string.match(text, "(%d%d%d%d%d%d+)") or "")
						if enter and n and n ~= t0.assetId then
							edit("AssetId", nil, n)
						end
					end
					else nil,
			}),
			if dead
				then label("edit + Enter to swap", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, -20),
					FontFace = R,
					TextSize = 12,
					TextColor3 = C.dim,
				})
				else nil,
		})
	)
	local _ = lib0
	return {
		head,
		body(items, 64),
		frame({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -16),
			Size = UDim2.new(1, -32, 0, 32),
			Controls.button({
				text = "Remove from library",
				kind = "danger",
				h = 32,
				onClick = function()
					local t = untrack(track)
					if not t then
						return
					end
					local inLists = 0
					for _, p in untrack(Store.library).playlists do
						if table.find(p.tracks, id) then
							inLists += 1
						end
					end
					Controls.confirm({
						title = "Remove “" .. t.title .. "”?",
						body = if inLists > 0
							then ("It also leaves " .. inLists .. (if inLists == 1 then " playlist." else " playlists."))
							else "It isn't in any playlist.",
						action = "Remove track",
						onConfirm = function()
							local rows = untrack(S.visibleTracks)
							local at
							for i, r in rows do
								if r.id == id then
									at = i
								end
							end
							local nextT = at and (rows[at + 1] or rows[at - 1])
							Actions.send({ Kind = "TrackRemove", Id = id })
							S.selected(if nextT then nextT.id else nil)
						end,
					})
				end,
			}, { AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 32) }),
		}),
	}
end

-- ── the add form ──
local function addForm(S: State.S): { Instance }
	local draft = function(): State.Draft
		return S.draft() :: State.Draft
	end
	local function patch(p: { [string]: any })
		local d = table.clone(untrack(draft))
		for k, v in p do
			d[k] = v
		end
		S.draft(d)
	end
	local idBox: TextBox
	local function runCheck()
		local text = idBox.Text
		local ids, seen = {}, {}
		for d in string.gmatch(text, "%d%d%d%d%d%d+") do
			local n = tonumber(d)
			if n and not seen[n] then
				seen[n] = true
				table.insert(ids, n)
			end
		end
		local capped = #ids > MAX_IDS
		while #ids > MAX_IDS do
			table.remove(ids)
		end
		local lib = untrack(Store.library)
		local function inLibrary(n: number): boolean
			for _, t in lib.tracks do
				if t.assetId == n then
					return true
				end
			end
			return false
		end
		if #ids > 1 then
			local batch = {}
			local toProbe = {}
			for _, n in ids do
				local e = { id = n, probe = if inLibrary(n) then "dupe" else "checking" }
				table.insert(batch, e)
				if e.probe == "checking" then
					table.insert(toProbe, n)
				end
			end
			local nd = table.clone(untrack(draft))
			nd.idText, nd.batch, nd.capped, nd.id, nd.probe = text, batch, capped, nil, nil
			S.draft(nd)
			local mine = untrack(S.draft)
			task.spawn(function()
				local results = if #toProbe > 0 then Actions.probe(toProbe) else {}
				if untrack(S.draft) ~= mine then
					return -- the form moved on
				end
				local byId = {}
				for _, r in results do
					byId[r.AssetId] = r
				end
				local nb = {}
				for i, e in batch do
					local r = byId[e.id]
					nb[i] = if r
						then {
							id = e.id,
							probe = if r.Ok then "ok" elseif r.Pending then "checking" else "dead",
							name = r.Name,
							creator = r.Creator,
							len = r.Len,
						}
						else e
				end
				local cur = table.clone(untrack(draft))
				cur.batch = nb
				S.draft(cur)
			end)
			return
		end
		local id = ids[1]
		if not id then
			local d = table.clone(untrack(draft))
			d.idText, d.batch, d.id, d.probe = text, nil, nil, "bad"
			S.draft(d)
			return
		end
		if inLibrary(id) then
			local d = table.clone(untrack(draft))
			d.idText, d.batch, d.id, d.probe = text, nil, id, "dupe"
			S.draft(d)
			return
		end
		local d = table.clone(untrack(draft))
		d.idText, d.batch, d.id, d.probe = text, nil, id, "checking"
		S.draft(d)
		local mine = untrack(S.draft)
		task.spawn(function()
			local r = Actions.probe({ id })[1]
			local cur = untrack(S.draft)
			if cur ~= mine or not cur then
				return
			end
			local nd = table.clone(cur)
			nd.probe = if r and r.Ok then "ok" elseif r and r.Pending then "checking" else "dead"
			nd.len = r and r.Len
			if nd.title == "" and r and r.Name then
				nd.title = r.Name
			end
			if nd.artist == "" and r and r.Creator then
				nd.artist = r.Creator
			end
			S.draft(nd)
		end)
	end

	local msg = function(): (string, Color3)
		local d = draft()
		if d.probe == "checking" then
			return "Checking with Roblox…", C.soft
		elseif d.probe == "ok" then
			return "Audio found" .. (if d.len then " · " .. Format.mmss(d.len) else ""), W
		elseif d.probe == "dead" then
			return "Roblox can't load this audio for this experience.", C.redText
		elseif d.probe == "bad" then
			return "That isn't an asset ID.", C.redText
		elseif d.probe == "dupe" then
			return "Already in the library.", C.soft
		elseif d.batch then
			local okN, waitN = 0, 0
			for _, e in d.batch do
				okN += if e.probe == "ok" then 1 else 0
				waitN += if e.probe == "checking" then 1 else 0
			end
			if waitN > 0 then
				return "Checking " .. waitN .. " of " .. #d.batch .. "…", C.soft
			end
			return okN .. " of " .. #d.batch .. " ready" .. (if d.capped then " · first 20 kept" else ""),
				if okN > 0 then W else C.redText
		end
		return "One ID, or up to 20 split by commas.", C.dim
	end
	local batchReady = function(): number
		local n = 0
		for _, e in draft().batch or {} do
			n += if e.probe == "ok" then 1 else 0
		end
		return n
	end
	local ready = function(): boolean
		local d = draft()
		if d.batch then
			return batchReady() > 0
		end
		return d.probe == "ok" and string.match(d.title, "%S") ~= nil
	end

	local d0 = untrack(draft)
	local idField = Layout.field(1, "Asset IDs", 32, {
		Controls.input({
			placeholder = "1846552189, 1837849285…",
			w = 199,
			text = d0.idText or (if d0.id then tostring(d0.id) else ""),
			ref = function(tb)
				idBox = tb
			end,
			onCommit = function(_, enter)
				if enter then
					runCheck()
				end
			end,
		}),
		Controls.button(
			{ text = "Check", kind = "secondary", w = 72, h = 32, onClick = runCheck },
			{ Position = UDim2.fromOffset(207, 0) }
		),
	}, { Size = UDim2.new(1, 0, 0, 20 + 32 + 22) })
	fixed(
		function()
			return (msg())
		end,
		0,
		58,
		279,
		16,
		{
			FontFace = R,
			TextSize = 12,
			TextColor3 = function()
				local _, c = msg()
				return c
			end,
			Parent = idField,
		}
	)

	-- details, or the batch list (each track takes its name from Roblox)
	local details = Base.rebuild(function()
		return draft().batch ~= nil
	end, function(isBatch: boolean)
		if isBatch then
			return Base.new("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
				BackgroundColor3 = C.field,
				corner(4),
				Base.pad(0, 12, 0, 12),
				Base.vlist(0),
				Base.rebuild(function()
					return draft().batch
				end, function(batch)
					local out = {}
					for i, e in batch or {} do
						local dot = Base.new("Frame", {
							AnchorPoint = Vector2.new(0, 0.5),
							Position = UDim2.new(0, 0, 0.5, 0),
							Size = UDim2.fromOffset(6, 6),
							BackgroundColor3 = if e.probe == "ok"
								then C.ok
								elseif e.probe == "dead" then C.red
								elseif e.probe == "dupe" then C.faint
								else W,
							corner(3),
						})
						if e.probe == "checking" then
							TweenService:Create(
								dot,
								TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
								{ BackgroundTransparency = 0.8 }
							):Play()
						end
						local name = if e.probe == "ok" then (e.name or tostring(e.id)) else tostring(e.id)
						local note = if e.probe == "ok"
							then (if e.len then Format.mmss(e.len) else "")
							elseif e.probe == "dead" then "Revoked"
							elseif e.probe == "dupe" then "In library"
							else "…"
						out[i] = frame({
							Size = UDim2.new(1, 0, 0, 36),
							LayoutOrder = i,
							dot,
							label(name, {
								AutomaticSize = Enum.AutomaticSize.None,
								Position = UDim2.fromOffset(16, 0),
								Size = UDim2.new(1, -16 - 72 - 8, 1, 0),
								TextSize = 12,
								TextColor3 = if e.probe == "ok" then W else C.dim,
								TextTruncate = Enum.TextTruncate.AtEnd,
							}),
							label(note, {
								AutomaticSize = Enum.AutomaticSize.None,
								AnchorPoint = Vector2.new(1, 0),
								Position = UDim2.fromScale(1, 0),
								Size = UDim2.new(0, 72, 1, 0),
								TextSize = 12,
								TextXAlignment = Enum.TextXAlignment.Right,
								TextColor3 = if e.probe == "dead" then C.redText else C.dim,
							}),
							if i < #batch
								then Base.new("Frame", {
									AnchorPoint = Vector2.new(0, 1),
									Position = UDim2.fromScale(0, 1),
									Size = UDim2.new(1, 0, 0, 1),
									BackgroundColor3 = C.flat,
								})
								else nil,
						})
					end
					return out
				end),
			})
		end
		local d = untrack(draft)
		return {
			textField(2, "Title", d.title, "Shown on the decks", function(v)
				patch({ title = v })
			end),
			textField(3, "Artist", d.artist, "Artist or DJ", function(v)
				patch({ artist = v })
			end),
			bpmKeyRow(4, d.bpm, d.key, function(v)
				patch({ bpm = v })
			end, function(k)
				patch({ key = k })
			end),
			speedField(5, d.speed, function(v)
				patch({ speed = v })
			end),
		}
	end)

	local go = Controls.button({
		text = function()
			local d = draft()
			return if d.batch and batchReady() > 0 then "Add " .. batchReady() .. " tracks" else "Add to library"
		end,
		kind = "primary",
		h = 36,
		bg = function()
			return if ready() then W else C.card2
		end,
		fg = function()
			return if ready() then C.ink else C.faint
		end,
		onClick = function()
			if not untrack(ready) then
				return
			end
			local d = untrack(draft)
			local lists = {}
			for pid in d.lists do
				table.insert(lists, pid)
			end
			task.spawn(function()
				local r
				if d.batch then
					local items = {}
					for _, e in d.batch do
						if e.probe == "ok" then
							table.insert(items, {
								AssetId = e.id,
								Title = e.name or tostring(e.id),
								Artist = e.creator or "",
								Len = e.len,
							})
						end
					end
					r = Actions.run({ Kind = "TrackAddBatch", Items = items, Lists = lists })
				else
					r = Actions.run({
						Kind = "TrackAdd",
						AssetId = d.id :: number,
						Title = d.title,
						Artist = d.artist,
						Bpm = d.bpm,
						Key = d.key,
						Len = d.len,
						Speed = d.speed,
						Lists = lists,
					})
				end
				if r.Ok then
					S.adding(false)
					if r.Id then
						S.selected(r.Id)
					end
				end
			end)
		end,
	}, { AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 36) })

	return {
		label("Add a track", { FontFace = B, TextSize = 16, Position = UDim2.fromOffset(16, 22) }),
		label(function()
			return if draft().batch
				then "Each track takes its name from Roblox."
				else "Check the ID, then fill in the details."
		end, { FontFace = R, TextSize = 12, TextColor3 = C.dim, Position = UDim2.fromOffset(16, 46) }),
		body({
			idField,
			details,
			playlistChips(6, function(pid)
				return draft().lists[pid] == true
			end, function(pid)
				local lists = table.clone(untrack(draft).lists)
				lists[pid] = if lists[pid] then nil else true
				patch({ lists = lists })
			end),
		}, 104),
		frame({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -16),
			Size = UDim2.new(1, -32, 0, 80),
			go,
			Controls.button({
				text = "Cancel",
				kind = "ghost",
				h = 32,
				onClick = function()
					S.adding(false)
				end,
			}, {
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.new(1, 0, 0, 32),
				Position = UDim2.fromOffset(0, 44),
			}),
		}),
	}
end

function Inspector.new(S: State.S): Frame
	return frame({
		Name = "Insp",
		Size = UDim2.fromScale(1, 1),
		Base.rebuild(function()
			if S.adding() and S.draft() then
				return "add"
			end
			local id = S.selected()
			local t = id and Store.library().tracks[id]
			-- rebuild only when the selection or its status changes, never on its own field edits
			-- status is nil on a ready track (Library clears it with Dict.None)
			return if t then id .. "|" .. tostring(t.status) .. "|" .. t.assetId else "none"
		end, function(key: string)
			if key == "add" then
				return addForm(S)
			elseif key == "none" then
				return label("Select a track to edit it", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					TextColor3 = C.dim,
					TextSize = 13,
				})
			end
			return editor(S, string.split(key, "|")[1])
		end),
	})
end

return Inspector
