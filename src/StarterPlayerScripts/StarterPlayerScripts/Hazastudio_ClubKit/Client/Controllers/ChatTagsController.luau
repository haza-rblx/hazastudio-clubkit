--!strict
-- Format chat general menjadi [Membership][Couple] DisplayName.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local DeltaCompressor = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DeltaCompressor)

type OverheadPayload = Types.OverheadPayload

local log = Logger.new("Client.ChatTagsController")

local _connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

local function destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
end

local DEFAULT_BUBBLE_TEXT_COLOR = Color3.fromRGB(235, 235, 235)
local BUBBLE_BACKGROUND_COLOR = Color3.fromRGB(17, 17, 17) -- #111111
local BUBBLE_BACKGROUND_TRANSPARENCY = 0.08

local function escapeRichText(text: string): string
	return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
end

local function wrapTag(label: string, color: string): string
	return string.format('<font color="%s">[%s]</font>', color, escapeRichText(label))
end

local function color3FromHex(hex: string?): Color3?
	if type(hex) ~= "string" then
		return nil
	end

	local clean = hex:gsub("#", "")
	if #clean ~= 6 then
		return nil
	end

	local r = tonumber(clean:sub(1, 2), 16)
	local g = tonumber(clean:sub(3, 4), 16)
	local b = tonumber(clean:sub(5, 6), 16)
	if not r or not g or not b then
		return nil
	end

	return Color3.fromRGB(r, g, b)
end

local function toLightPastel(color: Color3): Color3
	local mixed = color:Lerp(Color3.new(1, 1, 1), 0.68)
	local minChannel = 0.76
	return Color3.new(
		math.clamp(math.max(mixed.R, minChannel), 0, 1),
		math.clamp(math.max(mixed.G, minChannel), 0, 1),
		math.clamp(math.max(mixed.B, minChannel), 0, 1)
	)
end

local function resolvePrimaryKey(role: string?, effectiveMembership: string?): string
	local roleKey = role or "Guest"
	local membershipKey = effectiveMembership or "Guest"
	local rolePriority = Config.ChatPrimaryTagPriority[roleKey] or 0
	local membershipPriority = Config.ChatPrimaryTagPriority[membershipKey] or 0
	return if rolePriority >= membershipPriority then roleKey else membershipKey
end

local function resolveTagColorKey(primaryTag: string?): string?
	if type(primaryTag) ~= "string" or primaryTag == "" then
		return nil
	end

	-- Strip suffix " #N" yang dipake untuk Spender rank tag ("SPENDER #1" → "SPENDER")
	-- supaya reverse-lookup ke ChatPrimaryTagLabel ketemu base label "SPENDER".
	local lookupTag = primaryTag:gsub(" #%d+$", "")

	for roleKey, label in pairs(Config.ChatPrimaryTagLabel) do
		if label == lookupTag then
			return roleKey
		end
	end

	return nil
end

local function resolveBubbleTextColor(role: string?, effectiveMembership: string?): Color3
	local primaryKey = resolvePrimaryKey(role, effectiveMembership)
	local rawColor = Config.ChatPrimaryTagColor[primaryKey] or Config.ChatPrimaryTagColor.Guest
	local color = color3FromHex(rawColor)
	return if color then toLightPastel(color) else DEFAULT_BUBBLE_TEXT_COLOR
end

local function getBubbleChatConfiguration(): BubbleChatConfiguration?
	local byClass = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
	if byClass and byClass:IsA("BubbleChatConfiguration") then
		return byClass
	end

	local byName = TextChatService:FindFirstChild("BubbleChatConfiguration")
	if byName and byName:IsA("BubbleChatConfiguration") then
		return byName
	end

	return nil
end

local function copyProperty(target: Instance, source: Instance, propertyName: string)
	pcall(function()
		(target :: any)[propertyName] = (source :: any)[propertyName]
	end)
end

local function preserveConfiguredBubbleStyle(props: BubbleChatMessageProperties)
	local bubbleConfig = getBubbleChatConfiguration()
	if not bubbleConfig then
		return
	end

	copyProperty(props, bubbleConfig, "FontFace")
	copyProperty(props, bubbleConfig, "TextSize")
	copyProperty(props, bubbleConfig, "TailVisible")
end

local function applyBubbleAdorneeName()
	local chatBubbleCfg = Config.ChatBubble
	if type(chatBubbleCfg) ~= "table" or chatBubbleCfg.ENABLED ~= true then
		return
	end
	local adorneeName = chatBubbleCfg.ADORNEE_NAME
	if type(adorneeName) ~= "string" or adorneeName == "" then
		return
	end
	local bubbleConfig = getBubbleChatConfiguration()
	if not bubbleConfig then
		return
	end
	pcall(function()
		(bubbleConfig :: any).AdorneeName = adorneeName
	end)
end

