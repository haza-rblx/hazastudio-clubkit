--!strict
-- Talks to the licence server (ADR 0022): activate a code, redeem a guest pass, verify a licence.
-- Every call comes back as a LicensePolicy.Answer: ok, a definitive denial, or unreachable. In
-- Studio with the place attribute `CosmicDJ_LicenseStub` set, an in-memory stand-in answers instead,
-- so the lock can be tested before the real server exists.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LicensePolicy = require(ReplicatedStorage.CosmicDJ.Shared.LicensePolicy)
local Stamp = require(script.Parent.Parent.Stamp)

type Answer = LicensePolicy.Answer

local LicenseApi = {}

local BASE = "https://api.hazastudio.id/djx/v1"
local TIMEOUT = 15
-- reasons the server gives for a definitive "no"; anything else is treated as no answer
local DENIALS = {
	invalid_code = true,
	code_used = true,
	license_mismatch = true,
	universe_mismatch = true,
	owner_mismatch = true,
	revoked = true,
	expired = true,
}

-- who is asking: the place, its owner, and the download stamp (the second layer)
local function identity(): { [string]: any }
	return {
		universe_id = game.GameId,
		place_id = game.PlaceId,
		creator_id = game.CreatorId,
		creator_type = if game.CreatorType == Enum.CreatorType.Group then "Group" else "User",
		license_id = Stamp.licenseId,
		download_id = Stamp.downloadId,
		fingerprint = Stamp.fingerprint,
	}
end

local function classify(response: any): Answer
	local body: any = nil
	if type(response.Body) == "string" and response.Body ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, response.Body)
		body = if ok then decoded else nil
	end
	if response.Success and type(body) == "table" and body.ok == true then
		return {
			kind = "ok",
			licenseKind = if body.kind == "guest" then "guest" elseif body.kind == "full" then "full" else nil,
			licenseId = if type(body.license_id) == "string" then body.license_id else nil,
			expiresAt = tonumber(body.expires_at),
			secret = if type(body.secret) == "string" then body.secret else nil,
		}
	end
	local reason = if type(body) == "table" then body.error else nil
	if type(reason) == "string" and DENIALS[reason] then
		return { kind = "denied", reason = reason }
	end
	return { kind = "unreachable", detail = `HTTP {response.StatusCode}` }
end

local function post(path: string, payload: { [string]: any }, secret: string?): Answer
	local headers: { [string]: string } = { ["Content-Type"] = "application/json" }
	if secret then
		headers.Authorization = "Bearer " .. secret
	end
	local ok, response = pcall(
		HttpService.RequestAsync,
		HttpService,
		{
			Url = BASE .. path,
			Method = "POST",
			Headers = headers,
			Body = HttpService:JSONEncode(payload),
			Timeout = TIMEOUT,
		} :: any
	)
	if not ok then
		return { kind = "unreachable", detail = tostring(response) }
	end
	return classify(response)
end

-- ── the Studio stand-in ──
-- codes: "GUEST-…" a guest pass (GUEST-<n>M-… lasts n minutes, else 7 days), "BAD…" invalid,
-- "USED…" already used, anything else a full licence. Set `CosmicDJ_LicenseStubRevoke` to make
-- verify say revoked, `CosmicDJ_LicenseStubDown` to make every call unreachable.
local stubIssued: { [string]: { kind: LicensePolicy.Kind, licenseId: string, expiresAt: number? } } = {}

local function stubOn(): boolean
	return RunService:IsStudio() and workspace:GetAttribute("CosmicDJ_LicenseStub") == true
end

local function stubDown(): Answer?
	if workspace:GetAttribute("CosmicDJ_LicenseStubDown") == true then
		return { kind = "unreachable", detail = "stub: down" }
	end
	return nil
end

local function stubIssue(code: string, wantGuest: boolean): Answer
	local down = stubDown()
	if down then
		return down
	end
	local up = string.upper(code)
	if string.sub(up, 1, 3) == "BAD" then
		return { kind = "denied", reason = "invalid_code" }
	elseif string.sub(up, 1, 4) == "USED" then
		return { kind = "denied", reason = "code_used" }
	end
	local isGuest = string.sub(up, 1, 6) == "GUEST-"
	if isGuest ~= wantGuest then
		return { kind = "denied", reason = "invalid_code" }
	end
	local secret = "stub_" .. HttpService:GenerateGUID(false)
	local entry: { kind: LicensePolicy.Kind, licenseId: string, expiresAt: number? }
	if isGuest then
		local mins = tonumber(string.match(up, "^GUEST%-(%d+)M%-"))
		entry = {
			kind = "guest",
			licenseId = "stub-guest",
			expiresAt = os.time() + (if mins then mins * 60 else 7 * 86400),
		}
	else
		entry = { kind = "full", licenseId = "stub-full" }
	end
	stubIssued[secret] = entry
	return {
		kind = "ok",
		secret = secret,
		licenseKind = entry.kind,
		licenseId = entry.licenseId,
		expiresAt = entry.expiresAt,
	}
end

local function stubVerify(secret: string): Answer
	local down = stubDown()
	if down then
		return down
	end
	if workspace:GetAttribute("CosmicDJ_LicenseStubRevoke") == true then
		return { kind = "denied", reason = "revoked" }
	end
	local entry = stubIssued[secret]
	if not entry then
		-- a record from an earlier session: the stand-in forgets on restart, so it vouches for it
		return { kind = "ok" }
	end
	return { kind = "ok", licenseKind = entry.kind, expiresAt = entry.expiresAt }
end

-- ── calls ──

function LicenseApi.activate(code: string, userId: number): Answer
	if stubOn() then
		return stubIssue(code, false)
	end
	local payload = identity()
	payload.code = code
	payload.user_id = userId
	return post("/activate", payload)
end

function LicenseApi.redeem(code: string, userId: number): Answer
	if stubOn() then
		return stubIssue(code, true)
	end
	local payload = identity()
	payload.code = code
	payload.user_id = userId
	return post("/redeem", payload)
end

function LicenseApi.verify(secret: string): Answer
	if stubOn() then
		return stubVerify(secret)
	end
	return post("/verify", identity(), secret)
end

-- tells the licence server why this download refused to run here (a game mismatch, say). Fire
-- and forget: the answer is ignored, and a failure is silent.
function LicenseApi.beacon(reason: string)
	if stubOn() then
		print(`[CosmicDJ] licence beacon (stub): {reason}`)
		return
	end
	local payload = identity()
	payload.reason = reason
	task.spawn(function()
		pcall(post, "/beacon", payload)
	end)
end

function LicenseApi.usingStub(): boolean
	return stubOn()
end

return LicenseApi
