local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Equip.lua", "Sources.lua", "Browser.lua", "Plan.lua" }
local function load(char)
	local ns = T.addon(FILES)
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = {}, char or {}
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	return ns
end
return {
	storage = function()
		local char = {}
		local ns = load(char)
		local P = ns.Plan
		T.eq(P.Get("shadow", "head"), nil)
		P.Set("shadow", "head", { id = 10, bonus = 3 })
		T.eq(char.plan.shadow.head, "10:3"); T.eq(P.Get("shadow", "head"), "10:3")
		T.eq(P.Get("holy", "head"), nil, "per spec")
		local id, bonus = P.Parse("10:3"); T.eq(id, 10); T.eq(bonus, 3)
		id, bonus = P.Parse("10:0"); T.eq(id, 10); T.eq(bonus, nil)
		T.eq(P.Parse("junk"), nil)
		P.Clear("shadow", "head")
		T.eq(P.Get("shadow", "head"), nil)
		local fired = 0
		ns.On("PLAN_CHANGED", function() fired = fired + 1 end)
		P.Set("shadow", "neck", { id = 2 }); P.Clear("shadow", "neck")
		T.eq(fired, 2)
		P.Clear("shadow", "neck"); P.Clear("holy", "head")
		T.eq(fired, 2, "nothing to clear: no PLAN_CHANGED")
	end,
	bad_saved_value = function()
		local ns = load({ plan = { shadow = "x" } })
		T.eq(ns.Plan.Get("shadow", "head"), nil)
		ns.Plan.Set("shadow", "head", { id = 1 })
		T.eq(ns.Plan.Get("shadow", "head"), "1:0")
	end,
	resolve = function()
		local ns = load({})
		local P = ns.Plan
		local function r(id, gain, kinds, at, bonus)
			return { c = { id = id, inst = { id = id, bonus = bonus, name = "I" .. id }, kinds = kinds or { quest = true } }, gain = gain, at = at }
		end
		local rows = { r(1, 5), r(2, 3), r(3, 1, nil, nil, 7) }
		-- no pick: the suggestion
		local e = P.Resolve(rows, nil)
		T.eq(e.plan.c.id, 1); T.eq(e.isPick, false); T.eq(e.suggestion.c.id, 1); T.eq(e.betterBy, nil)
		-- a pick in the rows
		e = P.Resolve(rows, "3:7")
		T.eq(e.plan.c.id, 3); T.eq(e.isPick, true); T.near(e.betterBy, 4, 1e-9, "best: I1 +4 over the pick")
		e = P.Resolve(rows, "1:0")
		T.eq(e.isPick, true); T.eq(e.betterBy, nil, "the pick is the best")
		-- a pick not in the rows: missing (why from the model, Task 2.5)
		e = P.Resolve(rows, "9:0")
		T.eq(e.plan, nil); T.eq(e.missing.id, 9); T.eq(e.isPick, true); T.eq(e.suggestion.c.id, 1)
		-- nothing at all
		e = P.Resolve({}, nil)
		T.eq(e.plan, nil); T.eq(e.missing, nil); T.eq(e.suggestion, nil)
	end,
	-- The suggestion prefers an upgrade from an upcoming guide quest within 2 levels (Resolve's level)
	-- over the overall best: quest on the Polestar route (s.route), quest level and wear level <= level + 2.
	near_quest = function()
		local ns = load({})
		local P = ns.Plan
		-- q = { level, route (ahead) | false }; at = the coming row's level
		local function r(id, gain, q, at, kind)
			local srcs = {}
			if q then
				srcs[1] = { kind = "quest", ok = true, questId = 500 + id, level = q.level,
					route = q.route ~= false and { ahead = q.route, guide = "G" } or nil }
			else
				srcs[1] = { kind = kind or "dungeon", ok = true }
			end
			local kinds = {}
			for _, s in ipairs(srcs) do kinds[s.kind] = true end
			return { c = { id = id, inst = { id = id, name = "I" .. id }, kinds = kinds, sources = srcs, rl = q and q.rl or 18 }, gain = gain, at = at }
		end
		local bis = r(1, 9) -- a dungeon drop
		local craft = r(2, 8, nil, nil, "crafted")
		local quest = r(3, 4, { level = 21, route = 12 })
		local rows = { bis, craft, quest }
		-- near quest beats a higher dungeon/craft BiS
		local e = P.Resolve(rows, nil, 20)
		T.eq(e.suggestion.c.id, 3); T.eq(e.plan.c.id, 3); T.eq(e.best.c.id, 1); T.eq(e.near, true)
		-- no level: no preference (setting off)
		e = P.Resolve(rows, nil, nil)
		T.eq(e.suggestion.c.id, 1); T.eq(e.plan.c.id, 1); T.eq(e.near, nil)
		-- quest at level + 3: not near
		e = P.Resolve({ bis, r(4, 4, { level = 23, route = 1 }) }, nil, 20)
		T.eq(e.suggestion.c.id, 1, "quest level 23 > 22")
		-- missing quest level: the item's required level counts
		e = P.Resolve({ bis, r(5, 4, { rl = 23, route = 1 }) }, nil, 20)
		T.eq(e.suggestion.c.id, 1, "no quest level, item rl 23")
		e = P.Resolve({ bis, r(5, 4, { rl = 22, route = 1 }) }, nil, 20)
		T.eq(e.suggestion.c.id, 5, "no quest level, item rl 22")
		-- a quest not on the guide route never replaces BiS
		e = P.Resolve({ bis, r(6, 4, { level = 20, route = false }) }, nil, 20)
		T.eq(e.suggestion.c.id, 1, "not on the route")
		-- unavailable (not ok: done / other class): no
		local done = r(7, 4, { level = 20, route = 3 })
		done.c.sources[1].ok = false
		e = P.Resolve({ bis, done }, nil, 20)
		T.eq(e.suggestion.c.id, 1, "quest not available")
		-- look-ahead rows beyond +2 excluded, within +2 allowed
		e = P.Resolve({ bis, r(8, 4, { level = 20, route = 3 }, 23) }, nil, 20)
		T.eq(e.suggestion.c.id, 1, "worn from 23")
		e = P.Resolve({ bis, r(8, 4, { level = 20, route = 3 }, 22) }, nil, 20)
		T.eq(e.suggestion.c.id, 8, "worn from 22")
		-- "needs X first" still qualifies
		local needs = r(9, 4, { level = 20, route = 3 })
		needs.c.sources[1].needs = "Quest 1"
		T.eq(P.Resolve({ bis, needs }, nil, 20).suggestion.c.id, 9)
		-- tie-break: equal gains (within 0.05) -> fewest steps ahead
		local far, close = r(10, 5, { level = 20, route = 30 }), r(11, 4.97, { level = 20, route = 2 })
		e = P.Resolve({ bis, far, close }, nil, 20)
		T.eq(e.suggestion.c.id, 11, "fewer steps ahead")
		e = P.Resolve({ bis, r(12, 5.2, { level = 20, route = 30 }), close }, nil, 20)
		T.eq(e.suggestion.c.id, 12, "a real gain difference wins")
		-- the BiS itself a near quest: suggestion = best, no BiS note
		e = P.Resolve({ quest, r(13, 2, nil, nil, "crafted") }, nil, 20)
		T.eq(e.suggestion.c.id, 3); T.eq(e.best.c.id, 3)
		-- the player's pick wins over both; betterBy vs the overall best
		e = P.Resolve(rows, "2:0", 20)
		T.eq(e.plan.c.id, 2); T.eq(e.isPick, true); T.near(e.betterBy, 1, 1e-9)
	end,
	why = function()
		local ns = load({})
		local P = ns.Plan
		local function r(id, kinds, at) return { c = { id = id, inst = { id = id }, kinds = kinds }, gain = 1, at = at } end
		local m = { level = 20, now = { head = { r(1, { vendor = true, world = true }) } }, coming = { head = { r(2, { quest = true }, 24) } } }
		T.eq(P.Why(m, "head", "1:0", 0, { quest = true }), "its sources are off: Vendors, BoE / World")
		T.eq(P.Why(m, "head", "2:0", 2, { quest = true }), "needs level 24 (look ahead +4)")
		T.eq(P.Why(m, "head", "3:0", 5, { quest = true }), "not available now (quest done, retired, or no longer an upgrade)")
	end,
	clear_worn = function()
		local char = { plan = { shadow = { head = "10:3", finger = "20:0", neck = "30:0" }, holy = { head = "10:3" } } }
		local ns = load(char)
		local worn = { [1] = { inst = { id = 10, bonus = 3 } }, [12] = { inst = { id = 20 } }, [2] = { inst = { id = 30, bonus = 1 } } }
		local n = ns.Plan.ClearWorn(worn)
		T.eq(n, 3)
		T.eq(char.plan.shadow.head, nil); T.eq(char.plan.holy.head, nil, "every spec")
		T.eq(char.plan.shadow.finger, nil, "the second ring slot counts")
		T.eq(char.plan.shadow.neck, "30:0", "another suffix: not the picked one")
		-- wired: SCORES_CHANGED reads Context's worn items
		char.plan.shadow.head = "10:3"
		ns.Context = { Get = function() return { worn = worn } end }
		ns.Fire("SCORES_CHANGED")
		T.eq(char.plan.shadow.head, nil)
	end,
}
