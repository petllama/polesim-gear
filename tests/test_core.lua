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
	event_handler_errors_are_contained = function()
		local ns = T.addon({ "Core.lua" })
		local errors, ran = {}, false
		_G.geterrorhandler = function() return function(e) errors[#errors + 1] = e end end
		ns.RegisterEvent("BAG_UPDATE", function() error("boom") end)
		ns.RegisterEvent("BAG_UPDATE", function() ran = true end)
		ns._frame.scripts.OnEvent(ns._frame, "BAG_UPDATE")
		T.ok(ran, "the next handler still runs"); T.eq(#errors, 1)
	end,
	equipment_changes_coalesce = function()
		local ns = T.addon({ "Core.lua" })
		local W = require("wow")
		local n = 0
		ns.On("STATE", function(e) if e == "PLAYER_EQUIPMENT_CHANGED" then n = n + 1 end end)
		for slot = 1, 5 do ns._frame.scripts.OnEvent(ns._frame, "PLAYER_EQUIPMENT_CHANGED", slot, true) end
		T.eq(n, 0, "not before the next frame")
		W.flush()
		T.eq(n, 1, "one STATE for the burst")
		ns._frame.scripts.OnEvent(ns._frame, "PLAYER_EQUIPMENT_CHANGED", 1, false)
		W.flush()
		T.eq(n, 2)
	end,
	talent_events = function()
		local ns = T.addon({ "Core.lua" })
		for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE" }) do
			T.ok(ns._frame.events[e], e)
		end
	end,
	slash_usage = function()
		local ns = T.addon({ "Core.lua" })
		ns.Slash("spec", function() end)
		local said
		ns.Print = function(...) said = table.concat({ ... }, " ") end
		SlashCmdList.POLESIMGEAR("")
		T.ok(said and said:find("/psg spec", 1, true), said)
		said = nil
		SlashCmdList.POLESIMGEAR("nonsense")
		T.ok(said and said:find("/psg spec", 1, true), said)
	end,
	slash = function()
		local ns = T.addon({ "Core.lua" })
		local got
		ns.Slash("spec", function(rest) got = rest end)
		SlashCmdList.POLESIMGEAR("spec holy ")
		T.eq(got, "holy")
	end,
}
