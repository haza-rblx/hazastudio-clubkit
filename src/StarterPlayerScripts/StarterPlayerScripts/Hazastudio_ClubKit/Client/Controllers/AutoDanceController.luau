--!strict
-- AutoDanceController (ClientController)
--
-- Shuffles dance emotes on a randomised interval while enabled. Ported from the
-- legacy HIERAPOLIS `AnimationsUI` "AUTO" button.
--
-- Client-only by design: every cycle goes through SyncController:onEmoteSelected,
-- so the server sees an ordinary emote selection — identical to a manual click.
-- No new remote, no server state, nothing persisted.
--
-- Two details carried over from the legacy implementation, both load-bearing:
--   * randomised gap (MIN..MAX) rather than a fixed one, so it does not read as robotic
--   * never repeat the animation that is already playing
-- The no-repeat rule matters MORE here than it did in legacy: Club Kit's
-- onEmoteSelected toggles an emote OFF when re-selected while playing, so a repeat
-- would silently stop the dance instead of continuing it.
--
-- SYNC INTERACTION (both directions are handled, and they must be):
--   auto ON -> then sync : auto switches ITSELF off (see the isSyncing subscription).
--       Without this, the shuffle loop keeps issuing its own emote picks, and
--       SyncService:onAnimationStart detaches the player from their leader
--       ("become our own root"). That path fires no notification, so the client
--       would keep a stale isSyncing = true — which in turn disables
--       onEmoteSelected's toggle-off branch and would leave STOP_ON_DISABLE
--       replaying the emote instead of stopping it. Turning auto off first
--       avoids that whole chain.
--   sync ON -> then auto : the sync is dropped (UNSYNC_ON_ENABLE), since
--       "follow this person" and "shuffle my own emotes" cannot both hold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

export type AutoDanceController = {
	isEnabled: (self: AutoDanceController) -> boolean,
	setEnabled: (self: AutoDanceController, enabled: boolean) -> (),
	toggle: (self: AutoDanceController) -> boolean,
	destroy: (self: AutoDanceController) -> (),
}

local function createAutoDanceController(deps: {
	syncController: any,
	animationLoader: any,
	onStateChanged: ((enabled: boolean) -> ())?,
	logger: any?,
})
	local log = deps.logger or Logger.new("Client.AutoDanceController")
	local syncController = deps.syncController
	local animationLoader = deps.animationLoader
	local onStateChanged = deps.onStateChanged

	assert(syncController ~= nil, "AutoDanceController requires syncController")
	assert(animationLoader ~= nil, "AutoDanceController requires animationLoader")

	local cfg = Config.AutoDance
	local minInterval = tonumber(cfg and cfg.MIN_INTERVAL) or 3
	local maxInterval = tonumber(cfg and cfg.MAX_INTERVAL) or 6
	if maxInterval < minInterval then
		maxInterval = minInterval
	end

	local controller = {} :: any

	local enabled = false
	-- Generation guard: a stale task.delay callback from a previous enable must not
	-- resurrect the loop after it was switched off (the legacy `isRunning` flag,
	-- hardened against rapid toggling).
	local generation = 0
	local lastAnimation: Animation? = nil
	local unsubscribeSync: (() -> ())? = nil

	local function isSyncing(): boolean
		local ok, syncing = pcall(function()
			local store = syncController.store
			return store ~= nil and store:get().isSyncing == true
		end)
		return ok and syncing == true
	end

	local function pickNext(pool: { Animation }): Animation?
		local count = #pool
		if count == 0 then
			return nil
		end
		if count == 1 then
			-- Single emote: replaying it would toggle it off, so hold it instead.
			return if pool[1] ~= lastAnimation then pool[1] else nil
		end
		local lastName = if lastAnimation then lastAnimation.Name else nil
		for _ = 1, 12 do
			local candidate = pool[math.random(1, count)]
			if candidate.Name ~= lastName then
				return candidate
			end
		end
		-- Bounded fallback: never spin forever if the pool is degenerate
		-- (e.g. every entry sharing one name).
		for _, candidate in ipairs(pool) do
			if candidate.Name ~= lastName then
				return candidate
			end
		end
		return nil
	end

	-- opts.skipStop: leave the current emote playing. Used when auto yields to a
	-- dance sync — the sync system is taking the animation over, and calling the
	-- stop path there would fight it (and hit the stale-isSyncing toggle branch).
	local function setEnabledInternal(nextEnabled: boolean, opts: { skipStop: boolean? }?)
		nextEnabled = nextEnabled == true
		if nextEnabled == enabled then
			return
		end
		enabled = nextEnabled
		generation += 1

		if enabled then
			-- Following a leader and shuffling your own emotes conflict; drop the sync.
			if cfg and cfg.UNSYNC_ON_ENABLE ~= false then
				pcall(function()
					if isSyncing() then
						syncController:onUnsync()
					end
				end)
			end
			lastAnimation = nil
			log:info("AutoDance enabled", { minInterval = minInterval, maxInterval = maxInterval })
			controller._step(generation)
		else
			local skipStop = opts ~= nil and opts.skipStop == true
			-- Re-selecting the playing emote toggles it off (SyncController semantics).
			if not skipStop and cfg and cfg.STOP_ON_DISABLE ~= false and lastAnimation then
				local target = lastAnimation
				pcall(function()
					syncController:onEmoteSelected(target)
				end)
			end
			lastAnimation = nil
			log:info("AutoDance disabled", { skipStop = skipStop })
		end

		if onStateChanged then
			pcall(function()
				onStateChanged(enabled)
			end)
		end
	end

	function controller._step(myGeneration: number)
		if not enabled or myGeneration ~= generation then
			return
		end

		-- Belt-and-braces: if a sync started between ticks and the subscription has
		-- not run yet, yield rather than stealing the animation back from the leader.
		if isSyncing() then
			log:info("AutoDance yielding to dance sync (detected in loop)")
			setEnabledInternal(false, { skipStop = true })
			return
		end

		local ok, pool = pcall(function()
			return animationLoader.getAnimationsByCategory("Dance")
		end)
		if not ok or type(pool) ~= "table" then
			log:warn("AutoDance could not load dance animations; stopping")
			setEnabledInternal(false, { skipStop = true })
			return
		end

		local nextAnim = pickNext(pool)
		if nextAnim then
			lastAnimation = nextAnim
			local fired = pcall(function()
				syncController:onEmoteSelected(nextAnim)
			end)
			if not fired then
				log:warn("AutoDance emote selection failed", { animation = nextAnim.Name })
			end
		end

		local delay = minInterval + math.random() * (maxInterval - minInterval)
		task.delay(delay, function()
			controller._step(myGeneration)
		end)
	end

	-- Sync wins: the moment the player joins a leader, auto stands down.
	pcall(function()
		local store = syncController.store
		if store and type(store.subscribe) == "function" then
			unsubscribeSync = store:subscribe("isSyncing", function(nowSyncing)
				if nowSyncing == true and enabled then
					log:info("AutoDance disabled: player joined a dance sync")
					setEnabledInternal(false, { skipStop = true })
				end
			end)
		end
	end)

	function controller:isEnabled(): boolean
		return enabled
	end

	function controller:setEnabled(nextEnabled: boolean): ()
		setEnabledInternal(nextEnabled, nil)
	end

	function controller:toggle(): boolean
		setEnabledInternal(not enabled, nil)
		return enabled
	end

	function controller:destroy(): ()
		enabled = false
		generation += 1
		lastAnimation = nil
		if unsubscribeSync then
			pcall(unsubscribeSync)
			unsubscribeSync = nil
		end
	end

	return controller
end

return createAutoDanceController
