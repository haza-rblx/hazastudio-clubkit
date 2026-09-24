--!strict
-- Client/Utils/OverheadCullBudget.luau
--
-- Which other players' overheads stay enabled (production hardening P4, plan H13).
-- Each overhead wrapper is a CanvasGroup = one GPU texture; with 200 players on "Far" the
-- client ran out of texture budget and overheads drew blank (ADR 0005). Pure: the caller
-- (Client OverheadController) measures distances and applies the result.
--
-- Rules: pinned entries (the local player's own overhead) always stay and use no slot;
-- nothing beyond `maxDistance` stays (0 = unlimited); at most `cap` others stay (0 = no cap),
-- nearest first; an enabled entry counts `margin` studs nearer than it is, so a culled one
-- takes its slot only when clearly nearer (no flapping when two players swap places).

export type Entry = {
	key: any,
	distance: number,
	enabled: boolean,
	pinned: boolean?,
}

local OverheadCullBudget = {}

function OverheadCullBudget.select(entries: { Entry }, cap: number, margin: number, maxDistance: number): { [any]: boolean }
	local keep: { [any]: boolean } = {}
	local ranked: { Entry } = {}
	local scores: { [Entry]: number } = {}
	for _, entry in ipairs(entries) do
		if entry.pinned then
			keep[entry.key] = true
		elseif maxDistance <= 0 or entry.distance <= maxDistance then
			table.insert(ranked, entry)
			scores[entry] = if entry.enabled then entry.distance - margin else entry.distance
		end
	end
	if cap <= 0 or #ranked <= cap then
		for _, entry in ipairs(ranked) do
			keep[entry.key] = true
		end
		return keep
	end
	table.sort(ranked, function(a: Entry, b: Entry): boolean
		return scores[a] < scores[b]
	end)
	for i = 1, cap do
		keep[ranked[i].key] = true
	end
	return keep
end

return OverheadCullBudget
