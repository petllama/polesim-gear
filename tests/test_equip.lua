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
}
