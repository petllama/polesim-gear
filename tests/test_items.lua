local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua" }
return {
	get = function()
		local ns = T.addon(FILES)
		local it = ns.Items.Get(6540)
		T.eq(it.name, "Willow Pants")
		T.eq(it.inv, 7)
		T.eq(it.c, 4)
		T.eq(it.sc, 1)
		T.ok(it.ar > 0)
		T.ok(#it.sfx > 5)
		T.eq(type(it.sfx[1]), "number")
		T.ok(it.b > 0)
		T.eq(ns.Items.Get(6540), it, "cached")
		T.eq(ns.Items.Get(1), nil)
		T.eq(ns.Items.Get(14152), nil, "mage robe not shipped")
	end,
	wand = function()
		local ns = T.addon(FILES)
		local w = ns.Items.Get(11288)
		T.eq(w.s.sp, 2)
		T.ok(w.dps > 0)
	end,
	by_inv = function()
		local ns = T.addon(FILES)
		local by = ns.Items.ByInv()
		local found = false
		for _, id in ipairs(by[7]) do if id == 6540 then found = true end end
		T.ok(found)
		T.ok(#by[26] > 0, "wands")
	end,
	-- The browser's index decodes nothing (the whole table decoded and kept was ~8 MB): it keeps ids per
	-- inventory type and each item's required level; Peek decodes one item without keeping it.
	by_inv_keeps_no_records = function()
		local ns = T.addon(FILES)
		local by = ns.Items.ByInv()
		T.eq(ns.Items._cached(), 0, "nothing decoded and kept")
		T.eq(ns.Items.Rl(6540), ns.Items.Peek(6540).rl)
		T.eq(ns.Items.Rl(1), nil)
		T.ok(ns.Items.Peek(6540) ~= ns.Items.Peek(6540), "Peek keeps nothing")
		T.eq(ns.Items._cached(), 0)
		local it = ns.Items.Get(6540)
		T.eq(ns.Items.Peek(6540), it, "an item kept by Get is shared")
		T.eq(ns.Items.Peek(1), nil)
		T.eq(ns.Items.ByInv(), by, "built once")
		ns.Items.ReleaseIndex()
		T.ok(ns.Items.ByInv() ~= by, "built again after a release")
		T.eq(ns.Items.Rl(6540), it.rl)
	end,
}
