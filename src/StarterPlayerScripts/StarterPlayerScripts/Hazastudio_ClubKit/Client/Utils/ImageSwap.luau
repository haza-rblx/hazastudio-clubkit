--!strict
-- Assigns an image to an ImageLabel/ImageButton WITHOUT ever showing a blank frame.
--
-- The pattern this replaces, which appears across the kit, guarantees a gap:
--     holder.Image = ""              -- blank, right now
--     task.spawn(function() ... holder.Image = fetched end)   -- filled later
-- Between those two lines the player sees nothing, and a cold image keeps them
-- there for ~0.5s (measured).
--
-- Instead: keep whatever is currently displayed (or a placeholder) until the new
-- content is confirmed decoded on a detached probe, then swap. An unparented
-- ImageLabel still loads -- verified -- so probing costs no render work.
--
-- Rapid reassignment is safe: every call takes a generation token, and a late
-- probe whose token has been superseded is discarded. That matters for recycled
-- list rows (leaderboards, sticker grid, admin player list), where the same
-- holder is retargeted while an earlier fetch is still in flight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local ImagePreloadService = require(script.Parent.Parent.Services.ImagePreloadService)

export type Holder = ImageLabel | ImageButton

export type Options = {
	-- Shown while the target loads, when the holder has nothing useful to show.
	placeholder: string?,
	-- Transparency the image settles at (holders that live inside a faded panel
	-- may want something other than 0).
	baseTransparency: number?,
	-- Seconds to fade in. 0 swaps instantly.
	fadeTime: number?,
	-- Give up waiting after this long and leave the placeholder in place.
	timeout: number?,
	-- Force the placeholder even when the holder already shows another image.
	forcePlaceholder: boolean?,
}

local ImageSwap = {}

-- Weak keys: a destroyed holder must not be kept alive by its token.
local tokens: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function cfg(): any
	return Config.ImagePreload or {}
end

local function numOr(value: any, fallback: number): number
	local n = tonumber(value)
	if n == nil or n ~= n or n < 0 then
		return fallback
	end
	return n
end

local function isLoaded(holder: Holder): boolean
	local ok, loaded = pcall(function()
		return (holder :: any).IsLoaded
	end)
	return ok and loaded == true
end

local function applyNow(holder: Holder, contentId: string, base: number, fadeTime: number)
	if fadeTime <= 0 then
		holder.Image = contentId
		holder.ImageTransparency = base
		return
	end
	holder.Image = contentId
	-- Fade from wherever it currently sits so a placeholder->real swap reads as a
	-- cross-fade rather than a flash to empty.
	local from = math.max(holder.ImageTransparency, base)
	holder.ImageTransparency = from
	local tween = TweenService:Create(
		holder,
		TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ ImageTransparency = base }
	)
	tween:Play()
end

-- Main entry point. Never yields the caller.
function ImageSwap.set(holder: Holder?, contentId: any, options: Options?)
	if holder == nil or not holder.Parent then
		return
	end
	local opts = options or {}
	local base = numOr(opts.baseTransparency, 0)
	local fadeTime = numOr(opts.fadeTime, numOr(cfg().FADE_TIME, 0.12))
	local timeout = numOr(opts.timeout, numOr(cfg().SWAP_TIMEOUT_SEC, 10))
	local placeholder = opts.placeholder or cfg().PLACEHOLDER_IMAGE

	local token = (tokens[holder] or 0) + 1
	tokens[holder] = token

	-- Clearing is explicit and immediate; there is nothing to wait for.
	if not ImagePreloadService.isPreloadableId(contentId) then
		holder.Image = if type(placeholder) == "string" then placeholder else ""
		holder.ImageTransparency = base
		return
	end

	local target = contentId :: string

	-- Already the right image and ready: just make sure it is visible.
	if holder.Image == target and isLoaded(holder) then
		holder.ImageTransparency = base
		return
	end

	-- Known warm (preloaded at boot, or shown earlier): safe to swap instantly.
	if ImagePreloadService.isWarm(target) then
		applyNow(holder, target, base, 0)
		return
	end

	-- Nothing meaningful on screen yet -> show the placeholder rather than a hole.
	if type(placeholder) == "string" and placeholder ~= "" then
		if opts.forcePlaceholder or holder.Image == "" or holder.Image == "rbxassetid://0" then
			holder.Image = placeholder
			holder.ImageTransparency = base
		end
	end

	task.spawn(function()
		local probe = Instance.new("ImageLabel")
		probe.BackgroundTransparency = 1
		probe.Image = target

		local deadline = os.clock() + timeout
		while not probe.IsLoaded and os.clock() < deadline do
			task.wait(0.05)
		end
		local loaded = probe.IsLoaded
		probe:Destroy()

		-- Superseded, or the holder went away while we waited.
		if tokens[holder] ~= token or not holder.Parent then
			return
		end
		if not loaded then
			-- Leave the placeholder/previous image alone. A half-drawn asset is
			-- worse than a stable stand-in.
			return
		end

		ImagePreloadService.markWarm(target)
		applyNow(holder, target, base, fadeTime)
	end)
end

-- Convenience for list rows that are being recycled: drops any in-flight swap so
-- a stale fetch cannot land on the row after it has been retargeted.
function ImageSwap.cancel(holder: Holder?)
	if holder == nil then
		return
	end
	tokens[holder] = (tokens[holder] or 0) + 1
end

return ImageSwap
