--!strict
-- Server/Persistence/GlobalDocWriter.luau
--
-- Writes a global document once per revision per experience (production hardening P3, plan §2 B).
-- Until P3 every server rewrote the event-board cache and the web music cache (Playlists + Tracks)
-- whenever it applied a revision — N servers, N blind writes of the same value, no retry, no size
-- check. Now:
--   * UpdateAsync whose transform cancels when the key's metadata already holds this revision, or a
--     revision another server fetched later (Shared/Domain/GlobalDocPolicy). The revision rides in
--     the key's DataStore metadata: the stored value keeps its shape and no new key is needed.
--   * a random start delay (0–START_DELAY_MAX_SEC) so overflow servers rarely race, BudgetGate, and
--     RETRY_DELAYS on failure;
--   * values over MAX_DOC_BYTES are refused (`doc_oversize` event + warning) — the DataStore limit
--     is 4 MB; above 1 MB the music library needs sharding (plan §2 B, not built: see ADR 0016).
-- Config.GlobalDocWriter.ENABLED = false: callers keep their pre-P3 SetAsync.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local BudgetGate = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetGate)
local BudgetMeter = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.BudgetMeter)
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)
local GlobalDocPolicy = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.GlobalDocPolicy)

export type WriteArgs = {
	store: DataStore,
	key: string,
	value: any, -- stored as-is (a table, or an already encoded JSON string)
	revision: string,
	fetchedAt: number, -- os.time() when this server fetched the revision from the VPS
	label: string, -- for logs, e.g. "event_board"
}

local GlobalDocWriter = {}

local log = Logger.new("GlobalDocWriter")
local budgetGate = BudgetGate.create({ logger = log, name = "GlobalDocWriter" })

local function cfg(): any
	local g = Config.GlobalDocWriter
	return if type(g) == "table" then g else {}
end

function GlobalDocWriter.isEnabled(): boolean
	return cfg().ENABLED == true
end

--- Encoded size in bytes of what would be stored.
function GlobalDocWriter.sizeOf(value: any): number
	if type(value) == "string" then
		return #value
	end
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	return if ok and type(encoded) == "string" then #encoded else math.huge
end

--- Yields (start delay + retries). Returns (true, "first" | "newer" | "same_revision" | "older")
--- when the transform ran (written or rightly cancelled), or (false, reason).
function GlobalDocWriter.writeIfNewer(args: WriteArgs): (boolean, string)
	local c = cfg()
	local bytes = GlobalDocWriter.sizeOf(args.value)
	local sizeOk, sizeReason = GlobalDocPolicy.checkSize(bytes, tonumber(c.MAX_DOC_BYTES) or 1000000)
	if not sizeOk then
		BudgetMeter.recordEvent("doc_oversize")
		log:warn("Global document too large; not written (the game keeps its in-memory copy)", {
			doc = args.label,
			key = args.key,
			bytes = bytes,
			maxBytes = c.MAX_DOC_BYTES,
		})
		return false, sizeReason or "doc_oversize"
	end
	task.wait(GlobalDocPolicy.startDelay(math.random(), tonumber(c.START_DELAY_MAX_SEC) or 20))

	local delays = if type(c.RETRY_DELAYS) == "table" then c.RETRY_DELAYS else { 2, 5, 15 }
	local lastError = "write_failed"
	for attempt = 0, #delays do
		if attempt > 0 then
			task.wait(delays[attempt])
		end
		local outcome = "unknown"
		local result = budgetGate:executeAsync(Enum.DataStoreRequestType.UpdateAsync, function()
			local ok, err = pcall(function()
				args.store:UpdateAsync(args.key, function(_old: any, keyInfo: DataStoreKeyInfo?): (any, any, any)
					local meta = nil
					if keyInfo then
						local metaOk, value = pcall(function()
							return keyInfo:GetMetadata()
						end)
						if metaOk then
							meta = value
						end
					end
					local should, reason = GlobalDocPolicy.shouldWrite(meta, args.revision, args.fetchedAt)
					outcome = reason
					if not should then
						return nil, nil, nil -- cancel: another server already holds this or a later one
					end
					return args.value, nil, GlobalDocPolicy.metadata(args.revision, args.fetchedAt, os.time())
				end)
			end)
			if ok then
				return { ok = true, value = nil }
			end
			return { ok = false, error = tostring(err) }
		end, "global::" .. args.key)
		if result.ok then
			if outcome == "first" or outcome == "newer" then
				log:info("Global document written", { doc = args.label, bytes = bytes, revision = args.revision })
			else
				BudgetMeter.recordEvent("global_doc_write_cancelled")
			end
			return true, outcome
		end
		lastError = tostring(result.error)
	end
	log:warn("Global document write failed after retries", { doc = args.label, error = lastError })
	return false, lastError
end

return GlobalDocWriter
