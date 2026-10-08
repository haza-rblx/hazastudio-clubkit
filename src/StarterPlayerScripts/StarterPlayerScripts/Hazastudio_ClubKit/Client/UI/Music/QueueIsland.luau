--!strict
-- "Someone queued a song" island, shown to every player (owner, 2026-10-07; spec §4 "B4" of
-- docs/plans/ui-experiments-dance-acm-2026-10-07.md). Requests that land within the batch window
-- merge into one island: a pill (heads + "Rio queued · #4"), then a card listing the songs.
--
-- MusicPlayerController hands every queue snapshot to observe(); the first snapshot only primes
-- the known entries, so joining a server with a full queue shows nothing. Auto-playlist entries
-- (isSystemAssigned) never announce.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local KitLook = require(script.Parent.Parent.KitLook)
local NotificationIsland = require(script.Parent.Parent.NotificationIsland)
local Visuals = require(script.Parent.Visuals)

local QueueIsland = {}

local C = KitLook.COLOR
local MUTED = '<font color="#828282">%s</font>'

type Pending = { key: string, entry: any }

local known: { [string]: boolean } = {}
local primed = false
local pending: { Pending } = {}
local flushScheduled = false
local latest = { queue = {} :: { any }, config = nil :: any, playlists = nil :: any }

local function section(): { [string]: any }
	local value = (Config :: any).NotificationIsland
	return if type(value) == "table" then value else {}
end

local function entryKey(entry: any): string?
	if type(entry) ~= "table" then
		return nil
	end
	local key = entry.queueEntryId or entry.id
	return if key ~= nil then tostring(key) else nil
end

local function esc(text: any): string
	return (string.gsub(tostring(text or ""), "[&<>\"]", {
		["&"] = "&amp;",
		["<"] = "&lt;",
		[">"] = "&gt;",
		['"'] = "&quot;",
	}))
end

local function displayName(entry: any): string
	local name = entry.requesterDisplayName
	return if type(name) == "string" and name ~= "" then name else "Someone"
end

