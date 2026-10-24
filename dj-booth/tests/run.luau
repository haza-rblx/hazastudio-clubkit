--!nocheck
-- Unit tests for the pure shared modules (Mix, Queue, Rules, Format, Dict), run with Lune:
--   lune run tests/run
-- A tiny loader resolves the Roblox-style `require(script.Parent.X)` to files in src/shared.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local SHARED = "src/shared/"
local cache = {}

local function load(name)
	if cache[name] then
		return cache[name]
	end
	local source = fs.readFile(SHARED .. name .. ".luau")
	local folder = setmetatable({}, {
		__index = function(_, child)
			return { __module = child }
		end,
	})
	local env = setmetatable({
		script = { Parent = folder },
		require = function(m)
			return load(m.__module)
		end,
		-- the few Roblox globals the shared modules touch
		Color3 = {
			new = function(r, g, b)
				return { R = r, G = g, B = b }
			end,
		},
	}, { __index = _G })
	local fn = luau.load(source, { debugName = name, environment = env })
	local result = fn()
	cache[name] = result
	return result
end

local failures, passed = 0, 0
local function check(label, cond)
	if cond then
		passed += 1
	else
		failures += 1
		print("FAIL  " .. label)
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

-- Format
local Format = load("Format")
check("mmss 0", Format.mmss(0) == "0:00")
check("mmss 372", Format.mmss(372) == "6:12")
check("mmss nil", Format.mmss(nil) == "—")
check("mmss rounds", Format.mmss(59.6) == "1:00")
check("clock", Format.clock(73.2) == "01:13.2")
check("initials two words", Format.initials("Mirror Lake") == "ML")
check("initials one word", Format.initials("Kuro") == "KU")
check("effective bpm", Format.effectiveBpm(124, 1.05) == 130)
check("effective bpm nil", Format.effectiveBpm(nil, 1) == nil)
check("plural", Format.plural(1) == "1 Track" and Format.plural(4) == "4 Tracks")
check("ago today", Format.ago(1000, 1000 + 3600) == "Today")
check("ago 2 days", Format.ago(0, 2 * 86400 + 5) == "2 days ago")
check("ago last week", Format.ago(0, 8 * 86400) == "Last week")
check("ago never", Format.ago(nil, 0) == "Never")

-- Mix
local Mix = load("Mix")
check("eq flat", Mix.eqDb(0.5) == 0)
check("eq max", near(Mix.eqDb(1), 12))
check("eq label flat", Mix.eqLabel(0.5) == "0 dB")
check("eq label +1.2", Mix.eqLabel(0.55) == "+1.2 dB")
check("filter off", Mix.filterLabel(0.5) == "OFF")
check("filter lpf 40", Mix.filterLabel(0.3) == "LPF 40%")
check("filter hpf 100", Mix.filterLabel(1) == "HPF 100%")
local a, b = Mix.crossfade(0, 0)
check("xfade A end", near(a, 1) and near(b, 0))
a, b = Mix.crossfade(0.5, 0)
check("xfade centre constant power", near(a * a + b * b, 1))
a, b = Mix.crossfade(0.51, 0)
check("xfade centre magnet", near(a, b))
a, b = Mix.crossfade(0.98, 0)
check("xfade dead zone", near(b, 1) and near(a, 0, 1e-9))
local h, m, l = Mix.eqGains({ 0.5, 0.5, 0 }, 0.5)
check("eq kill", l == -80 and h == 0 and m == 0)
h = Mix.eqGains({ 0.5, 0.5, 0.5 }, 0)
check("lpf cuts highs", h <= -59)
check("pitch label", Mix.pitchLabel(0.016) == "+1.6%")
check("speed label", Mix.speedLabel(0) == "1.0X")
check("gain", near(Mix.dbToGain(0), 1) and near(Mix.dbToGain(-6), 0.501, 0.001))

