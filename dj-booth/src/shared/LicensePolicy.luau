--!strict
-- The licence rules (ADR 0022), pure: what a stored licence record means at a given time, how a
-- licence server answer changes it, and how codes and attempts are checked. The server keeps the
-- record (with its secret); clients only ever see a View.
local LicensePolicy = {}

export type Kind = "full" | "guest"

-- the record the server keeps in its DataStore; `secret` never leaves the server
export type Record = {
	v: number,
	secret: string,
	kind: Kind,
	licenseId: string,
	expiresAt: number?, -- guest passes only (unix seconds)
	startedAt: number?, -- when this licence was activated here (the guest pass bar's start)
	lastOkAt: number, -- the last time the licence server said yes (unix seconds)
	denied: string?, -- a definitive "no" from the licence server; sticky until a later yes
}

-- locked: never activated · active: a full licence · guest: a guest pass still running ·
-- expired: the guest pass ran out · offline: not confirmed for longer than the grace ·
-- denied: the licence server said no (revoked, moved, mismatched)
export type Status = "locked" | "active" | "guest" | "expired" | "offline" | "denied"

export type View = {
	status: Status,
	kind: Kind?,
	expiresAt: number?,
	startedAt: number?, -- guest passes: when the pass started
	secondsLeft: number?, -- guest passes: time left on the pass
	reason: string?, -- denied: why
}

-- what a call to the licence server came back with
export type Answer =
	{ kind: "ok", licenseKind: Kind?, licenseId: string?, expiresAt: number?, secret: string? }
	| { kind: "denied", reason: string }
	| { kind: "unreachable", detail: string? }

LicensePolicy.GRACE = 7 * 86400 -- an activated game keeps playing this long without a confirmation
LicensePolicy.VERIFY_EVERY = 1800
LicensePolicy.CODE_MIN = 8
LicensePolicy.CODE_MAX = 128
LicensePolicy.ATTEMPTS = 5 -- activation attempts per player per window
LicensePolicy.ATTEMPT_WINDOW = 600

function LicensePolicy.evaluate(rec: Record?, now: number): View
	if not rec then
		return { status = "locked" }
	end
	if rec.denied then
		return { status = "denied", kind = rec.kind, reason = rec.denied }
	end
	if rec.kind == "guest" then
		local ends = rec.expiresAt or 0
		if now >= ends then
			return { status = "expired", kind = "guest", expiresAt = ends }
		end
	end
	-- a guest pass that ends before the grace does is judged by its end, never stretched by it
	if now - rec.lastOkAt > LicensePolicy.GRACE then
		return { status = "offline", kind = rec.kind, expiresAt = rec.expiresAt }
	end
	if rec.kind == "guest" then
		local ends = rec.expiresAt :: number
		return {
			status = "guest",
			kind = "guest",
			expiresAt = ends,
			startedAt = rec.startedAt,
			secondsLeft = ends - now,
		}
	end
	return { status = "active", kind = "full" }
end

function LicensePolicy.unlocked(view: View): boolean
	return view.status == "active" or view.status == "guest"
end

-- a verify answer applied to the record: a yes refreshes it (and clears a denial), a no sticks,
-- no answer leaves it as it was (the grace decides)
function LicensePolicy.applyVerify(rec: Record, answer: Answer, now: number): Record
	local out = table.clone(rec)
	if answer.kind == "ok" then
		out.lastOkAt = now
		out.denied = nil
		if answer.licenseKind then
			out.kind = answer.licenseKind
		end
		-- a full licence has no end; a guest pass keeps its end unless the server sends a new one
		out.expiresAt = if out.kind == "guest" then answer.expiresAt or out.expiresAt else nil
	elseif answer.kind == "denied" then
		out.denied = answer.reason
	end
	return out
end

-- the record an accepted activation or guest pass starts; nil if the answer lacks what it needs
function LicensePolicy.fromActivation(answer: Answer, now: number): Record?
	if answer.kind ~= "ok" or not answer.secret or not answer.licenseId then
		return nil
	end
	local kind: Kind = answer.licenseKind or "full"
	if kind == "guest" and not answer.expiresAt then
		return nil
	end
	return {
		v = 1,
		secret = answer.secret,
		kind = kind,
		licenseId = answer.licenseId,
		expiresAt = if kind == "guest" then answer.expiresAt else nil,
		startedAt = now,
		lastOkAt = now,
		denied = nil,
	}
end

-- two servers saving at once: keep the newest confirmation, and a denial wins over a stale yes
function LicensePolicy.merge(old: Record?, new: Record): Record
	if not old or old.secret ~= new.secret then
		return new
	end
	local out = table.clone(new)
	if old.lastOkAt > out.lastOkAt then
		out.lastOkAt = old.lastOkAt
		out.denied = old.denied
		out.kind = old.kind
		out.expiresAt = old.expiresAt
	end
	return out
end

-- a pasted code, trimmed; nil when it can't be a code (so it never reaches the licence server)
function LicensePolicy.normalizeCode(raw: string): string?
	local code = string.gsub(raw, "%s", "")
	if #code < LicensePolicy.CODE_MIN or #code > LicensePolicy.CODE_MAX then
		return nil
	end
	if string.find(code, "[^%w%-_]") then
		return nil
	end
	return code
end

-- a sliding window of attempt times: whether one more is allowed now, and the window kept
function LicensePolicy.allowAttempt(times: { number }, now: number): (boolean, { number })
	local kept = {}
	for _, t in times do
		if now - t < LicensePolicy.ATTEMPT_WINDOW then
			table.insert(kept, t)
		end
	end
	if #kept >= LicensePolicy.ATTEMPTS then
		return false, kept
	end
	table.insert(kept, now)
	return true, kept
end

-- "5 days 4 h left", "3 h 20 min left", "12 min left"
function LicensePolicy.leftText(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local days, hours, mins = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
	if days > 0 then
		return `{days} day{if days == 1 then "" else "s"} {hours} h left`
	elseif hours > 0 then
		return `{hours} h {mins} min left`
	end
	return `{math.max(mins, if s > 0 then 1 else 0)} min left`
end

-- a place's game: its universe and owner (a User or a Group)
export type GameIdentity = { universeId: number, ownerId: number, ownerType: string }

-- why a download stamped for `stamp` does not belong in the place `here`; nil when it does, or
-- when the download is not pre-bound (universeId 0, a dev download)
function LicensePolicy.gameMismatch(stamp: GameIdentity, here: GameIdentity): string?
	if stamp.universeId == 0 then
		return nil
	end
	if here.universeId ~= stamp.universeId then
		return "universe_mismatch"
	end
	if here.ownerId ~= stamp.ownerId or here.ownerType ~= stamp.ownerType then
		return "owner_mismatch"
	end
	return nil
end

return LicensePolicy
