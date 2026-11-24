local T = require("t")
return {
	-- The item-level rule for an item with no required level (quest rewards, vendor sets, AH listings):
	-- its item level stands in (leveling items sit about 5 above their level): above lim + 5 = not yet,
	-- said as "item level N". Sources (vendor/container) and the AH scan share it.
	level_less_gate = function()
		local ns = T.addon({ "Core.lua" })
		T.eq(ns.LevelLessGate({ rl = 0, il = 62 }, 21), "item level 62")
		T.eq(ns.LevelLessGate({ rl = 0, il = 26 }, 21), nil, "il 26 at 21: lim + 5")
		T.eq(ns.LevelLessGate({ rl = 0, il = 27 }, 21), "item level 27")
		T.eq(ns.LevelLessGate({ rl = 10, il = 62 }, 21), nil, "a required level: the level gate decides")
		T.eq(ns.LevelLessGate({ il = 62 }, 21), "item level 62", "no rl = 0")
		T.eq(ns.LevelLessGate(nil, 21), nil, "no item record: no rule")
	end,
	-- A level shown as text: blank when missing or 0 (quest rewards with no quest level, level-less
	-- items), never "lvl 0".
	level_text = function()
		local ns = T.addon({ "Core.lua" })
		T.eq(ns.LevelText(22, "lvl "), "lvl 22")
		T.eq(ns.LevelText(0, "lvl "), "")
		T.eq(ns.LevelText(nil, "lvl "), "")
		T.eq(ns.LevelText(-1, "lvl "), "", "scaling quests (-1): no level either")
		T.eq(ns.LevelText(18, " (", ")"), " (18)")
		T.eq(ns.LevelText(0, " (", ")"), "")
	end,
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
	-- One error per key per session (a link redrawn on every bag update must not flood the handler).
	report_once = function()
		local ns = T.addon({ "Core.lua" })
		local errors = {}
		_G.geterrorhandler = function() return function(e) errors[#errors + 1] = e end end
		ns.ReportOnce("a", "boom"); ns.ReportOnce("a", "boom again")
		ns.ReportOnce("b", "other")
		T.eq(#errors, 2); T.eq(errors[1], "boom"); T.eq(errors[2], "other")
	end,
	-- A session with many different bad items keeps at most REPORT_KEYS keys: after that new keys are
	-- neither stored nor reported (a bounded table, a bounded flood); known keys stay silent.
	report_once_capped = function()
		local ns = T.addon({ "Core.lua" })
		local errors = {}
		_G.geterrorhandler = function() return function(e) errors[#errors + 1] = e end end
		for i = 1, ns.REPORT_KEYS + 10 do ns.ReportOnce("k" .. i, "e" .. i) end
		T.eq(ns.REPORT_KEYS, 50)
		T.eq(#errors, 50, "new keys past the cap are not reported")
		ns.ReportOnce("k1", "again")
		T.eq(#errors, 50)
		T.eq(ns._reportedCount(), 50, "and not stored")
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
