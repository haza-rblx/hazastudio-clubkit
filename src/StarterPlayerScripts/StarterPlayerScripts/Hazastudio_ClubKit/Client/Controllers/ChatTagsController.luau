--!strict
-- Format chat general menjadi [Membership][Couple] DisplayName.
--
-- Sumber kebenaran tag: ChatTagStore (global ChatTagSync, not proximity-gated).
-- Fallback: OverheadController cache + last-known-good. Never invent Guest
-- when the player exists but tag data is not yet authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local OverheadController = require(script.Parent.OverheadController)
local ChatBubbleAdornee = require(script.Parent.Parent.Services.ChatBubbleAdornee)
local ChatTagStore = require(script.Parent.Parent.Services.ChatTagStore)

local log = Logger.new("Client.ChatTagsController")

local _connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

type TagRecord = {
	displayName: string,
	primaryTag: string?,
	coupleTag: string?,
	role: string?,
	effectiveMembership: string?,
}

type ChatTagEntry = Types.ChatTagEntry

-- Last-known-good per userId: dipakai kalau cache payload transien kosong
-- (respawn / race) supaya tag tidak flip ke Guest.
local lastGoodByUserId: { [number]: TagRecord } = {}
local unsubscribeChatTagStore: (() -> ())? = nil

local function destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	table.clear(lastGoodByUserId)
	if unsubscribeChatTagStore then
		unsubscribeChatTagStore()
		unsubscribeChatTagStore = nil
	end
end

local DEFAULT_BUBBLE_TEXT_COLOR = Color3.fromRGB(235, 235, 235)
local BUBBLE_BACKGROUND_COLOR = Color3.fromRGB(17, 17, 17) -- #111111
local BUBBLE_BACKGROUND_TRANSPARENCY = 0.08
local DEFAULT_NAME_COLOR = "#FFFFFF"

local function escapeRichText(text: string): string
	return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
end

local function wrapTag(label: string, color: string): string
	return string.format('<font color="%s">[%s]</font>', color, escapeRichText(label))
end

local function wrapColoredText(text: string, color: string): string
	return string.format('<font color="%s">%s</font>', color, escapeRichText(text))
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

local function resolveHexColor(role: string?, effectiveMembership: string?, primaryTag: string?): string
	local primaryKey = resolveTagColorKey(primaryTag) or resolvePrimaryKey(role, effectiveMembership)
	return Config.ChatPrimaryTagColor[primaryKey] or Config.ChatPrimaryTagColor.Guest or DEFAULT_NAME_COLOR
end

local function resolveBubbleTextColor(role: string?, effectiveMembership: string?, primaryTag: string?): Color3
	local hex = resolveHexColor(role, effectiveMembership, primaryTag)
	local color = color3FromHex(hex)
	return if color then toLightPastel(color) else DEFAULT_BUBBLE_TEXT_COLOR
end

local function tagRecordFromEntry(entry: ChatTagEntry): TagRecord
	return {
		displayName = entry.displayName,
		primaryTag = entry.primaryTag,
		coupleTag = entry.coupleTag,
		role = entry.role,
		effectiveMembership = entry.effectiveMembership,
	}
end

-- Bangun TagRecord dari payload overhead. Kalau chatPrimaryTag hilang
-- (delta parsial diperlakukan sebagai full di joiner race), derive dari
-- role/effectiveMembership via OverheadDomain — logika sama dengan server.
local function tagRecordFromPayload(payload: any): TagRecord?
	if type(payload) ~= "table" then
		return nil
	end
	local displayName = payload.displayName
	if type(displayName) ~= "string" or displayName == "" then
		return nil
	end

	local primaryTag = payload.chatPrimaryTag
	if type(primaryTag) ~= "string" or primaryTag == "" then
		local role = if type(payload.role) == "string" then payload.role else nil
		local membership = if type(payload.effectiveMembership) == "string"
			then payload.effectiveMembership
			else nil
		if role or membership then
			local ok, derived = pcall(
				OverheadDomain.getChatPrimaryTag,
				(role or "Guest") :: any,
				(membership or "Guest") :: any
			)
			if ok and type(derived) == "string" and derived ~= "" then
				primaryTag = derived
			end
		end
	end

	return {
		displayName = displayName,
		primaryTag = if type(primaryTag) == "string" and primaryTag ~= "" then primaryTag else nil,
		coupleTag = if type(payload.chatCoupleTag) == "string" then payload.chatCoupleTag else nil,
		role = if type(payload.role) == "string" then payload.role else nil,
		effectiveMembership = if type(payload.effectiveMembership) == "string"
			then payload.effectiveMembership
			else nil,
	}
