--!strict
-- PATH: ReplicatedStorage/Shared/Utils/InstanceState.luau
-- Per-instance state that must survive for as long as the Instance lives: one STRONG record per
-- Instance, reclaimed by that Instance's own `Destroying`. This is the kit's one mechanism for it
-- (ADR 0011 addendum, 2026-09-17); UIMotion grew the shape first and every other site uses this.
--
-- Why not a weak-keyed table. Roblox drops a `__mode = "k"` entry keyed by an Instance the moment no
-- *Lua* value references that Instance — the Instance itself stays alive, parented, in the tree.
-- Measured live 2026-09-17: a UIScale parented under a holder, `weak[s] = true`, ~40 frames of
-- allocation churn, 1 s wait — entriesBefore = 1, entriesAfterChurn = 0, instanceStillInTree = true.
-- Kit code rarely holds a Lua reference to the labels, gradients, strokes and UIScales it keeps
-- state for (it finds them again through the tree), so every such entry sat on a GC timer: lost
-- tween handles that could no longer be cancelled, lost rest/design captures re-captured mid-gesture
-- as "designed", lost bind-once guards that let a second bind through. A weak key follows the Lua
-- proxy's lifetime, not the Instance's.
--
-- The rule. Weak tables are not a lifetime mechanism. A weak-keyed table is only ever a pure cache:
-- a lost entry must cost nothing worse than a recompute (a cover key re-applied, a highlight tween
-- restarted toward the same value). Anything that has to be there while the Instance is alive — a
-- captured design value, a generation counter, a running tween, a bound flag — goes through here.
--
-- Lifetime. `of` makes the record on first use and connects `instance.Destroying:Once` — exactly one
-- connection per Instance, kept beside the record so it is never doubled — and that clears the
-- record. Only `Destroying` reclaims; `AncestryChanged` to a nil parent is not destruction. Pooled
-- rows (music playlist cards, the Admin v3 player list, the couple picker) are detached and re-shown
-- as the same Instance, and their state must survive that. A hidden-but-alive pooled row therefore
-- keeps its record for as long as it lives — intended, it is bytes per row.
--
-- `get` never creates. Release and teardown paths (anything that may run from inside a `Destroying`
-- handler) read with `get`, because a record made for an Instance that has already fired
-- `Destroying` would never be reclaimed. `drop` is the explicit reclaim, idempotent.

local InstanceState = {}

export type Store<T> = {
	-- The record if one exists. Never creates.
	get: (instance: Instance) -> T?,
	-- The record, made by `init` on first use and reclaimed when the instance fires `Destroying`.
	of: (instance: Instance) -> T,
	-- Explicit reclaim: forgets the record and disconnects its `Destroying` listener. No-op without one.
	drop: (instance: Instance) -> (),
}

type Entry<T> = {
	value: T,
	destroying: RBXScriptConnection,
}

function InstanceState.new<T>(init: (instance: Instance) -> T): Store<T>
	local entries: { [Instance]: Entry<T> } = {}

	local function get(instance: Instance): T?
		local entry = entries[instance]
		return if entry then entry.value else nil
	end

	local function drop(instance: Instance)
		local entry = entries[instance]
		if entry == nil then
			return
		end
		entries[instance] = nil
		entry.destroying:Disconnect()
	end

	local function of(instance: Instance): T
		local entry = entries[instance]
		if entry then
			return entry.value
		end
		local made: Entry<T> = {
			value = init(instance),
			destroying = instance.Destroying:Once(function()
				entries[instance] = nil
			end),
		}
		entries[instance] = made
		return made.value
	end

	return {
		get = get,
		of = of,
		drop = drop,
	}
end

return InstanceState
