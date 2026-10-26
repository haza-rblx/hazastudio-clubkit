--!strict
-- The Access tab (311 | 624 | 311): views on the left (Everyone, Residents, Guests, the group-rank
-- and game-pass gates, the DJ deck rules), the DJ table in the middle, the picked DJ's profile or the
-- add form on the right. Rule pages widen the middle to 937.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Shared = ReplicatedStorage.HazaDJ.Shared
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local Actions = require(script.Parent.Parent.Actions)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.UI.Base)
local Controls = require(script.Parent.Parent.UI.Controls)
local Covers = require(script.Parent.Parent.UI.Covers)
local Layout = require(script.Parent.Parent.UI.Layout)
local Debug = require(script.Parent.Parent.Debug)

local create, source, untrack = Vide.create, Vide.source, Vide.untrack
local C, W, B, R = Theme.C, Theme.W, Theme.B, Theme.R
local frame, label, fixed, caption = Base.frame, Base.label, Base.fixed, Base.caption

local Access = {}

local PAGE_H, PAGE_PAD, PAGE_HEAD = Theme.PAGE_H, Theme.PAGE_PAD, Theme.PAGE_HEAD
local ROLES = { "Resident", "Guest" }
local ENDS = { "When the server closes", "In 1 hour", "At 23:00 tonight" }

type Person = Types.Person & { live: boolean, online: boolean }

local function people(): { Person }
	local a, s = Store.access(), Store.session()
	local out = {}
	for key, p in a.people do
		local o = table.clone(p) :: any
		o.live = s.live == p.userId
		o.online = s.online[key] == true
		table.insert(out, o)
	end
	return out
end

local function lastText(p: Person): string
	if p.live then
		return "Now"
	end
	return Format.ago(p.lastSet, os.time())
end

local function status(p: Person): (string, Color3, Color3)
	if p.live then
		return "On the decks", C.red, C.redText
	elseif p.online then
		return "In this server", W, C.soft
	end
	return "Offline", C.faint, C.dim
end

local LAST_ORDER = { Now = 0, Today = 1, Yesterday = 2 }

