--!strict
-- Format chat general menjadi [Membership][Couple] DisplayName.
--
-- v2.4.52 fix: jangan maintain cache OverheadUpdate duplikat di sini.
-- ChatTagsController init telat (setelah batch awal server terkirim), jadi
-- listener lokalnya sering miss batch itu dan delta parsial berikutnya
-- di-drop tanpa baseline → chat tag jatuh ke Guest secara acak.
-- Sumber kebenaran sekarang OverheadController.getCachedPayload (subscribe
-- paling awal di boot, merge delta lengkap) + last-known-good lokal supaya
-- tag tidak pernah downgrade ke Guest saat payload transien hilang.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local OverheadDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.OverheadDomain)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local OverheadController = require(script.Parent.OverheadController)
local ChatBubbleAdornee = require(script.Parent.Parent.Services.ChatBubbleAdornee)

local log = Logger.new("Client.ChatTagsController")

local _connections: { RBXScriptConnection } = {}

local function track(conn: RBXScriptConnection): RBXScriptConnection
	table.insert(_connections, conn)
	return conn
end

type TagRecord = {
	displayName: string,
	primaryTag: string,
	coupleTag: string?,
	role: string?,
	effectiveMembership: string?,
}

-- Last-known-good per userId: dipakai kalau cache payload transien kosong
-- (respawn / race) supaya tag tidak flip ke Guest.
local lastGoodByUserId: { [number]: TagRecord } = {}
local unsubscribeCacheUpdated: (() -> ())? = nil

local function destroy()
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	table.clear(_connections)
	table.clear(lastGoodByUserId)
	if unsubscribeCacheUpdated then
		unsubscribeCacheUpdated()
		unsubscribeCacheUpdated = nil
	end
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
		local role = if type(payload.role) == "string" then payload.role else "Guest"
		local membership = if type(payload.effectiveMembership) == "string"
			then payload.effectiveMembership
			else "Guest"
		local ok, derived = pcall(OverheadDomain.getChatPrimaryTag, role :: any, membership :: any)
		if ok and type(derived) == "string" and derived ~= "" then
			primaryTag = derived
		else
			return nil
		end
	end

	return {
		displayName = displayName,
		primaryTag = primaryTag,
		coupleTag = if type(payload.chatCoupleTag) == "string" then payload.chatCoupleTag else nil,
		role = if type(payload.role) == "string" then payload.role else nil,
		effectiveMembership = if type(payload.effectiveMembership) == "string"
			then payload.effectiveMembership
			else nil,
	}
end

local function getTagRecord(userId: number): TagRecord?
	local payload = OverheadController.getCachedPayload(userId)
	local record = tagRecordFromPayload(payload)
	if record then
		lastGoodByUserId[userId] = record
		return record
	end
	-- Payload belum ada / incomplete → pakai last-known-good, jangan downgrade.
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

local function init(_deps: {}?): ()
	track(Players.PlayerRemoving:Connect(function(player)
		lastGoodByUserId[player.UserId] = nil
	end))

	-- Pre-warm last-known-good setiap kali cache overhead berubah, supaya
	-- pesan pertama setelah join/respawn sudah punya tag benar.
	if type(OverheadController.subscribeOverheadCacheUpdated) == "function" then
		unsubscribeCacheUpdated = OverheadController.subscribeOverheadCacheUpdated(function(userId: number?)
			if type(userId) == "number" then
				local record = tagRecordFromPayload(OverheadController.getCachedPayload(userId))
				if record then
					lastGoodByUserId[userId] = record
				end
			end
		end)
	end

	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local textSource = message.TextSource
		if not textSource then
			return nil
		end

		local cached = getTagRecord(textSource.UserId)
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
		props.TextColor3 = resolveBubbleTextColor(
			if cached then cached.role else "Guest",
			if cached then cached.effectiveMembership else "Guest"
		)
		return props
	end

	log:info("Client ChatTagsController initialized (overhead cache source)")
end

return { init = init, destroy = destroy }