-- Dict
local Dict = load("Dict")
local t = table.freeze({ a = 1, b = { c = 2 } })
local t2 = Dict.setIn(t, { "b", "c" }, 3)
check("setIn copies", t.b.c == 2 and t2.b.c == 3 and t2.a == 1)
local t3 = Dict.merge(t, { a = Dict.None, d = 4 })
check("merge None removes", t3.a == nil and t3.d == 4)
check("insert/remove", #Dict.removeValue(Dict.insert({ 1, 2 }, 3), 2) == 2)

-- Queue
local Queue = load("Queue")
local q = {}
q = Queue.add(q, "t1")
q = Queue.add(q, "t2")
q = Queue.add(q, "t3")
check("queue add keeps order", q[1].trackId == "t1" and q[3].trackId == "t3")
check("queue move one place", Queue.move(q, q[1].key, 1)[2].trackId == "t1")
check("queue move clamps at the top", Queue.move(q, q[3].key, -5)[1].trackId == "t3")
check("queue move no-op returns q", Queue.move(q, q[1].key, -1) == q)
local e, rest = Queue.pop(q)
check("queue pops the first", e.trackId == "t1" and #rest == 2 and rest[1].trackId == "t2")
check("queue addMany in order", #Queue.addMany(q, { "a", "b" }) == 5 and Queue.addMany(q, { "a" })[4].trackId == "a")
check("queue prune", #Queue.prune(q, { t1 = {}, t3 = {} }) == 2)
check("queue remove", #Queue.remove(q, q[2].key) == 2)

-- Rules
local Rules = load("Rules")
check("owner caps", Rules.caps("Owner").canEditAccess)
check(
	"resident edits library only",
	Rules.caps("Resident").canEditLibrary and not Rules.caps("Resident").canEditSettings
)
check("guest plays only", Rules.caps("Guest").canOpen and not Rules.caps("Guest").canEditLibrary)
check("nobody", not Rules.caps(nil).canOpen)
check("take over: owner always", Rules.canTakeOver("Owner", 1))
check("take over: residents policy", Rules.canTakeOver("Resident", 2) and not Rules.canTakeOver("Resident", 1))
check("take over: guests only any", Rules.canTakeOver("Guest", 3) and not Rules.canTakeOver("Guest", 2))
local now = 1_800_000_000
check("guest 1 hour", Rules.guestEndsAt(2, now) == now + 3600)
check("guest server close", Rules.guestEndsAt(1, now) == nil)
local at = Rules.guestEndsAt(3, now, 7)
check("guest 23:00 local", at and ((at + 7 * 3600) % 86400) == 23 * 3600 and at > now and at - now <= 86400)
check("guest expired", Rules.guestExpired({ role = "Guest", endsAt = now - 1 }, now))
check("resident never expires", not Rules.guestExpired({ role = "Resident", endsAt = now - 1 }, now))

-- deck fixtures: only the fields a test changes are passed in
local function deckOf(p)
	local d = {
		trackId = "t1",
		playing = false,
		pos = 0,
		at = 0,
		cue = 0,
		pitch = 0,
		synced = false,
		eq = { 0.5, 0.5, 0.5 },
		filter = 0.5,
		vol = 1,
		fx = { 0, 0, 0 },
	}
	for k, v in p do
		d[k] = v
	end
	return d
end
local function trackOf(p)
	local t = {
		id = "t1",
		assetId = 1,
		title = "",
		artist = "",
		speed = 1,
		gain = 0,
		start = 0,
		status = "ready",
		added = 1,
		len = 200,
	}
	for k, v in p do
		t[k] = v
	end
	return t
end

-- DeckClock
local DeckClock = load("DeckClock")
check("rate pitch + speed", near(DeckClock.rate(deckOf({ pitch = 0.1 }), trackOf({ speed = 1.2 })), 1.32))
check("rate without track", near(DeckClock.rate(deckOf({ pitch = 0.1 }), nil), 1.1))
check("rate pitch -0.5", near(DeckClock.rate(deckOf({ pitch = -0.5 }), trackOf({})), 0.5))
check(
	"position playing",
	near(DeckClock.position(deckOf({ playing = true, pos = 10, at = 100 }), trackOf({}), 104), 14)
)
check("position paused holds pos", near(DeckClock.position(deckOf({ pos = 10, at = 100 }), trackOf({}), 104), 10))
check(
	"position with pitch",
	near(
		DeckClock.position(deckOf({ playing = true, pos = 10, at = 100, pitch = 0.1 }), trackOf({ speed = 1.2 }), 105),
		16.6
	)
)
check("position never below 0", DeckClock.position(deckOf({ playing = true, pos = 0, at = 100 }), trackOf({}), 90) == 0)
check("position without track", DeckClock.position(deckOf({ playing = true, pos = 12, at = 0 }), nil, 50) == 12)
check(
	"timeLeft at speed 1.25",
	near(DeckClock.timeLeft(deckOf({ playing = true, pos = 50 }), trackOf({ speed = 1.25 }), 0), 120)
)
check(
	"timeLeft with pitch 0.1",
	near(DeckClock.timeLeft(deckOf({ playing = true, pos = 50, pitch = 0.1 }), trackOf({}), 0), 136.3636364, 1e-6)
)
check("timeLeft min 0", DeckClock.timeLeft(deckOf({ playing = true, pos = 300 }), trackOf({}), 0) == 0)
check("timeLeft unknown length is nil", DeckClock.timeLeft(deckOf({ playing = true }), trackOf({ len = 0 }), 0) == nil)
check(
	"timeLeft uses fallback",
	near(DeckClock.timeLeft(deckOf({ playing = true, pos = 50 }), trackOf({ len = 0 }), 0, 100), 50)
)
check("length from track", DeckClock.length(trackOf({ len = 200 })) == 200)
check("length falls back when len is 0", DeckClock.length(trackOf({ len = 0 }), 180) == 180)
check("length unknown is nil", DeckClock.length(trackOf({ len = 0 })) == nil)
check("length without track uses fallback", DeckClock.length(nil, 90) == 90)
check("length negative fallback is nil", DeckClock.length(nil, -5) == nil)
check("length nothing is nil", DeckClock.length(nil) == nil)
check("ended at len - 0.05", DeckClock.ended(deckOf({ playing = true, pos = 199.95 }), trackOf({}), 0) == true)
check("not ended 0.06 early", DeckClock.ended(deckOf({ playing = true, pos = 199.9 }), trackOf({}), 0) == false)
check("paused never ended", DeckClock.ended(deckOf({ pos = 199.99 }), trackOf({}), 0) == false)
check(
	"ended with fallback length",
	DeckClock.ended(deckOf({ playing = true, pos = 99.96 }), trackOf({ len = 0 }), 0, 100) == true
)
check(
	"ended false when length unknown",
	DeckClock.ended(deckOf({ playing = true, pos = 500 }), trackOf({ len = 0 }), 0) == false
)
check("drifted default 1.5", DeckClock.drifted(10, 11.6) and not DeckClock.drifted(10, 11.5))
check("drifted is symmetric", DeckClock.drifted(11.6, 10))
check("drifted custom tolerance", DeckClock.drifted(10, 10.6, 0.5) and not DeckClock.drifted(10, 10.4, 0.5))

-- LoadPolicy
local LoadPolicy = load("LoadPolicy")
check("policy constants", LoadPolicy.MAX_ATTEMPTS == 6 and LoadPolicy.CYCLE_DELAY == 8)
check("policy watchdog and caps", LoadPolicy.WATCHDOG_INTERVAL == 2 and LoadPolicy.PRELOAD_CAP_DESKTOP == 300)
check("policy mobile cap and concurrency", LoadPolicy.PRELOAD_CAP_MOBILE == 15 and LoadPolicy.PRELOAD_CONCURRENCY == 8)
check("timeout touch 30", LoadPolicy.timeout(true) == 30)
check("timeout desktop 25", LoadPolicy.timeout(false) == 25)
local backoffs = { 1.5, 3, 4.5, 6, 7.5, 8, 8 }
local backoffOk = true
for i, want in backoffs do
	backoffOk = backoffOk and near(LoadPolicy.backoff(i), want)
end
check("backoff 1..7 caps at 8", backoffOk)
check("contentId attempt 1 asset", LoadPolicy.contentId(123, 1) == "rbxassetid://123")
check("contentId attempt 2 web", LoadPolicy.contentId(123, 2) == "https://www.roblox.com/asset/?id=123")
check(
	"contentId alternates",
	LoadPolicy.contentId(123, 3) == "rbxassetid://123"
		and LoadPolicy.contentId(123, 6) == "https://www.roblox.com/asset/?id=123"
)
check("contentId large id", LoadPolicy.contentId(9876543210, 1) == "rbxassetid://9876543210")

-- DeckParams
local DeckParams = load("DeckParams")
local function sessionOf(p)
	local s = { xfader = 0, curve = 0, master = 1 }
	for k, v in p or {} do
		s[k] = v
	end
	return s
end
local function settingsOf(p)
	local s = { volume = 100, keyLock = false, limiter = false, normalize = false }
	for k, v in p or {} do
		s[k] = v
	end
	return s
end
local function paramsOf(n, d, t, s, st)
	return DeckParams.deck(n, deckOf(d or {}), trackOf(t or {}), sessionOf(s), settingsOf(st))
end
check("deck1 at A is full", near(paramsOf(1, {}, {}, { xfader = 0 }).volume, 1))
check("deck2 at A is silent", near(paramsOf(2, {}, {}, { xfader = 0 }).volume, 0, 1e-9))
check("deck1 at B is silent", near(paramsOf(1, {}, {}, { xfader = 1 }).volume, 0, 1e-9))
check("deck2 at B is full", near(paramsOf(2, {}, {}, { xfader = 1 }).volume, 1))
check("centre: deck1 at 0.707", near(paramsOf(1, {}, {}, { xfader = 0.5 }).volume, 0.7071068, 1e-6))
check("centre: deck2 at 0.707", near(paramsOf(2, {}, {}, { xfader = 0.5 }).volume, 0.7071068, 1e-6))
check("centre magnet snaps 0.52", near(paramsOf(1, {}, {}, { xfader = 0.52 }).volume, 0.7071068, 1e-6))
check("cut curve keeps centre full", near(paramsOf(1, {}, {}, { xfader = 0.5, curve = 1 }).volume, 1))
check("cut curve deck2 at A silent", near(paramsOf(2, {}, {}, { xfader = 0, curve = 1 }).volume, 0))
check("track gain +6 dB", near(paramsOf(1, { vol = 0.5 }, { gain = 6 }).volume, 0.9976312, 1e-6))
check("volume clamps at 10", paramsOf(1, {}, { gain = 40 }).volume == 10)
check("speed is rate", near(paramsOf(1, { pitch = 0.1 }, { speed = 1.2 }).speed, 1.32))
check("speed clamps at 0.2", paramsOf(1, { pitch = -0.8 }, { speed = 0.5 }).speed == 0.2)
check("speed clamps at 5", paramsOf(1, { pitch = 3 }, { speed = 1.5 }).speed == 5)
local kl = paramsOf(1, { pitch = 0.1 }, {}, {}, { keyLock = true })
check("key lock on shifts", kl.shiftEnabled and near(kl.octave, 0.9090909, 1e-6))
local klFlat = paramsOf(1, {}, {}, {}, { keyLock = true })
check("key lock on, flat pitch off", not klFlat.shiftEnabled and klFlat.octave == 1)
local klOff = paramsOf(1, { pitch = 0.1 }, {}, {}, { keyLock = false })
check("key lock off ignores pitch", not klOff.shiftEnabled and klOff.octave == 1)
check("key lock octave clamps at 2", paramsOf(1, { pitch = -0.5 }, {}, {}, { keyLock = true }).octave == 2)
check("key lock tiny pitch off", not paramsOf(1, { pitch = 0.0003 }, {}, {}, { keyLock = true }).shiftEnabled)
local eqBoost = paramsOf(1, { eq = { 1, 0.5, 0 } })
check("eq high +12, low kill", near(eqBoost.high, 12) and eqBoost.mid == 0 and eqBoost.low == -80)
local lpf = paramsOf(1, { filter = 0 })
check("lpf cuts high 60 and mid 30", near(lpf.high, -60) and near(lpf.mid, -30) and lpf.low == 0)
local fxOff = paramsOf(1, { fx = { 0, 0, 0 } })
check(
	"fx off",
	not fxOff.echoEnabled
		and fxOff.echoWet == -30
		and not fxOff.reverbEnabled
		and fxOff.reverbWet == -40
		and not fxOff.flangeEnabled
		and fxOff.flangeMix == 0
)
local fxFull = paramsOf(1, { fx = { 1, 1, 1 } })
check(
	"fx full",
	fxFull.echoEnabled
		and fxFull.echoWet == 0
		and fxFull.reverbEnabled
		and fxFull.reverbWet == 0
		and fxFull.flangeEnabled
		and fxFull.flangeMix == 1
)
local fxHalf = paramsOf(1, { fx = { 0.5, 0.5, 0.5 } })
check("fx half", fxHalf.echoWet == -15 and fxHalf.reverbWet == -20 and fxHalf.flangeMix == 0.5)
check("echo delay without bpm", paramsOf(1, {}, {}).echoDelay == 0.375)
check("echo delay 128 bpm", paramsOf(1, {}, { bpm = 128 }).echoDelay == 0.3515625)
check("echo delay uses speed", near(paramsOf(1, {}, { bpm = 128, speed = 1.2 }).echoDelay, 0.29296875, 1e-9))
check("echo delay clamps at 1", paramsOf(1, {}, { bpm = 10 }).echoDelay == 1)
check("echo delay 300 bpm", near(paramsOf(1, {}, { bpm = 300 }).echoDelay, 0.15, 1e-9))
check("deck2 uses its own crossfade side", paramsOf(2, { vol = 1 }, {}, { xfader = 0 }).volume == 0)

local m = DeckParams.master(sessionOf({ master = 0.5 }), settingsOf({ volume = 80 }))
check(
	"master limiter off",
	near(m.volume, 0.4)
		and not m.limiterEnabled
		and m.threshold == -1
		and m.ratio == 20
		and m.gainMakeup == 0
		and near(m.attack, 0.003)
		and near(m.release, 0.1)
)
local mn = DeckParams.master(sessionOf({}), settingsOf({ normalize = true }))
check(
	"master normalize",
	mn.limiterEnabled
		and mn.threshold == -18
		and mn.ratio == 4
		and mn.gainMakeup == 6
		and near(mn.attack, 0.01)
		and near(mn.release, 0.2)
)
local ml = DeckParams.master(sessionOf({}), settingsOf({ limiter = true }))
check("master limiter on", ml.limiterEnabled and ml.threshold == -1 and ml.ratio == 20)
check(
	"master volume clamps at 10",
	DeckParams.master(sessionOf({ master = 1 }), settingsOf({ volume = 1500 })).volume == 10
)
local fx = DeckParams.FX_DEFAULTS
check(
	"fx defaults",
	fx.echo.DryLevel == 0
		and fx.echo.Feedback == 0.35
		and fx.reverb.DryLevel == 0
		and fx.reverb.DecayTime == 1.6
		and fx.flange.Depth == 0.45
		and fx.flange.Rate == 0.6
)
check(
	"fx priorities",
	fx.priority.eq == 5
		and fx.priority.echo == 4
		and fx.priority.reverb == 3
		and fx.priority.flange == 2
		and fx.priority.shift == 1
)

print(string.format("%d passed, %d failed", passed, failures))
if failures > 0 then
	process.exit(1)
end
