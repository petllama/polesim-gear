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
		T.eq(B.For("mage", "frost", 30), nil)
	end,
}
