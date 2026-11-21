local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua" }
local function fake(kw)
	local it = { c = 4, sc = 1, inv = 5, cm = 0 }
	for k, v in pairs(kw or {}) do it[k] = v end
	return it
end
return {
	can_use = function()
		local E = T.addon(FILES).Equip
		T.ok(E.CanUse(fake(), "priest", 1))
		T.ok(not E.CanUse(fake({ sc = 2 }), "priest", 60), "leather")
		T.ok(E.CanUse(fake({ sc = 2, inv = 16 }), "priest", 1), "every cloak")
		T.ok(E.CanUse(fake({ sc = 0, inv = 11 }), "priest", 1), "rings")
		T.ok(E.CanUse(fake({ c = 2, sc = 19, inv = 26 }), "priest", 1), "wand")
		T.ok(not E.CanUse(fake({ c = 2, sc = 7, inv = 13 }), "priest", 60), "sword")
		T.ok(not E.CanUse(fake({ cm = 128 }), "priest", 60), "mage only")
		T.ok(E.CanUse(fake({ cm = 16 }), "priest", 60), "priest only")
		T.ok(not E.CanUse(fake({ c = 15 }), "priest", 60), "not gear")
	end,
	compare = function()
		local E = T.addon(FILES).Equip
		local w = { int = 1, dps = 1, rdps = 1 }
		local function item(id, inv, int, extra)
			local i = { id = id, inv = inv, stats = { int = int }, armor = 0, dps = 0, weapon = false }
			for k, v in pairs(extra or {}) do i[k] = v end
			return i
		end
		local worn = {
			[1] = { inst = item(1, 1, 5), score = 5 },
			[11] = { inst = item(2, 11, 8), score = 8 }, [12] = { inst = item(3, 11, 4), score = 4 },
			[16] = { inst = item(4, 21, 6), score = 6 }, [17] = { inst = item(5, 23, 3), score = 3 },
		}
		local c = E.Compare(item(10, 1, 9), w, "priest", worn, false)
		T.near(c.gain, 4); T.eq(c.slot, 1)
		c = E.Compare(item(11, 11, 6), w, "priest", worn, false)
		T.near(c.gain, 2); T.eq(c.slot, 12)
		T.ok(E.Compare(item(2, 11, 8), w, "priest", worn, false).equipped)
		c = E.Compare(item(12, 17, 10), w, "priest", worn, false)
		T.near(c.gain, 1); T.eq(c.note, "replaces main and off hand")
		local staff = { [16] = { inst = item(6, 17, 9), score = 9 } }
		c = E.Compare(item(13, 21, 7), w, "priest", staff, false)
		T.near(c.gain, -2); T.eq(c.note, "leaves the off hand empty")
		c = E.Compare(item(14, 23, 4), w, "priest", staff, false)
		T.eq(c.note, "needs a one-hander")
		c = E.Compare(item(15, 26, 0, { dps = 10, weapon = true }), w, "priest", worn, false)
		T.near(c.score, 10); T.eq(c.slot, 18); T.near(c.gain, 10)
		c = E.Compare(item(16, 7, 3), w, "priest", worn, false)
		T.near(c.gain, 3); T.eq(c.base, 0)
	end,
}
