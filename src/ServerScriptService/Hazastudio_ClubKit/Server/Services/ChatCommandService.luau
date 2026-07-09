--!strict
-- Register chat commands for TextChatService with legacy fallback + short idempotency window.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

export type CommandHandler = (player: Player, unfilteredText: string, requestId: string) -> ()

export type IChatCommandService = {
	register: (self: IChatCommandService, alias: string, handler: CommandHandler) -> (),
}

local function normalizeMessage(message: string): string
	local trimmed = message:match("^%s*(.-)%s*$") or ""
	return string.lower(trimmed)
end

local function createChatCommandService(): IChatCommandService
	local self = {} :: IChatCommandService
	local log = Logger.new("ChatCommandService")
	local processed: {[string]: number} = {}
	-- Always wire legacy Chatted fallback so commands work in Studio playtest
	-- where TextChatCommand.Triggered sometimes doesn't fire.
	-- remember() dedup prevents double-processing.
	local useLegacyChatFallback = true

	local function remember(requestId: string): boolean
		local now = os.clock()
		for key, expiresAt in pairs(processed) do
			if expiresAt <= now then
				processed[key] = nil
			end
		end

		if processed[requestId] and processed[requestId] > now then
			return false
		end

		processed[requestId] = now + Config.Security.CHAT_COMMAND_DEDUPE_WINDOW
		return true
	end

	local function buildRequestId(player: Player, message: string): string
		return ("%d:%s"):format(player.UserId, normalizeMessage(message))
	end

	local function shouldHandleAlias(message: string, alias: string): boolean
		local lowered = normalizeMessage(message)
		return lowered == ("/" .. alias) or string.sub(lowered, 1, #alias + 2) == ("/" .. alias .. " ")
	end

	function self:register(alias: string, handler: CommandHandler)
		local command = TextChatService:FindFirstChild(alias) :: TextChatCommand?
		if not command then
			local created = Instance.new("TextChatCommand")
			created.Name = alias
			created.PrimaryAlias = "/" .. alias
			created.Parent = TextChatService
			command = created
		end
		local textCommand = command :: TextChatCommand

		textCommand.Triggered:Connect(function(source: TextSource, unfilteredText: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if not player then
				return
			end

			local requestId = buildRequestId(player, unfilteredText)
			if not remember(requestId) then
				return
			end

			handler(player, unfilteredText, requestId)
		end)

		-- Always wire legacy fallback (Studio playtest compatibility).
		-- Dedup via remember() prevents double-fire when Triggered also fires.
		do
			local function wirePlayer(player: Player)
				player.Chatted:Connect(function(message: string)
					if not shouldHandleAlias(message, alias) then
						return
					end

					local requestId = buildRequestId(player, message)
					if not remember(requestId) then
						return
					end

					handler(player, message, requestId)
				end)
			end

			Players.PlayerAdded:Connect(wirePlayer)
			for _, player in ipairs(Players:GetPlayers()) do
				wirePlayer(player)
			end
		end

		log:info("Chat command registered", { alias = alias, legacy = useLegacyChatFallback })
	end

	return self
end

return createChatCommandService
