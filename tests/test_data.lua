local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua" }
return {
	loads = function()
		local ns = T.addon(FILES)
		T.eq(ns.DATA.build, "1.60.1.70938")
		T.eq(ns.DATA.items:sub(1, 1), "\n")
		T.ok(ns.DATA.items:find("\n6540\tWillow Pants\t", 1, true))
		T.eq(ns.DATA.suffixes[12720].n, "of the Owl")
		T.eq(ns.DATA.rating.crit, 14)
		T.eq(#ns.DATA.specs.priest.holy.bands, 6)
		T.eq(ns.DATA.specs.priest.shadow.ref, "spShadow")
		T.eq(ns.DATA.proficiency.priest.bit, 16)
	end,
	healers_are_kill_sim = function()
		local ns = T.addon(FILES)
		for _, spec in ipairs({ "holy", "discipline" }) do
			for _, b in ipairs(ns.DATA.specs.priest[spec].bands) do
				T.eq(b.label, "Kill sim", spec)
				T.eq(b.w.heal, nil, spec)
			end
		end
	end,
}