-- Overlapping heads, first one on top. Each head sits in a ring of the island colour.
local function headStack(parent: Instance, userIds: { number }, size: number, step: number, order: number): Frame
	local count = math.min(#userIds, 3)
	local stack = KitLook.box(parent, "Heads", UDim2.fromOffset(size + step * math.max(count - 1, 0), size), order)
	for index = 1, count do
		local head = KitLook.headshot(stack, userIds[index], size)
		head.Position = UDim2.fromOffset(step * (index - 1), 0)
		head.ZIndex = 10 - index
		local ring = Instance.new("UIStroke")
		ring.Color = C.panel
		ring.Thickness = 2
		ring.Parent = head
	end
	return stack
end

type Batch = {
	rows: { { entry: any, position: number? } },
	names: { string },
	userIds: { number },
}

local function positionOf(key: string): number?
	for index, entry in ipairs(latest.queue) do
		if entryKey(entry) == key then
			return index
		end
	end
	return nil
end

local function playlistFor(track: any): any?
	local playlists = latest.playlists
	if type(playlists) == "table" and track.playlistId ~= nil and playlists[track.playlistId] then
		return playlists[track.playlistId]
	end
	return track.playlist
end

local function compactBuilder(batch: Batch): NotificationIsland.Builder
	return function(content: Frame)
		KitLook.padding(content, 6, 0, 16, 0)
		KitLook.list(content, Enum.FillDirection.Horizontal, 10, nil, Enum.VerticalAlignment.Center)
		headStack(content, batch.userIds, 32, 14, 0)

		local column = KitLook.box(content, "Lines", UDim2.new(0, 0, 1, 0), 1)
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = column
		KitLook.list(column, Enum.FillDirection.Vertical, 0, nil, Enum.VerticalAlignment.Center)

		local first = batch.rows[1]
		local line1, line2
		if #batch.rows == 1 then
			line1 = displayName(first.entry) .. " queued" .. (if first.position then " · #" .. first.position else "")
			line2 = tostring(first.entry.name or "")
		else
			line1 = string.format("%d new songs in queue", #batch.rows)
			if #batch.names == 1 then
				line2 = batch.names[1]
			elseif #batch.names == 2 then
				line2 = batch.names[1] .. " and " .. batch.names[2]
			else
				line2 = string.format("%s, %s +%d", batch.names[1], batch.names[2], #batch.names - 2)
			end
		end
		KitLook.text(column, line1, 12, Enum.FontWeight.SemiBold, C.sub, 0, { truncate = true })
		KitLook.text(column, line2, 14, Enum.FontWeight.Bold, C.white, 1, { truncate = true })
		return nil
	end
end

local function cardBuilder(batch: Batch): NotificationIsland.Builder
	return function(content: Frame)
		KitLook.padding(content, 14)
		KitLook.list(content, Enum.FillDirection.Vertical, 8)

		local top = KitLook.box(content, "Top", UDim2.new(1, 0, 0, 30), 0)
		KitLook.list(top, Enum.FillDirection.Horizontal, 10, nil, Enum.VerticalAlignment.Center)
		headStack(top, batch.userIds, 30, 18, 0)
		local escaped = {}
		for index, name in ipairs(batch.names) do
			escaped[index] = esc(name)
		end
		local verb = if #batch.names == 1 and #batch.rows == 1
			then " queued a song"
			elseif #batch.names == 1 then string.format(" queued %d songs", #batch.rows)
			else " queued"
		local headline = KitLook.text(top, KitLook.richNames(escaped, 3) .. string.format(MUTED, verb), 14, Enum.FontWeight.SemiBold, C.white, 1, {
			rich = true,
			truncate = true,
		})
		headline.Size = UDim2.new(0, 0, 1, 0)
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = headline

		for index = 1, math.min(#batch.rows, 3) do
			local row = batch.rows[index]
			local track = row.entry
			local line = KitLook.box(content, "Song" .. index, UDim2.new(1, 0, 0, 28), index)
			KitLook.list(line, Enum.FillDirection.Horizontal, 10, nil, Enum.VerticalAlignment.Center)

			local cover = Instance.new("ImageLabel")
			cover.Name = "Cover"
			cover.BackgroundColor3 = C.row
			cover.BorderSizePixel = 0
			cover.ScaleType = Enum.ScaleType.Crop
			cover.Size = UDim2.fromOffset(28, 28)
			cover.ClipsDescendants = true
			KitLook.corner(cover, UDim.new(0, 6))
			cover.Parent = line
			pcall(Visuals.applyTrackCover, cover, track, playlistFor(track), latest.config, { compact = true })

			local creator = tostring(track.creator or "")
			local label = KitLook.text(
				line,
				"<b>" .. esc(track.name) .. "</b>" .. (if creator ~= "" then string.format(MUTED, " · " .. esc(creator)) else ""),
				13,
				Enum.FontWeight.SemiBold,
				C.white,
				1,
				{ rich = true, truncate = true }
			)
			label.Size = UDim2.new(0, 0, 1, 0)
			local grow = Instance.new("UIFlexItem")
			grow.FlexMode = Enum.UIFlexMode.Fill
			grow.Parent = label
			if row.position then
				KitLook.text(line, "#" .. row.position, 12, Enum.FontWeight.Bold, C.sub, 2)
			end
		end

		if #batch.rows > 3 then
			KitLook.text(
				content,
				string.format("+%d more in queue", #batch.rows - 3),
				12,
				Enum.FontWeight.SemiBold,
				Config.Notify.COLOR_INFO,
				10
			)
		end
		return nil
	end
end

local function flush()
	flushScheduled = false
	local items = pending
	pending = {}
	local batch: Batch = { rows = {}, names = {}, userIds = {} }
	local seenUsers: { [string]: boolean } = {}
	for _, item in ipairs(items) do
		local position = positionOf(item.key)
		-- Gone already (played or removed inside the window): nothing to announce.
		if position then
			table.insert(batch.rows, { entry = item.entry, position = position })
			local userId = tonumber(item.entry.requesterUserId)
			local who = if userId then tostring(userId) else displayName(item.entry)
			if not seenUsers[who] then
				seenUsers[who] = true
				table.insert(batch.names, displayName(item.entry))
				if userId then
					table.insert(batch.userIds, userId)
				end
			end
		end
	end
	if #batch.rows == 0 then
		return
	end
	table.sort(batch.rows, function(a, b)
		return (a.position or math.huge) < (b.position or math.huge)
	end)
	NotificationIsland.show({
		key = "queue",
		compact = compactBuilder(batch),
		card = cardBuilder(batch),
		cardHold = 3.6,
		endHold = 2.2,
	})
end

-- Every queue snapshot the client receives (StateSync and QueueUpdated alike).
function QueueIsland.observe(queue: { any }?, config: any, playlists: any?)
	if type(queue) ~= "table" then
		return
	end
	latest.queue = queue
	latest.config = config
	latest.playlists = playlists
	local opts = section()
	local enabled = opts.QUEUE_ENABLED ~= false
	local current: { [string]: boolean } = {}
	for _, entry in ipairs(queue) do
		local key = entryKey(entry)
		if key then
			current[key] = true
			if not known[key] and primed and enabled and entry.isSystemAssigned ~= true then
				table.insert(pending, { key = key, entry = entry })
			end
		end
	end
	-- Keep only what is queued now, so the set stays small over a long session. An empty
	-- snapshot keeps the old set: a blip of "no queue" must not re-announce everything after it.
	if #queue > 0 then
		known = current
	end
	primed = true
	if #pending > 0 and not flushScheduled then
		flushScheduled = true
		task.delay(tonumber(opts.QUEUE_BATCH_SECONDS) or 3, flush)
	end
end

return QueueIsland
