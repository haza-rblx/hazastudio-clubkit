--!strict
-- Who may do what. Pure functions, so the server enforces exactly what the client shows.
local Types = require(script.Parent.Types)

local Rules = {}

export type Caps = {
	canOpen: boolean,
	canEditLibrary: boolean,
	canEditAccess: boolean,
	canEditSettings: boolean,
}

local NONE: Caps = { canOpen = false, canEditLibrary = false, canEditAccess = false, canEditSettings = false }

-- Owner: everything. Residents: the decks and the library. Guests (listed or let in by a group
-- rank / game pass): the decks only.
function Rules.caps(role: Types.Role?): Caps
	if role == "Owner" then
		return { canOpen = true, canEditLibrary = true, canEditAccess = true, canEditSettings = true }
	elseif role == "Resident" then
		return { canOpen = true, canEditLibrary = true, canEditAccess = false, canEditSettings = false }
	elseif role == "Guest" then
		return { canOpen = true, canEditLibrary = false, canEditAccess = false, canEditSettings = false }
	end
	return NONE
end

-- may `role` take the booth from someone who is playing? policy: 1 owner, 2 residents, 3 any DJ
function Rules.canTakeOver(role: Types.Role?, policy: number): boolean
	if role == "Owner" then
		return true
	elseif role == "Resident" then
		return policy >= 2
	elseif role == "Guest" then
		return policy >= 3
	end
	return false
end

-- a guest's access has ended
function Rules.guestExpired(p: Types.Person, now: number): boolean
	return p.role == "Guest" and p.endsAt ~= nil and now >= p.endsAt
end

-- the unix time a guest's access ends for an "Access ends" choice (1 = server close: nil)
function Rules.guestEndsAt(choice: number, now: number, utcOffsetHours: number?): number?
	if choice == 2 then
		return now + 3600
	elseif choice == 3 then
		-- 23:00 tonight in the venue's time (UTC+7 by default, the owner's WIB)
		local off = (utcOffsetHours or 7) * 3600
		local localNow = now + off
		local dayStart = localNow - localNow % 86400
		local target = dayStart + 23 * 3600
		if target <= localNow then
			target += 86400
		end
		return target - off
	end
	return nil
end

return Rules