end

local function rememberGood(userId: number, record: TagRecord)
	-- Only promote ChatTagStore-backed records. Overhead proximity payloads can be
	-- unresolved Guest and must not stick in lastGood after the speaker leaves range.
	if type(record.primaryTag) == "string" and record.primaryTag ~= "" then
		lastGoodByUserId[userId] = record
	end
end

local function getTagRecord(userId: number): TagRecord?
	local entry = ChatTagStore.get(userId)
	if entry then
		local record = tagRecordFromEntry(entry)
		rememberGood(userId, record)
		return record
	end

	-- Nearby overhead is a live hint only (not lastGood), so distant chat stays
	-- honest when ChatTagStore has not published yet.
	local payload = OverheadController.getCachedPayload(userId)
	local record = tagRecordFromPayload(payload)
	if record and type(record.primaryTag) == "string" and record.primaryTag ~= "" then
		return record
	end

	return lastGoodByUserId[userId]
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

local function nameOnlyRecord(userId: number): TagRecord?
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end
	return {
		displayName = player.DisplayName,
		primaryTag = nil,
		coupleTag = nil,
		role = nil,
		effectiveMembership = nil,
	}
end

local function buildPrefixText(record: TagRecord): string
	local hasTag = type(record.primaryTag) == "string" and record.primaryTag ~= ""
	-- Name-only (awaiting authoritative tag): neutral white, not Guest color.
	local colorHex = if hasTag
		then resolveHexColor(record.role, record.effectiveMembership, record.primaryTag)
		else DEFAULT_NAME_COLOR
	local prefixParts = {}
	if hasTag then
		table.insert(prefixParts, wrapTag(record.primaryTag :: string, colorHex))
	end
	if record.coupleTag and #record.coupleTag > 0 then
		table.insert(prefixParts, wrapTag(record.coupleTag, Config.ChatCoupleTagColor))
	end
	local namePart = wrapColoredText(record.displayName, colorHex)
	if #prefixParts > 0 then
		return table.concat(prefixParts, "") .. " " .. namePart .. ": "
	end
	return namePart .. ": "
end

local function init(_deps: {}?): ()
	ChatTagStore.init()

	track(Players.PlayerRemoving:Connect(function(player)
		lastGoodByUserId[player.UserId] = nil
	end))

	unsubscribeChatTagStore = ChatTagStore.subscribe(function(userId: number?)
		if type(userId) == "number" then
			local entry = ChatTagStore.get(userId)
			if entry then
				rememberGood(userId, tagRecordFromEntry(entry))
			end
		end
	end)

	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local textSource = message.TextSource
		if not textSource then
			return nil
		end

		local cached = getTagRecord(textSource.UserId)
		if not cached then
			-- No authoritative tag yet — name only, never invent [GUEST].
			cached = nameOnlyRecord(textSource.UserId)
			if not cached then
				return nil
			end
		end

		local props = Instance.new("TextChatMessageProperties")
		props.PrefixText = buildPrefixText(cached)
		return props
	end

	applyBubbleAdorneeName()
	ChatBubbleAdornee.bindTuneCommands()

	TextChatService.OnBubbleAdded = function(
		message: TextChatMessage,
		_adornee: Instance?
	): BubbleChatMessageProperties?
		local textSource = message.TextSource
		if not textSource then
			return nil
		end

		local cached = getTagRecord(textSource.UserId)
		local props = Instance.new("BubbleChatMessageProperties")
		preserveConfiguredBubbleStyle(props)
		props.BackgroundColor3 = BUBBLE_BACKGROUND_COLOR
		props.BackgroundTransparency = BUBBLE_BACKGROUND_TRANSPARENCY
		if cached then
			props.TextColor3 = resolveBubbleTextColor(cached.role, cached.effectiveMembership, cached.primaryTag)
		else
			props.TextColor3 = DEFAULT_BUBBLE_TEXT_COLOR
		end
		return props
	end

	log:info("Client ChatTagsController initialized (ChatTagStore + overhead fallback)")
end

return { init = init, destroy = destroy }