function Access.new(props: Base.Props?): Frame
	local view = source("all") -- "all" | "Resident" | "Guest" | "group" | "pass" | "rules"
	local selected = source(nil :: number?)
	local adding = source(false)
	local query = source("")
	local sortBy = source(1) -- 1 status, 2 name, 3 last set

	-- the first person opens selected: whoever is live, else the first in the list
	Vide.effect(function()
		if selected() == nil and Store.ready() then
			local list = untrack(people)
			table.sort(list, function(a, b)
				return (if a.live then 0 elseif a.online then 1 else 2)
					< (if b.live then 0 elseif b.online then 1 else 2)
			end)
			if list[1] then
				selected(list[1].userId)
			end
		end
	end)

	local function go(key: string)
		view(key)
		adding(false)
		Controls.closeMenu()
	end
	Debug.on("access", function(cmd: string, arg: any)
		if cmd == "view" then
			go(arg)
		elseif cmd == "select" then
			for _, p in untrack(Store.access).people do
				if p.name == arg then
					selected(p.userId)
					adding(false)
				end
			end
		elseif cmd == "add" then
			adding(true)
		end
		return "ok"
	end)

	-- ── left ──
	local nav = Base.rebuild(function()
		return { Store.access(), view() }
	end, function(v)
		local a: Types.Access, cur: string = v[1], v[2]
		local counts = { all = 0, Resident = 0, Guest = 0 }
		for _, p in a.people do
			counts.all += 1
			counts[p.role] = (counts[p.role] or 0) + 1
		end
		local nx = Layout.counter()
		local function row(key: string, title: string, right: string, rightColor: Color3?)
			return Layout.sideRow(nx(), cur == key, title, right, rightColor, function()
				go(key)
			end)
		end
		return {
			Layout.sideCaption(nx(), "DJs"),
			row("all", "Everyone", tostring(counts.all)),
			row("Resident", "Residents", tostring(counts.Resident)),
			row("Guest", "Guests", tostring(counts.Guest)),
			Layout.sideCaption(nx(), "Also allowed"),
			row(
				"group",
				"Group rank",
				if a.gates.group.on then "On" else "Off",
				if a.gates.group.on then W else C.faint
			),
			row("pass", "Game pass", if a.gates.pass.on then "On" else "Off", if a.gates.pass.on then W else C.faint),
			Layout.sideCaption(nx(), "DJ deck"),
			row("rules", "Rules", ""),
		}
	end)
	local navTile = Base.tile(0, 0, 311, PAGE_H, {
		Base.scroll({
			Size = UDim2.fromScale(1, 1),
			ScrollingDirection = Enum.ScrollingDirection.XY,
			Base.pad(0, 0, 12, 12),
			Base.vlist(0),
			nav,
		}),
	})

	-- ── middle: the list ──
	local function peopleView(): { Instance }
		local title = function()
			local v = view()
			return if v == "Resident" then "Residents" elseif v == "Guest" then "Guests" else "Everyone"
		end
		local top = Layout.pageHead(
			title,
			Controls.button({
				text = "+  Add DJ",
				kind = "primary",
				h = 32,
				onClick = function()
					adding(true)
				end,
			})
		)
		local tools = frame({
			Position = UDim2.fromOffset(0, PAGE_HEAD),
			Size = UDim2.new(1, 0, 0, 48),
			Controls.input({
				placeholder = "Search name or @handle",
				w = 408,
				text = untrack(query),
				onText = function(t)
					query(t)
				end,
			}, { Position = UDim2.fromOffset(PAGE_PAD, 4) }),
			Controls.dropdown(
				{ "Status", "Name A–Z", "Last set" },
				sortBy,
				function() end,
				176,
				{ Position = UDim2.fromOffset(PAGE_PAD + 416, 4) }
			),
		})
		local function colHead(text: string, x: number, w: number, align: Enum.TextXAlignment?)
			return caption(text, {
				AutomaticSize = Enum.AutomaticSize.None,
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.fromOffset(w, 32),
				TextXAlignment = align or Enum.TextXAlignment.Left,
			})
		end
		local cols = frame({
			Position = UDim2.fromOffset(0, PAGE_HEAD + 48),
			Size = UDim2.new(1, 0, 0, 32),
			colHead("DJ", PAGE_PAD + 48, 200),
			colHead("Status", 300, 120),
			colHead("Role", 436, 80),
			colHead("Last set", 520, 88, Enum.TextXAlignment.Right),
			Base.rule(true, PAGE_PAD),
		})
		local list = Base.scroll({
			Position = UDim2.fromOffset(0, PAGE_HEAD + 80),
			Size = UDim2.new(1, 0, 1, -(PAGE_HEAD + 80)),
			ScrollingDirection = Enum.ScrollingDirection.XY,
			Base.vlist(0),
			Base.rebuild(function()
				return { people(), view(), query(), sortBy(), selected(), adding() }
			end, function(v)
				local all: { Person }, cur: string, q: string, sort: number, sel: number?, isAdding: boolean =
					v[1], v[2], v[3], v[4], v[5], v[6]
				local ql = string.lower(q)
				local shown = {}
				for _, p in all do
					local inView = cur == "all" or p.role == cur
					local hit = ql == ""
						or string.find(string.lower(p.name), ql, 1, true) ~= nil
						or string.find(string.lower(p.handle), (string.gsub(ql, "^@", "")), 1, true) ~= nil
					if inView and hit then
						table.insert(shown, p)
					end
				end
				table.sort(shown, function(a, b)
					if sort == 2 then
						return string.lower(a.name) < string.lower(b.name)
					elseif sort == 3 then
						local la, lb = LAST_ORDER[lastText(a)], LAST_ORDER[lastText(b)]
						return (la or (if a.lastSet then 3 + (os.time() - a.lastSet) / 1e6 else 99))
							< (lb or (if b.lastSet then 3 + (os.time() - b.lastSet) / 1e6 else 99))
					end
					-- status: on the decks, then here, then everyone else; ties keep the list order
					local ra = if a.live then 0 elseif a.online then 1 else 2
					local rb = if b.live then 0 elseif b.online then 1 else 2
					if ra ~= rb then
						return ra < rb
					end
					return a.added < b.added
				end)
				if #shown == 0 then
					return frame({
						Size = UDim2.new(1, 0, 0, 140),
						label(
							if q ~= ""
								then "Nobody matches “" .. q .. "”"
								elseif cur == "Guest" then "No guests tonight"
								else "Nobody here yet",
							{
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.new(0.5, 0, 0, 48),
								TextColor3 = C.soft,
							}
						),
						label(if q ~= "" then "Try a name or an @handle." else "Add someone with + Add DJ.", {
							AnchorPoint = Vector2.new(0.5, 0),
							Position = UDim2.new(0.5, 0, 0, 72),
							FontFace = R,
							TextSize = 12,
							TextColor3 = C.dim,
						}),
					})
				end
				local out = {}
				for i, p in shown do
					local on = p.userId == sel and not isAdding
					local hover = source(false)
					local st, dotC, txtC = status(p)
					local last = lastText(p)
					out[i] = create("TextButton")({
						Text = "",
						AutoButtonColor = false,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 52),
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
							selected(p.userId)
							adding(false)
						end,
						Covers.avatar(p, 32, p.live, p.online, { Position = UDim2.fromOffset(PAGE_PAD, 10) }),
						fixed(p.name, PAGE_PAD + 48, 9, 220, 18, { TextSize = 14 }),
						fixed(
							"@" .. p.handle,
							PAGE_PAD + 48,
							28,
							220,
							16,
							{ FontFace = R, TextSize = 12, TextColor3 = C.dim }
						),
						frame({
							Position = UDim2.fromOffset(300, 16),
							Size = UDim2.fromOffset(130, 20),
							Base.hlist(6),
							Base.new("Frame", {
								Size = UDim2.fromOffset(6, 6),
								BackgroundColor3 = dotC,
								LayoutOrder = 1,
								Base.corner(3),
							}),
							label(st, { TextSize = 12, TextColor3 = txtC, LayoutOrder = 2 }),
						}),
						fixed(
							p.role,
							436,
							0,
							80,
							52,
							{ TextSize = 13, TextColor3 = if p.role == "Owner" then W else C.soft }
						),
						fixed(last, 520, 0, 88, 52, {
							TextSize = 13,
							TextColor3 = if last == "Now" then C.redText else C.soft,
							TextXAlignment = Enum.TextXAlignment.Right,
						}),
						if i < #shown then Base.rule(true, PAGE_PAD) else nil,
					})
				end
				return out
			end),
		})
		return { top, tools, cols, list }
	end

	-- rule pages: the same head, body and square cards as Settings
	local function gateView(key: string): { Instance }
		local isGroup = key == "group"
		local g0 = if isGroup then untrack(Store.access).gates.group else untrack(Store.access).gates.pass
		local nx = Layout.counter()
		local gate = if isGroup then "Group" else "Pass"
		local function setGate(p: { [string]: any })
			local cmd = { Kind = "GateEdit", Gate = gate } :: any
			for k, v in p do
				cmd[k] = v
			end
			Actions.settle("gate" .. gate .. (next(p) :: string), cmd, 0.4)
		end
		local cards: { any } = {}
		for _, x in
			Layout.group(nx, "Access", {
				Layout.settingRow(
					nx(),
					"Allow",
					if isGroup then "Let the group in" else "Let pass owners in",
					Controls.toggle(g0.on, function(on)
						Actions.send({ Kind = "GateEdit", Gate = gate, On = on })
					end),
					true
				),
			}, true)
		do
			table.insert(cards, x)
		end
		local rows = {}
		if isGroup then
			rows = {
				Layout.settingRow(
					nx(),
					"Group",
					"The group's ID from its page URL",
					Layout.rowInput("Group ID", 160, g0.id, function(t)
						setGate({ Value = t })
					end)
				),
				Layout.settingRow(
					nx(),
					"Lowest rank",
					"This rank number and everyone above it",
					Layout.rowInput("e.g. 200", 160, (g0 :: any).rank or "", function(t)
						setGate({ Rank = t })
					end),
					true
				),
			}
		else
			rows = {
				Layout.settingRow(
					nx(),
					"Pass",
					"The game pass's asset ID",
					Layout.rowInput("Game pass ID", 160, g0.id, function(t)
						setGate({ Value = t })
					end),
					true
				),
			}
		end
		for _, x in Layout.group(nx, if isGroup then "Group" else "Pass", rows) do
			table.insert(cards, x)
		end
		table.insert(
			cards,
			frame({
				Size = UDim2.new(1, 0, 0, 36),
				LayoutOrder = nx(),
				label(
					"They join as guests for the night and don't show in the list.",
					{ Position = UDim2.fromOffset(0, 12), FontFace = R, TextSize = 12, TextColor3 = C.dim }
				),
			})
		)
		return { Layout.pageHead(if isGroup then "Group rank" else "Game pass"), Layout.pageBody(cards) }
	end

	local function rulesView(): { Instance }
		local nx = Layout.counter()
		local cards = Layout.group(nx, "While a set is live", {
			Layout.settingRow(
				nx(),
				"Take over",
				"Who can take the DJ deck from the live DJ",
				Controls.segmented({ "Owner", "Residents", "Any DJ" }, untrack(Store.access).gates.takeOver, function(i)
					Actions.send({ Kind = "TakeOverPolicy", Policy = i })
				end, 240),
				true
			),
		}, true)
		return { Layout.pageHead("Rules"), Layout.pageBody(cards) }
	end

	local wide = function()
		local v = view()
		return v == "group" or v == "pass" or v == "rules"
	end
	local mainTile = Base.tile(313, 0, 624, PAGE_H, {
		Size = function()
			return UDim2.fromOffset(if wide() then 937 else 624, PAGE_H)
		end,
		frame({
			Size = UDim2.fromScale(1, 1),
			Base.rebuild(function()
				local v = view()
				return if v == "group" or v == "pass" or v == "rules" then v else "people"
			end, function(kind: string)
				if kind == "group" or kind == "pass" then
					return gateView(kind)
				elseif kind == "rules" then
					return rulesView()
				end
				return peopleView()
			end),
		}),
	})

	-- ── right: the picked DJ, or the add form ──
	local function addForm(): { Instance }
		local role = source(if untrack(view) == "Guest" then 2 else 1)
		local ends = 1
		local note = source("")
		local whoBox: TextBox
		local function submit()
			local text = string.match(whoBox.Text, "^%s*@?(.-)%s*$") or ""
			if text == "" then
				note("Type a username or a user ID.")
				return
			end
			for _, p in untrack(Store.access).people do
				if tostring(p.userId) == text or string.lower(p.handle) == string.lower(text) then
					note("@" .. p.handle .. " is already on the list.")
					return
				end
			end
			note("Looking them up…")
			task.spawn(function()
				local r =
					Actions.run({ Kind = "PersonAdd", Who = text, Role = ROLES[untrack(role)] :: any, Ends = ends })
				if r.Ok then
					adding(false)
					if r.Id then
						selected(tonumber(r.Id))
					end
				else
					note(r.Message or "Couldn't add them.")
				end
			end)
		end
		return {
			caption("Add a DJ", { Position = UDim2.fromOffset(16, 18) }),
			Base.scroll({
				Position = UDim2.fromOffset(0, 48),
				Size = UDim2.new(1, 0, 1, -48 - 64),
				Base.pad(16, 16, 0, 16),
				Base.vlist(16),
				Layout.field(1, "Username or user ID", nil, {
					Controls.input({
						placeholder = "e.g. kuro_wav or 1234567",
						ref = function(tb)
							whoBox = tb
							task.defer(function()
								if tb.Parent then
									tb:CaptureFocus()
								end
							end)
						end,
						onCommit = function(_, enter)
							if enter then
								submit()
							end
						end,
					}),
				}),
				Layout.field(2, "Role", nil, {
					Controls.segmented(ROLES, role, function() end, 279),
				}),
				Layout.field(3, "Access ends", nil, {
					Controls.dropdown(ENDS, 1, function(i)
						ends = i
					end, 279),
				}, {
					Visible = function()
						return role() == 2
					end,
				}),
				label(note, { FontFace = R, TextSize = 12, TextColor3 = C.soft, LayoutOrder = 4 }),
			}),
			frame({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 16, 1, -16),
				Size = UDim2.new(1, -32, 0, 32),
				Controls.button({
					text = "Cancel",
					kind = "secondary",
					h = 32,
					onClick = function()
						adding(false)
					end,
				}, { AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(0.5, -4, 0, 32) }),
				Controls.button({ text = "Add DJ", kind = "primary", h = 32, onClick = submit }, {
					AutomaticSize = Enum.AutomaticSize.None,
					Size = UDim2.new(0.5, -4, 0, 32),
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
				}),
			}),
		}
	end

	local function profile(userId: number): { Instance }
		local person = function(): Person?
			for _, p in people() do
				if p.userId == userId then
					return p
				end
			end
			return nil
		end
		local p0 = untrack(person) :: Person
		local st = function()
			local p = person()
			return if p then (status(p)) else ""
		end
		local stColor = function()
			local p = person()
			if not p then
				return C.dim
			end
			return if p.live then C.redText elseif p.online then C.soft else C.dim
		end
		local stat = function(i: number, value: () -> string, name: string)
			return frame({
				Position = UDim2.fromScale((i - 1) / 3, 0),
				Size = UDim2.new(1 / 3, 0, 1, 0),
				label(value, {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 10),
					FontFace = B,
					TextSize = 14,
				}),
				label(name, {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 30),
					FontFace = R,
					TextSize = 12,
					TextColor3 = C.dim,
				}),
			})
		end
		local isOwner = p0.role == "Owner"
		local fields: { any } = {}
		if isOwner then
			fields = {
				label("This is you. The owner can't be removed and always has the DJ deck.", {
					FontFace = R,
					TextSize = 12,
					TextColor3 = C.dim,
					TextWrapped = true,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 0),
				}),
			}
		else
			fields = {
				Layout.field(1, "Role", nil, {
					Controls.segmented({ "Resident", "Guest" }, if p0.role == "Resident" then 1 else 2, function(i)
						Actions.send({ Kind = "PersonEdit", UserId = userId, Role = ROLES[i] :: any })
					end, 279),
				}),
				Base.rebuild(function()
					local p = person()
					return if p then p.role else ""
				end, function(role: string)
					if role == "Guest" then
						return Layout.field(2, "Access ends", nil, {
							Controls.dropdown(ENDS, (untrack(person) :: Person).ends or 1, function(i)
								Actions.send({ Kind = "PersonEdit", UserId = userId, Ends = i })
							end, 279),
						})
					end
					return Layout.field(2, "Resident since", nil, {
						label(function()
							local p = person()
							return if p and p.since then Format.dayMonth(p.since) else "today"
						end, {
							AnchorPoint = Vector2.new(0, 0.5),
							Position = UDim2.fromScale(0, 0.5),
							TextSize = 13,
							TextColor3 = C.soft,
						}),
					})
				end),
			}
		end
		return {
			Covers.avatar(
				p0,
				88,
				p0.live,
				p0.online,
				{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 28) }
			),
			label(
				function()
					local p = person()
					return if p then p.name else ""
				end,
				{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 128), FontFace = B, TextSize = 18 }
			),
			label("@" .. p0.handle, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 152),
				FontFace = R,
				TextSize = 12,
				TextColor3 = C.dim,
			}),
			label(st, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 172),
				TextSize = 12,
				TextColor3 = stColor,
			}),
			frame({
				Position = UDim2.fromOffset(16, 208),
				Size = UDim2.new(1, -32, 0, 56),
				Base.rule(false),
				Base.rule(true),
				stat(1, function()
					local p = person()
					return tostring(if p then p.sets else 0)
				end, "Sets"),
				stat(2, function()
					local p = person()
					return math.floor((if p then p.seconds else 0) / 3600) .. "h"
				end, "On the decks"),
				stat(3, function()
					local p = person()
					return if p then lastText(p) else "—"
				end, "Last set"),
			}),
			Base.scroll({
				Position = UDim2.fromOffset(0, 280),
				Size = UDim2.new(1, 0, 1, -280 - 64),
				Base.pad(16, 16, 0, 16),
				Base.vlist(16),
				fields,
			}),
			if isOwner
				then nil
				else frame({
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 16, 1, -16),
					Size = UDim2.new(1, -32, 0, 32),
					Controls.button({
						text = "Remove access",
						kind = "danger",
						h = 32,
						onClick = function()
							local p = untrack(person)
							if not p then
								return
							end
							Controls.confirm({
								title = "Remove " .. p.name .. "?",
								body = "@"
									.. p.handle
									.. " loses "
									.. string.lower(p.role)
									.. " access to the DJ deck"
									.. (if p.live then " and comes off the decks now." else "."),
								action = "Remove access",
								onConfirm = function()
									Actions.send({ Kind = "PersonRemove", UserId = userId })
									selected(nil)
								end,
							})
						end,
					}, { AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 32) }),
				}),
		}
	end

	local inspTile = Base.tile(939, 0, 311, PAGE_H, {
		Visible = function()
			return not wide()
		end,
		frame({
			Size = UDim2.fromScale(1, 1),
			Base.rebuild(function()
				if adding() then
					return "add"
				end
				local id = selected()
				if not id then
					return "none"
				end
				local found = false
				for _, p in Store.access().people do
					if p.userId == id then
						found = true
					end
				end
				-- rebuild on a selection change, a role change or live / online moving
				if not found then
					return "none"
				end
				local s = Store.session()
				return tostring(id) .. "|" .. tostring(s.live == id) .. "|" .. tostring(s.online[tostring(id)] == true)
			end, function(key: string)
				if key == "add" then
					return addForm()
				elseif key == "none" then
					return label("Pick a DJ to see them here", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						TextColor3 = C.dim,
						TextSize = 13,
					})
				end
				return profile(tonumber(string.split(key, "|")[1]) :: number)
			end),
		}),
	})

	return frame(Base.with({ Name = "Access", Size = UDim2.fromScale(1, 1), navTile, mainTile, inspTile }, props))
end

return Access