local function init(_deps: {}?): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then
		log:warn("Remotes folder tidak ditemukan untuk chat tags")
		return
	end

	local overheadRemote = remotes:WaitForChild("OverheadUpdate", 10) :: RemoteEvent?
	if not overheadRemote then
		log:warn("OverheadUpdate remote tidak ditemukan untuk chat tags")
		return
	end

	local tagCache: {
		[number]: {
			displayName: string,
			primaryTag: string,
			coupleTag: string?,
			role: string?,
			effectiveMembership: string?,
		},
	} =
		{}

	-- v2.3 fix: ChatTagsController harus handle wire format DELTA_MESSAGE_KIND
	-- yang dipakai server. Tanpa baseline tracking + merge, delta partial
	-- (cuma 1–2 field) bakal nuke cache jadi nil dan chat tag flip-flop.
	local payloadBaselines: { [number]: any } = {}
	local NIL_SENTINEL = DeltaCompressor.NIL_SENTINEL

	local function mergeDelta(base: any, delta: any): any
		local result: any = if base then table.clone(base) else {}
		for field, value in delta do
			if value == NIL_SENTINEL then
				result[field] = nil
			else
				result[field] = value
			end
		end
		return result
	end

	local function cachePayload(payload: any)
		if type(payload) ~= "table" or type(payload.userId) ~= "number" then
			return
		end

		-- Guard: kalau merged payload masih incomplete (missing displayName /
		-- chatPrimaryTag), skip overwrite biar cache lama tetep dipake.
		if type(payload.displayName) ~= "string" or type(payload.chatPrimaryTag) ~= "string" then
			return
		end

		local overheadPayload = payload :: OverheadPayload
		tagCache[overheadPayload.userId] = {
			displayName = overheadPayload.displayName,
			primaryTag = overheadPayload.chatPrimaryTag,
			coupleTag = overheadPayload.chatCoupleTag,
			role = overheadPayload.role,
			effectiveMembership = overheadPayload.effectiveMembership,
		}
	end

	local function ingestFullPayload(payload: any)
		if type(payload) ~= "table" or type(payload.userId) ~= "number" then
			return
		end
		payloadBaselines[payload.userId] = payload
		cachePayload(payload)
	end

	local function ingestDelta(message: any)
		local userId = if type(message) == "table" then message.userId else nil
		local delta = if type(message) == "table" then message.delta else nil
		if type(userId) ~= "number" or type(delta) ~= "table" then
			return
		end
		local base = payloadBaselines[userId]
		if not base then
			-- First delta untuk userId ini biasanya full state (force broadcast).
			if type(delta.userId) == "number" and type(delta.displayName) == "string" then
				ingestFullPayload(delta)
			end
			return
		end
		local merged = mergeDelta(base, delta)
		merged.userId = userId
		payloadBaselines[userId] = merged
		cachePayload(merged)
	end

	track(Players.PlayerRemoving:Connect(function(player)
		payloadBaselines[player.UserId] = nil
		tagCache[player.UserId] = nil
	end))

	track(overheadRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end

		if payload.kind == Config.Overhead.BATCH_MESSAGE_KIND then
			local payloads = payload.payloads
			if type(payloads) ~= "table" then
				return
			end
			for _, item in ipairs(payloads) do
				ingestFullPayload(item)
			end
			return
		end

		if payload.kind == Config.Overhead.DELTA_MESSAGE_KIND then
			ingestDelta(payload)
			return
		end

		-- Legacy / non-delta full payload path.
		ingestFullPayload(payload)
	end))

	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local textSource = message.TextSource
		if not textSource then
			return nil
		end

		local cached = tagCache[textSource.UserId]
		if not cached then
			local player = Players:GetPlayerByUserId(textSource.UserId)
			if not player then
				return nil
			end
			cached = {
				displayName = player.DisplayName,
				primaryTag = Config.ChatPrimaryTagLabel.Guest,
				coupleTag = nil,
				role = "Guest",
				effectiveMembership = "Guest",
			}
		end

		local primaryKey = resolveTagColorKey(cached.primaryTag) or resolvePrimaryKey(cached.role, cached.effectiveMembership)
		local prefixParts = {
			wrapTag(cached.primaryTag, Config.ChatPrimaryTagColor[primaryKey] or Config.ChatPrimaryTagColor.Guest),
		}
		if cached.coupleTag and #cached.coupleTag > 0 then
			table.insert(prefixParts, wrapTag(cached.coupleTag, Config.ChatCoupleTagColor))
		end
		table.insert(prefixParts, " " .. escapeRichText(cached.displayName))

		local props = Instance.new("TextChatMessageProperties")
		props.PrefixText = table.concat(prefixParts, "") .. ": "
		return props
	end

	applyBubbleAdorneeName()

	TextChatService.OnBubbleAdded = function(
		message: TextChatMessage,
		_adornee: Instance?
	): BubbleChatMessageProperties?
		local textSource = message.TextSource
		if not textSource then
			return nil
		end

		local cached = tagCache[textSource.UserId]
		local props = Instance.new("BubbleChatMessageProperties")
		preserveConfiguredBubbleStyle(props)
		props.BackgroundColor3 = BUBBLE_BACKGROUND_COLOR
		props.BackgroundTransparency = BUBBLE_BACKGROUND_TRANSPARENCY
		props.TextColor3 = resolveBubbleTextColor(
			if cached then cached.role else "Guest",
			if cached then cached.effectiveMembership else "Guest"
		)
		return props
	end

	log:info("Client ChatTagsController initialized")
end

return { init = init, destroy = destroy }
