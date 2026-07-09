--!strict
-- Server/TagDonationDisplayRoots.server.luau
--
-- Applies the DonationDisplayRoot CollectionService tag to every Workspace
-- instance that hosts a donation SurfaceGui (LiveChatDonations, RunningText).
--
-- Why this exists:
--   CollectionService tags are stored in the place file, not in Rojo source.
--   Reloading from BASE.rbxm strips all runtime tags, which causes
--   DonationNotificationController to silently find zero roots and skip the
--   marquee loop entirely.  Running this script on every server start means
--   the tag is always present regardless of how the place was published.
--
-- Why the scan runs after a short delay:
--   Multiple instances with the same name (e.g., three "RunningText" Parts) may
--   not all be present in workspace:GetDescendants() in the very first frame
--   after a server starts.  A brief wait lets the engine settle so every
--   instance is discoverable before the scan runs.

-- 1. Services ─────────────────────────────────────────────────────────────────
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 2. Imports ──────────────────────────────────────────────────────────────────
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

-- 3. Constants ────────────────────────────────────────────────────────────────
local DISPLAY_ROOT_TAG = Config.Donation.DISPLAY_ROOT_TAG
local ROOT_NAMES: { string } = {
	Config.Donation.LIVE_CHAT_ROOT_NAME,
	Config.Donation.RUNNING_TEXT_ROOT_NAME,
}
-- Seconds to wait before the initial scan so all Parts are present.
local STARTUP_SETTLE_SECONDS = 2

-- 4. Module ───────────────────────────────────────────────────────────────────
local log = Logger.new("TagDonationDisplayRoots")

-- 5. Private helpers ──────────────────────────────────────────────────────────

--- Tags a single instance if not already tagged.
--- Returns true when a new tag was applied.
local function tagInstance(instance: Instance): boolean
	if CollectionService:HasTag(instance, DISPLAY_ROOT_TAG) then
		return false
	end
	CollectionService:AddTag(instance, DISPLAY_ROOT_TAG)
	log:info("Tagged donation display root", {
		name = instance.Name,
		path = instance:GetFullName(),
		tag = DISPLAY_ROOT_TAG,
	})
	return true
end

--- Scans all Workspace descendants and tags every instance whose name is in
--- ROOT_NAMES.  Returns the total number of newly-tagged instances.
local function scanAndTagAll(): number
	local nameSet: { [string]: boolean } = {}
	for _, name in ipairs(ROOT_NAMES) do
		nameSet[name] = true
	end

	local count = 0
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if nameSet[descendant.Name] then
			if tagInstance(descendant) then
				count += 1
			end
		end
	end
	return count
end

--- Connects a DescendantAdded listener so any instance added AFTER the initial
--- scan (e.g., streamed in later or dynamically parented) is also tagged.
--- Returns the connection so the caller can store it if needed.
local function watchForLateArrivals(): RBXScriptConnection
	local nameSet: { [string]: boolean } = {}
	for _, name in ipairs(ROOT_NAMES) do
		nameSet[name] = true
	end

	return workspace.DescendantAdded:Connect(function(descendant: Instance)
		if nameSet[descendant.Name] then
			tagInstance(descendant)
		end
	end)
end

-- 6. Startup ──────────────────────────────────────────────────────────────────

task.spawn(function()
	-- Wait for the engine to settle so all Parts with duplicate names are present.
	task.wait(STARTUP_SETTLE_SECONDS)

	local newlyTagged = scanAndTagAll()
	log:info("Initial scan complete", {
		newlyTagged = newlyTagged,
		totalTagged = #CollectionService:GetTagged(DISPLAY_ROOT_TAG),
	})

	-- Keep watching in case any root arrives after the initial scan.
	-- The connection is intentionally left open for the server's lifetime;
	-- server scripts do not clean up on shutdown (no PlayerRemoving pattern needed).
	watchForLateArrivals()
end)
