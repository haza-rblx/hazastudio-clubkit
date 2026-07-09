--!strict
-- InterestManager — Channel-based recipient filtering.
-- Players subscribe to interest channels (e.g., "dance:group_abc").
-- Broadcasts only reach players subscribed to the relevant channel.
--
-- This is the #1 bandwidth optimization for high-CCU sync scenarios.
-- Reduces recipients from ALL players to ONLY relevant players.
--
-- See: Guidelines/REF_ARCHITECTURE.md (Network Transport section)

-- ── Types ─────────────────────────────────────────────────────

type ChannelId = string

type InterestManagerDeps = {
    logger: any,
}

-- ── Factory ───────────────────────────────────────────────────

local function create(deps: InterestManagerDeps)
    local log = deps.logger

    -- channel → set of subscribed players
    local channels: { [ChannelId]: { [Player]: boolean } } = {}

    local self = {}

    --- Subscribe a player to a channel.
    --- Returns unsubscribe function (MUST be stored for cleanup).
    --- @param player Player -- The player to subscribe
    --- @param channel ChannelId -- Channel ID (e.g., "dance:group_abc", "stage:1")
    --- @return () -> () -- Unsubscribe function
    function self:subscribe(player: Player, channel: ChannelId): () -> ()
        if not channels[channel] then
            channels[channel] = {}
        end
        channels[channel][player] = true

        log:info("Player subscribed", {
            player = player.Name,
            channel = channel,
            subscriberCount = self:getCount(channel),
        })

        -- Return unsubscribe function
        return function()
            if channels[channel] then
                channels[channel][player] = nil
                -- Cleanup empty channels to prevent memory leak
                if not next(channels[channel]) then
                    channels[channel] = nil
                end
            end
        end
    end

    --- Get all active players in a channel.
    --- Automatically removes stale players (already left the game).
    --- @param channel ChannelId -- Channel to query
    --- @return { Player } -- List of active subscribers
    function self:getSubscribers(channel: ChannelId): { Player }
        local subs = channels[channel]
        if not subs then return {} end

        local result = {}
        for player in subs do
            -- Guard: remove stale players who left but weren't cleaned up
            if player.Parent then
                table.insert(result, player)
            else
                subs[player] = nil
            end
        end

        -- Cleanup empty channel after stale removal
        if not next(subs) then
            channels[channel] = nil
        end

        return result
    end

    --- Get subscriber count for a channel.
    --- Useful for logging and metrics.
    function self:getCount(channel: ChannelId): number
        local subs = channels[channel]
        if not subs then return 0 end

        local count = 0
        for player in subs do
            if player.Parent then
                count += 1
            else
                subs[player] = nil
            end
        end
        return count
    end

    --- Check if a player is subscribed to a channel.
    function self:isSubscribed(player: Player, channel: ChannelId): boolean
        local subs = channels[channel]
        if not subs then return false end
        return subs[player] == true
    end

    --- Get all channels a player is subscribed to.
    --- Useful for debugging and cleanup verification.
    function self:getPlayerChannels(player: Player): { ChannelId }
        local result = {}
        for channelId, subs in channels do
            if subs[player] then
                table.insert(result, channelId)
            end
        end
        return result
    end

    --- Remove player from ALL channels.
    --- MUST be called on PlayerRemoving to prevent memory leaks.
    function self:removePlayer(player: Player)
        local removedFrom = 0
        for channelId, subs in channels do
            if subs[player] then
                subs[player] = nil
                removedFrom += 1
                -- Cleanup empty channels
                if not next(subs) then
                    channels[channelId] = nil
                end
            end
        end

        if removedFrom > 0 then
            log:info("Player removed from all channels", {
                player = player.Name,
                channelCount = removedFrom,
            })
        end
    end

    --- Cleanup all channels and state.
    function self:destroy()
        table.clear(channels)
    end

    return self
end

return { create = create }
