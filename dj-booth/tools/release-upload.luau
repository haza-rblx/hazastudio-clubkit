--!nocheck
-- Completes a djX release when tools/release stops at its `bash` build step on Windows:
-- the build is already done (rojo + package ran), so this skips steps 1-3 and does the upload.
--   lune run tools/release-upload [--api <base>]
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local TEMPLATE = "build/djx-template.rbxm"
local CLIENT = "dj-booth release.luau"

local function fail(message)
	print("release: " .. message)
	process.exit(1)
end

local function api(): string
	for i, arg in process.args do
		if arg == "--api" and process.args[i + 1] then
			return (string.gsub(process.args[i + 1], "/+$", ""))
		end
	end
	local env = process.env.DJX_API
	return if env and env ~= "" then (string.gsub(env, "/+$", "")) else "https://api.hazastudio.id"
end

local function version(): string
	local toml = fs.readFile("wally.toml")
	local v = string.match(toml, '\nversion%s*=%s*"([^"]+)"')
	if not v or not string.match(v, "^[0-9A-Za-z._-]+$") or #v > 32 then
		fail("no usable version in wally.toml")
	end
	return v
end

local function post(url: string, body: { [string]: any })
	local ok, res = pcall(net.request, {
		url = url,
		method = "POST",
		headers = { ["content-type"] = "application/json" },
		body = serde.encode("json", body),
	})
	if not ok then
		fail("can't reach " .. url .. ": " .. tostring(res))
	end
	local decoded = if res.body ~= "" then select(2, pcall(serde.decode, "json", res.body)) else nil
	return res.statusCode, if type(decoded) == "table" then decoded else {}
end

local function openBrowser(url: string)
	if process.env.DJX_NO_BROWSER == "1" then
		return
	end
	if process.os == "windows" then
		process.spawn("cmd", { "/c", "start", "", url })
	else
		process.spawn("xdg-open", { url })
	end
end

if not fs.isFile(TEMPLATE) then
	fail(TEMPLATE .. " is not built")
end
local bytes = fs.readFile(TEMPLATE)
if string.sub(bytes, 1, 8) ~= "<roblox!" then
	fail(TEMPLATE .. " is not a binary model")
end
if #bytes < 100 * 1024 or #bytes > 8 * 1024 * 1024 then
	fail(`{TEMPLATE} is {#bytes} bytes, outside 100 KB – 8 MB`)
end

local v = version()
local sha = serde.hash("sha256", bytes)
local base = api()
print(`· template {v}: {math.floor(#bytes / 1024)} KB, sha256 {string.sub(sha, 1, 12)}`)

local status, device = post(base .. "/djx/v1/device", {
	scope = "template_upload",
	client = CLIENT,
	version = v,
	sha256 = sha,
	size = #bytes,
})
if status ~= 200 or not device.device_code then
	fail(`device request refused ({status} {device.error or ""})`)
end
print("")
print(`  Approve this upload in your browser:  {device.verification_url}`)
print(`  Code: {device.user_code}`)
print("")
openBrowser(device.verification_url)

local interval = math.max(2, tonumber(device.interval) or 3)
local deadline = os.clock() + (tonumber(device.expires_in) or 600)
local grant
while not grant do
	if os.clock() > deadline then
		fail("the approval timed out")
	end
	task.wait(interval)
	local code, body = post(base .. "/djx/v1/device/token", { device_code = device.device_code })
	if code == 200 and body.grant then
		grant = body.grant
	elseif body.error == "access_denied" then
		fail("the upload was denied")
	elseif body.error == "expired_token" then
		fail("the approval expired; run the release again")
	elseif body.error ~= "authorization_pending" then
		fail(`unexpected answer ({code} {body.error or ""})`)
	end
end
print("· approved")

local ok, res = pcall(net.request, {
	url = base .. "/admin/djx/template",
	method = "PUT",
	headers = {
		authorization = "Bearer " .. grant,
		["content-type"] = "application/octet-stream",
		["x-djx-version"] = v,
	},
	body = bytes,
})
grant = nil
if not ok then
	fail("upload failed: " .. tostring(res))
end
local okBody, result = pcall(serde.decode, "json", res.body)
if res.statusCode ~= 200 or not okBody or not result.template then
	fail(`upload refused ({res.statusCode} {if okBody and result.error then result.error else ""})`)
end
if result.template.sha256 ~= sha then
	fail("the server stored a different file (sha256 mismatch)")
end

print(`released djX {v} ({math.floor(#bytes / 1024)} KB, sha256 {string.sub(sha, 1, 12)})`)
