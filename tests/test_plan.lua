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
	why = function()
		local ns = load({})
		local P = ns.Plan
		local function r(id, kinds, at) return { c = { id = id, inst = { id = id }, kinds = kinds }, gain = 1, at = at } end
		local m = { level = 20, now = { head = { r(1, { vendor = true, world = true }) } }, coming = { head = { r(2, { quest = true }, 24) } } }
		T.eq(P.Why(m, "head", "1:0", 0, { quest = true }), "its sources are off: Vendor, BoE / World")
		T.eq(P.Why(m, "head", "2:0", 2, { quest = true }), "needs level 24 (look ahead +4)")
		T.eq(P.Why(m, "head", "3:0", 5, { quest = true }), "not available now (quest done, retired, or no longer an upgrade)")
	end,
}
