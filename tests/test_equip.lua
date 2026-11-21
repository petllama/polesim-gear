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
	-- Mage (armory.PROFICIENCY): cloth, staves, one-hand swords, daggers, wands; no maces or shields;
	-- class-restricted items follow the class mask. Real shipped items.
	can_use_mage = function()
		local ns = T.addon(FILES)
		local E, I = ns.Equip, ns.Items
		T.ok(E.CanUse(I.Get(14152), "mage", 60), "Robe of the Archmage")
		T.ok(not E.CanUse(I.Get(14152), "priest", 60), "Robe of the Archmage: not a priest's")
		T.ok(E.CanUse(I.Get(1219), "mage", 11), "Redridge Machete (sword)")
		T.ok(not E.CanUse(I.Get(1219), "priest", 11), "no swords for priests")
		T.ok(not E.CanUse(I.Get(7736), "mage", 34), "Fight Club (mace)")
		T.ok(not E.CanUse(I.Get(2919), "mage", 60), "Relic of the Ancients: priests only")
		T.ok(E.CanUse(I.Get(15945), "mage", 60), "Runic Stave (held in off hand)")
		T.ok(E.CanUse(I.Get(11288), "mage", 60), "Greater Magic Wand")
		T.ok(not E.CanUse(fake({ c = 4, sc = 6, inv = 14 }), "mage", 60), "shield")
		T.eq(ns.DATA.proficiency.mage.dw, nil, "no dual wield")
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
	-- A ring/trinket worn with another suffix: not "equipped"; against the weaker one, or (unique)
	-- against the slot that holds it.
	ring_suffixes = function()
		local E = T.addon(FILES).Equip
		local w = { int = 1 }
		local function ring(id, bonus, int, unique, inv)
			return { id = id, bonus = bonus, inv = inv or 11, unique = unique, stats = { int = int }, armor = 0, dps = 0 }
		end
		local worn = { [11] = { inst = ring(2, 100, 8), score = 8 }, [12] = { inst = ring(3, 200, 4), score = 4 } }
		local c = E.Compare(ring(2, 101, 9), w, "priest", worn, false)
		T.ok(not c.equipped, "another suffix is not the worn one"); T.eq(c.slot, 12); T.near(c.gain, 5)
		c = E.Compare(ring(3, 200, 4), w, "priest", worn, false)
		T.ok(c.equipped); T.eq(c.slot, 12)
		c = E.Compare(ring(2, nil, 6), w, "priest", worn, false)
		T.ok(not c.equipped); T.eq(c.slot, 12); T.near(c.gain, 2)
		worn[11].inst.unique = true
		c = E.Compare(ring(2, 101, 9, true), w, "priest", worn, false)
		T.ok(not c.equipped); T.eq(c.slot, 11); T.near(c.gain, 1); T.near(c.base, 8)
		c = E.Compare(ring(2, 102, 7, true), w, "priest", worn, false)
		T.eq(c.slot, 11); T.near(c.gain, -1)
		local tr = { [13] = { inst = ring(5, 300, 2, false, 12), score = 2 } }
		c = E.Compare(ring(5, 301, 3, false, 12), w, "priest", tr, false)
		T.ok(not c.equipped); T.eq(c.slot, 14); T.near(c.gain, 3)
	end,
	nil_instance = function()
		T.eq(T.addon(FILES).Equip.Compare(nil, {}, "priest", {}, false), nil)
	end,
}
