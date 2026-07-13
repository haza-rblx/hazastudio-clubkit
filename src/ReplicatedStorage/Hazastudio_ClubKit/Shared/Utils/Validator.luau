--!strict
-- Shared/Utils/Validator.lua
-- Terpusat: semua schema validation di sini.
-- Setiap validator mengembalikan { valid: boolean, errors: {string} }
local HttpService = game:GetService("HttpService")
-- require di atas bersama require lain, bukan di tengah file
local Config = require(script.Parent.Parent.Constants.Config)
local Logger = require(script.Parent.Logger)
type VResult = { valid: boolean, errors: {string} }
local log = Logger.new("Validator")
local function vr(errs: {string}): VResult
	return { valid = #errs == 0, errors = errs }
end
local Validator = {}
-- ============================================================
-- BASE: command envelope (dipakai oleh semua remote yang modif data)
-- ============================================================
function Validator.command(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table"            then return vr({ "payload must be a table" }) end
	if type(d.type) ~= "string"      then table.insert(e, "missing field: type (string)") end
	if type(d.requestId) ~= "string" then table.insert(e, "missing field: requestId (string)") end
	return vr(e)
end
-- ============================================================
-- COUPLE REQUEST
-- ============================================================
function Validator.coupleRequest(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table" then return vr({ "payload must be a table" }) end
	if type(d.requestId)     ~= "string" then table.insert(e, "missing requestId") end
	if type(d.targetUserId)  ~= "number" then table.insert(e, "missing targetUserId") end
	if type(d.targetUserId) == "number" and d.targetUserId <= 0 then
		table.insert(e, "targetUserId must be positive")
	end
	return vr(e)
end
-- ============================================================
-- COUPLE RESPONSE (accept / reject)
-- ============================================================
function Validator.coupleResponse(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table" then return vr({ "payload must be a table" }) end
	if type(d.requestId) ~= "string"  then table.insert(e, "missing requestId") end
	if type(d.accepted)  ~= "boolean" then table.insert(e, "missing accepted (boolean)") end
	return vr(e)
end
-- ============================================================
-- SHOP GIFT PENDING
-- ============================================================
function Validator.shopGiftPending(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table" then return vr({ "payload must be a table" }) end
	if type(d.tier)       ~= "string" then table.insert(e, "missing tier (string)") end
	if type(d.toId)       ~= "number" then table.insert(e, "missing toId (number)") end
	if type(d.requestId)  ~= "string" then table.insert(e, "missing requestId (string)") end
	return vr(e)
end
-- ============================================================
-- COUPLE OPEN PANEL
-- ============================================================
function Validator.coupleOpenPanel(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table" then return vr({ "payload must be a table" }) end
	if type(d.requestId) ~= "string" or #d.requestId == 0 then
		table.insert(e, "missing requestId")
	end
	return vr(e)
end
-- ============================================================
-- COUPLE BREAKUP
-- ============================================================
function Validator.coupleBreakup(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table" then return vr({ "payload must be a table" }) end
	if type(d.requestId) ~= "string" or #d.requestId == 0 then
		table.insert(e, "missing requestId")
	end
	return vr(e)
end
-- ============================================================
-- ADMIN RESET TITLE
-- ============================================================
function Validator.adminResetTitle(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table" then return vr({ "payload must be a table" }) end
	if type(d.requestId) ~= "string" or #d.requestId == 0 then
		table.insert(e, "missing requestId")
	end
	if type(d.targetUsername) ~= "string" or #d.targetUsername == 0 then
		table.insert(e, "missing targetUsername")
	end
	return vr(e)
end
-- ============================================================
-- ADMIN SET TITLE
-- ============================================================
-- Validator.adminSetTitle dan Validator.adminSendGiftcard dihapus
-- (dead code - tidak dipakai, digantikan oleh adminSetTitleByUsername
--  dan adminSendGiftcardByUsername yang menerima targetUsername string)
-- Hard limits untuk titleStyle payload - cegah memory exhaustion
local TITLE_STYLE_MAX_COLOR_POINTS = 10   -- max entries di bgColors / textColors
local TITLE_STYLE_MAX_NEST_DEPTH   = 2    -- max depth untuk nested arrays
local TITLE_STYLE_MAX_SERIALIZED   = 2048 -- max serialized bytes untuk titleStyle
-- Validate structure depth dan ukuran titleStyle secara rekursif
local function validateStyleDepth(value: any, depth: number): boolean
	if depth > TITLE_STYLE_MAX_NEST_DEPTH then
		return false
	end
	if type(value) == "table" then
		local count = 0
		for k, v in pairs(value) do
			count += 1
			if count > TITLE_STYLE_MAX_COLOR_POINTS then
				return false
			end
			if type(v) == "table" and not validateStyleDepth(v, depth + 1) then
				return false
			end
		end
	end
	return true
end
function Validator.adminSetTitleByUsername(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table" then return vr({ "payload must be a table" }) end
	if type(d.requestId) ~= "string" or #d.requestId == 0 then
		table.insert(e, "missing requestId")
	end
	if type(d.targetUsername) ~= "string" or #d.targetUsername == 0 then
		table.insert(e, "missing targetUsername")
	end
	if type(d.title) ~= "string" or #d.title == 0 then
		table.insert(e, "missing title")
	end
	if type(d.title) == "string" and #d.title > 100 then
		table.insert(e, "title too long (max 100 chars)")
	end
	if type(d.titleSize) ~= "string" or #d.titleSize == 0 then
		table.insert(e, "missing titleSize")
	end
	local hasPreset = type(d.presetMode) == "string" and #d.presetMode > 0
	if hasPreset then
		if type(d.titleFont) == "string" and #d.titleFont > 64 then
			table.insert(e, "titleFont too long")
		end
	elseif type(d.titleStyle) ~= "table" then
		table.insert(e, "missing presetMode or titleStyle")
	else
		-- Validasi depth, ukuran, dan serialisasi titleStyle (legacy path)
		if not validateStyleDepth(d.titleStyle, 0) then
			table.insert(e, "titleStyle too large or too deep")
		else
			local ok, encoded = pcall(function()
				return HttpService:JSONEncode(d.titleStyle)
			end)
			if not ok then
				table.insert(e, "titleStyle not JSON-serializable")
			elseif #encoded > TITLE_STYLE_MAX_SERIALIZED then
				table.insert(e, ("titleStyle too large (%d bytes, max %d)"):format(
					#encoded, TITLE_STYLE_MAX_SERIALIZED
				))
			end
		end
	end
	return vr(e)
end
function Validator.adminSendGiftcardByUsername(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table" then return vr({ "payload must be a table" }) end
	if type(d.requestId) ~= "string" or #d.requestId == 0 then
		table.insert(e, "missing requestId")
	end
	if type(d.targetUsername) ~= "string" or #d.targetUsername == 0 then
		table.insert(e, "missing targetUsername")
	end
	if type(d.tier) ~= "string" or #d.tier == 0 then
		table.insert(e, "missing tier")
	end
	return vr(e)
end
-- ============================================================
-- OVERHEAD REQUEST REFRESH
-- ============================================================
function Validator.overheadRefresh(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table"            then return vr({ "payload must be a table" }) end
	if type(d.requestId) ~= "string" or #d.requestId == 0 then
		table.insert(e, "missing requestId")
	end
	return vr(e)
end
-- ============================================================
-- AVATAR CONTEXT LIKE
-- ============================================================
function Validator.avatarContextLike(d: any): VResult
	local e: {string} = {}
	if type(d) ~= "table" then
		return vr({ "payload must be a table" })
	end
	if type(d.requestId) ~= "string" or #d.requestId == 0 then
		table.insert(e, "missing requestId")
	end
	if type(d.targetUserId) ~= "number" then
		table.insert(e, "missing targetUserId")
	elseif d.targetUserId <= 0 then
		table.insert(e, "targetUserId must be positive")
	end
	if type(d.action) ~= "string" then
		table.insert(e, "missing action")
	elseif d.action ~= "like" and d.action ~= "unlike" then
		table.insert(e, "action must be like or unlike")
	end
	return vr(e)
end
-- ============================================================
-- HELPER: ukuran payload (cegah oversized payload exploit)
-- ============================================================
local MAX_PAYLOAD_BYTES = Config.Security.MAX_PAYLOAD_BYTES  -- dari Config, bukan magic number
function Validator.checkSize(d: any): (boolean, number)
	return Validator.checkSizeLimit(d, MAX_PAYLOAD_BYTES)
end

function Validator.checkSizeLimit(d: any, maxBytes: number): (boolean, number)
	local limit = math.max(0, math.floor(tonumber(maxBytes) or MAX_PAYLOAD_BYTES))
	local ok, encodedOrErr = pcall(function()
		return HttpService:JSONEncode(d)
	end)
	if not ok then
		log:warn("JSONEncode gagal saat checkSize", {
			error = tostring(encodedOrErr),
		})
		return false, -1
	end
	local encoded = encodedOrErr
	return #encoded <= limit, #encoded
end
-- ============================================================
-- SYNC DANCE
-- ============================================================
function Validator.animStart(animation: any, shouldPlay: any, speed: any, intent: any?): VResult
	local e: {string} = {}
	if typeof(animation) ~= "Instance" or not animation:IsA("Animation") then
		table.insert(e, "animation must be Animation")
	end
	if type(shouldPlay) ~= "boolean" then
		table.insert(e, "shouldPlay must be boolean")
	end
	if type(speed) ~= "number" then
		table.insert(e, "speed must be number")
	elseif speed < Config.Sync.MIN_SPEED or speed > Config.Sync.MAX_SPEED then
		table.insert(e, "speed out of range")
	end
	if intent ~= nil then
		if type(intent) ~= "string" then
			table.insert(e, "intent must be string")
		elseif intent ~= "play" and intent ~= "stop" and intent ~= "restart" then
			table.insert(e, "intent must be play, stop, or restart")
		elseif intent == "restart" and shouldPlay ~= true then
			table.insert(e, "restart intent requires shouldPlay=true")
		end
	end
	return vr(e)
end
function Validator.syncRequest(targetPlayer: any, condition: any, transferLead: any?): VResult
	local e: {string} = {}
	if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then
		table.insert(e, "targetPlayer must be Player")
	end
	if type(condition) ~= "boolean" then
		table.insert(e, "condition must be boolean")
	end
	if transferLead ~= nil and type(transferLead) ~= "boolean" then
		table.insert(e, "transferLead must be boolean or nil")
	end
	return vr(e)
end
function Validator.speedChange(speed: any): VResult
	local e: {string} = {}
	if type(speed) ~= "number" then
		table.insert(e, "speed must be number")
	elseif speed < Config.Sync.MIN_SPEED or speed > Config.Sync.MAX_SPEED then
		table.insert(e, "speed out of range")
	end
	return vr(e)
end
function Validator.favoritesUpdate(jsonData: any): VResult
	local e: {string} = {}
	if type(jsonData) ~= "string" then
		table.insert(e, "favorites payload must be string")
		return vr(e)
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(jsonData)
	end)
	if not ok or type(decoded) ~= "table" then
		table.insert(e, "favorites payload must be valid json object")
	end
	local favoritesMax = (Config.Favorites and Config.Favorites.MAX_PAYLOAD_BYTES) or MAX_PAYLOAD_BYTES
	if #jsonData > favoritesMax then
		table.insert(e, "favorites payload too large")
	end
	return vr(e)
end
function Validator.carryCommand(command: any): VResult
	local e: { string } = {}
	if type(command) ~= "table" then
		return vr({ "carry command must be table" })
	end
	if type(command.type) ~= "string" then
		table.insert(e, "missing type")
	elseif command.type ~= "REQUEST" and command.type ~= "ACCEPT" and command.type ~= "REJECT" and command.type ~= "END" then
		table.insert(e, "invalid carry command type")
	end
	if type(command.requestId) ~= "string" or #command.requestId == 0 or #command.requestId > 80 then
		table.insert(e, "invalid requestId")
	end
	if type(command.payload) ~= "table" then
		table.insert(e, "payload must be table")
		return vr(e)
	end
	if command.type == "REQUEST" then
		local payload = command.payload
		local targetUserId = payload.targetUserId
		if type(targetUserId) ~= "number" and type(payload.targetId) == "number" then
			targetUserId = payload.targetId
		end
		if type(targetUserId) ~= "number" then
			table.insert(e, "targetUserId must be number")
		elseif targetUserId == 0 or targetUserId ~= math.floor(targetUserId) then
			-- Studio Test Server clients use negative UserIds (-1, -2); only 0 is invalid.
			table.insert(e, "targetUserId must be non-zero integer")
		end
		if payload.targetName ~= nil and type(payload.targetName) ~= "string" then
			table.insert(e, "targetName must be string")
		end
		if type(payload.style) ~= "string" then
			table.insert(e, "style must be string")
		elseif not Config.Carry.STYLES[payload.style] then
			table.insert(e, "invalid style")
		end
	end
	return vr(e)
end
return Validator
