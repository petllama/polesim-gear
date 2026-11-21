local T = require("t")
return {
	bus = function()
		local ns = T.addon({ "Core.lua" })
		local got
		ns.On("X", function(a, b) got = a + b end)
		ns.Fire("X", 2, 3)
		T.eq(got, 5)
	end,
	saved_variables = function()
		local ns = T.addon({ "Core.lua" })
		PoleSimGearDB, PoleSimGearCharDB = nil, nil
		local ready = false
		ns.On("DB_READY", function() ready = true end)
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
		T.ok(ready)
		T.eq(ns.char.spec, "auto")
		T.eq(type(ns.db), "table")
	end,
	slash = function()
		local ns = T.addon({ "Core.lua" })
		local got
		ns.Slash("spec", function(rest) got = rest end)
		SlashCmdList.POLESIMGEAR("spec holy ")
		T.eq(got, "holy")
	end,
}
