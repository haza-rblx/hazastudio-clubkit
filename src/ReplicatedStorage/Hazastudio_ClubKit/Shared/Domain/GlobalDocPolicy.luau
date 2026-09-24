--!strict
-- Shared/Domain/GlobalDocPolicy.luau
--
-- Rules for global documents that every server of an experience would otherwise rewrite
-- (production hardening P3, workstream B): the event-board cache ("board" in EventBoardCache_v1)
-- and the web music cache (Playlists / Tracks in the music store). Server/Persistence/
-- GlobalDocWriter runs UpdateAsync with these rules; this module is pure (spec:
-- .tmp/global-doc-policy-spec.luau).
--
-- Revisions are content hashes (no order), so "newer" is decided by when the server fetched the
-- revision from the VPS. Both ride in the key's DataStore *metadata*, so the stored value keeps
-- its shape (older kits read it unchanged) and no new key is needed.
--   same revision stored            → cancel (another server already wrote it)
--   stored revision fetched later   → cancel (ours is older)
--   otherwise                       → write

export type Meta = { rev: string?, fetchedAt: any?, writtenAt: any? }

local MAX_REV_CHARS = 128 -- DataStore metadata is limited to 300 characters in total

local GlobalDocPolicy = {}

function GlobalDocPolicy.shouldWrite(stored: Meta?, revision: string, fetchedAt: number): (boolean, string)
	if type(stored) ~= "table" or type(stored.rev) ~= "string" or stored.rev == "" then
		return true, "first"
	end
	if stored.rev == string.sub(revision, 1, MAX_REV_CHARS) then
		return false, "same_revision"
	end
	local storedFetchedAt = tonumber(stored.fetchedAt) or 0
	if storedFetchedAt > fetchedAt then
		return false, "older"
	end
	return true, "newer"
end

function GlobalDocPolicy.metadata(revision: string, fetchedAt: number, writtenAt: number): { [string]: any }
	return {
		rev = string.sub(revision, 1, MAX_REV_CHARS),
		fetchedAt = fetchedAt,
		writtenAt = writtenAt,
	}
end

function GlobalDocPolicy.checkSize(bytes: number, maxBytes: number): (boolean, string?)
	if bytes > maxBytes then
		return false, "doc_oversize"
	end
	return true, nil
end

--- Random start delay so overflow servers that fetched the same revision rarely collide.
function GlobalDocPolicy.startDelay(random01: number, maxSec: number): number
	return math.clamp(random01, 0, 1) * math.max(0, maxSec)
end

return GlobalDocPolicy
