--!strict
-- The accent this player sees right now (CONTEXT.md "Accent theme"). SettingsController sets it
-- from the settings payload; UI that paints state (toggles, selected pills, played dance row,
-- top-menu hover) reads it and repaints through `subscribe`.
--
-- Multicolor (default) and Graphite mean "the design's own state colours": consumers keep whatever
-- their GUI/code paints today (`isDesign()`), so a player who never picks an accent sees no change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccentDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.AccentDomain)
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local AccentService = {}

export type Accent = {
	id: string,
	fill: Color3,
	onFill: Color3,
}

type Listener = (Accent) -> ()

local function build(id: string): Accent
	local swatch = AccentDomain.swatch(id)
	return table.freeze({
		id = id,
		fill = Color3.fromHex(swatch.fill),
		onFill = Color3.fromHex(swatch.onFill),
	})
end

local current: Accent = build(AccentDomain.resolve(nil, (Config :: any).Branding and Config.Branding.DEFAULT_ACCENT))
local listeners: { Listener } = {}

function AccentService.get(): Accent
	return current
end

-- True for Multicolor and Graphite: paint the design's own colours, not `fill` / `onFill`.
function AccentService.isDesign(): boolean
	return AccentDomain.keepsDesign(current.id)
end

-- True for Multicolor: every GUI keeps its own colours (Graphite is the grey one).
function AccentService.isMulticolor(): boolean
	return current.id == AccentDomain.DEFAULT
end

-- Settings echo the whole payload on every sync, so an unchanged accent returns early.
function AccentService.set(id: any)
	local resolved = AccentDomain.normalize(id) or AccentDomain.DEFAULT
	if resolved == current.id then
		return
	end
	current = build(resolved)
	for _, listener in ipairs(table.clone(listeners)) do
		task.spawn(listener, current)
	end
end

function AccentService.subscribe(listener: Listener): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

return AccentService
