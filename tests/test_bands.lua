local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Bands.lua" }
return {
	picks = function()
		local B = T.addon(FILES).Bands
		local b, lo, sd = B.For("priest", "shadow", 34)
		T.eq(b.upTo, 39); T.eq(lo, 30); T.eq(sd.ref, "spShadow")
		T.eq((B.For("priest", "shadow", 5)).upTo, 19)
		local top, tlo = B.For("priest", "holy", 60)
		T.eq(top.upTo, 60); T.eq(tlo, 60)
		local mb, mlo, msd = B.For("mage", "frost", 18)
		T.eq(mb.upTo, 19); T.eq(mlo, 1); T.eq(msd.ref, "spFrost")
		T.eq(select(3, B.For("mage", "fire", 30)).ref, "spFire")
		T.eq(select(3, B.For("mage", "arcane", 60)).ref, "spArcane")
		T.eq(select(3, B.For("warlock", "affliction", 30)).ref, "spShadow")
		T.eq(B.For("warrior", "arms", 30), nil, "a class with no shipped weights")
		T.eq(B.For("druid", "feral", 30), nil, "a spec with no shipped weights")
	end,
	above_the_last_band = function()
		local B = T.addon(FILES).Bands
		local sd = select(3, B.For("priest", "shadow", 1))
		local last, prev = sd.bands[#sd.bands], sd.bands[#sd.bands - 1]
		local b, lo = B.For("priest", "shadow", last.upTo + 5)
		T.eq(b, last); T.eq(lo, prev.upTo + 1, "the last band's own first level")
	end,
	nil_level = function()
		T.eq(T.addon(FILES).Bands.For("priest", "shadow", nil), nil)
	end,
}
