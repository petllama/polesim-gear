local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Equip.lua", "Sources.lua", "Browser.lua", "Plan.lua", "Wishlist.lua", "View.lua" }
local function load(char)
	local ns = T.addon(FILES)
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = {}, char or {}
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	return ns
end
local function r(id, gain, kinds, at)
	return { c = { id = id, inst = { id = id, name = "I" .. id }, kinds = kinds or { quest = true } }, gain = gain, at = at }
end
local function model()
	return { level = 20,
		now = { head = { r(1, 5), r(2, 3) }, neck = { r(3, 9, { vendor = true }) }, chest = { r(4, 2, { world = true }) } },
		coming = { feet = { r(5, 7, { quest = true }, 22) } } }
end
local worn = { [1] = { inst = { id = 90 }, score = 10 }, [5] = { inst = { id = 91 }, score = 4 } }
local ALL = { quest = true, dungeon = true, crafted = true, vendor = true, world = false }
return {
	upgrades_mode = function()
		local ns = load()
		local st = { spec = "shadow", filters = ALL, ahead = 0, show = "upgrades" }
		local es = ns.View.PlanEntries(model(), worn, st)
		local keys = {}
		for _, e in ipairs(es) do keys[#keys + 1] = e.def.key .. "#" .. e.priority end
		T.eq(table.concat(keys, ","), "neck#1,head#2", "biggest planned gain first; world off; feet beyond look ahead")
		T.eq(es[2].worn.inst.id, 90, "the current item")
		st.ahead = 2
		es = ns.View.PlanEntries(model(), worn, st)
		T.eq(es[2].def.key, "feet", "look ahead +2: the level 22 boots")
	end,
	pick_sorts_by_pick_gain = function()
		local ns = load({ plan = { shadow = { head = "2:0", neck = "77:0" } } })
		local es = ns.View.PlanEntries(model(), worn, { spec = "shadow", filters = ALL, ahead = 0, show = "upgrades" })
		T.eq(es[1].def.key, "head", "the pick's gain (3) ranks it; the missing pick goes last")
		T.eq(es[1].entry.plan.c.id, 2); T.near(es[1].entry.betterBy, 2, 1e-9)
		T.eq(es[2].def.key, "neck"); T.eq(es[2].entry.missing.id, 77); T.eq(es[2].priority, nil, "no number for a missing pick")
		T.ok(es[2].why:find("not available", 1, true), es[2].why)
	end,
	all_mode = function()
		local ns = load()
		local es = ns.View.PlanEntries(model(), worn, { spec = "shadow", filters = ALL, ahead = 0, show = "all" })
		T.eq(#es, #ns.Browser.SLOTS, "every slot")
		T.eq(es[1].def.key, "neck"); T.eq(es[2].def.key, "head")
		T.eq(es[3].entry.plan, nil, "then the rest in slot order, no upgrade"); T.eq(es[3].priority, nil)
		T.eq(es[3].def.key, "shoulder")
	end,
	wishlist_mode = function()
		local ns = load({ wish = { ["4:0"] = true, ["99:0"] = true } })
		local es = ns.View.PlanEntries(model(), worn, { spec = "shadow", filters = ALL, ahead = 0, show = "wishlist" })
		T.eq(#es, 2)
		T.eq(es[1].row.c.id, 4, "found (filters do not hide starred items)"); T.eq(es[1].def.key, "chest")
		T.eq(es[2].row, nil); T.eq(es[2].missing.id, 99); T.eq(es[2].why, "not an upgrade now")
	end,
	progress = function()
		local ns = load({ plan = { shadow = { neck = "3:0" } } })
		local m = model()
		local st = { spec = "shadow", filters = ALL, ahead = 0, show = "upgrades" }
		local done, total = ns.View.Progress(m, worn, st)
		T.eq(total, #ns.Browser.SLOTS); T.eq(done, total - 2, "head and neck have upgrades now")
		st.filters = { quest = true }
		done = ns.View.Progress(m, worn, st)
		T.eq(done, total - 1, "vendor off: the neck counts as done")
		st.ahead = 5
		T.eq((ns.View.Progress(m, worn, st)), total - 1, "progress counts upgrades available NOW")
	end,
	weights = function()
		local ns = load()
		local rows = ns.View.WeightRows({ int = 0.4, spShadow = 1, sta = 0.1, armor = 0 }, nil)
		local t = {}
		for _, w in ipairs(rows) do t[#t + 1] = w.key .. "=" .. w.value end
		T.eq(table.concat(t, ","), "spShadow=1,int=0.4,sta=0.1", "zero weights left out, biggest first")
		T.eq(rows[1].label, ns.DATA.statLabels.spShadow or "spShadow")
		T.eq(#ns.View.WeightRows({ a = 3, b = 2, c = 1 }, 2), 2, "top N")
		local bands = ns.View.Bands("priest", "shadow")
		T.ok(#bands >= 2); T.eq(bands[1].lo, 1); T.eq(bands[2].lo, bands[1].upTo + 1)
		T.eq(ns.View.BandIndex(bands, bands[2].lo), 2)
	end,
	badge_slots = function()
		local ns = load({ plan = { shadow = { neck = "3:0" } } })
		local B = ns.Browser
		local def = {}
		for _, d in ipairs(B.SLOTS) do def[d.key] = d end
		local function e(key, isPick) return { def = def[key], entry = { plan = {}, isPick = isPick } } end
		local worn = { [11] = { score = 5 }, [12] = { score = 3 }, [13] = { score = 2 } }
		local neck = e("neck", true)
		local b, of = ns.View.BadgeSlots({ neck, e("finger"), e("trinket"), { def = def.head, entry = {} } }, worn)
		T.eq(of[2], neck, "the entry behind the dot (the slot tooltip names its item)"); T.eq(of[1], nil)
		T.eq(b[2], "pick"); T.eq(b[12], "suggestion", "the weaker ring"); T.eq(b[14], "suggestion", "the empty trinket slot")
		T.eq(b[1], nil, "no plan")
	end,
}
