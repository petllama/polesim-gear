local T = require("t")
local FILES = { "Core.lua", "Coexist.lua" }
return {
	gear_on = function()
		local C = T.addon(FILES).Coexist
		_G.Polestar = nil
		T.ok(not C.PolestarGearOn(), "no Polestar")
		_G.Polestar = { Gear = { IsEnabled = function() return true end } }
		T.ok(C.PolestarGearOn())
		_G.Polestar = { Gear = { IsEnabled = function() return false end } }
		T.ok(not C.PolestarGearOn())
		_G.Polestar = { Gear = { IsEnabled = function() error("changed upstream") end } }
		T.ok(not C.PolestarGearOn(), "an error reads as off")
		_G.Polestar = {}
		T.ok(not C.PolestarGearOn(), "module removed upstream")
		_G.Polestar = nil
	end,
	should_ask = function()
		local C = T.addon(FILES).Coexist
		T.ok(C.ShouldAsk(true, nil)); T.ok(not C.ShouldAsk(true, true)); T.ok(not C.ShouldAsk(false, nil))
		T.ok(not C.ShouldAsk(true, "no"), "an answer is remembered whatever it was")
	end,
	turn_off = function()
		local C = T.addon(FILES).Coexist
		local set
		_G.Polestar = { Set = function(path, v) set = { path, v } end, Gear = { IsEnabled = function() return true end } }
		T.ok(C.TurnOff()); T.eq(set[1], "gear.enabled"); T.eq(set[2], false)
		_G.Polestar = { Set = function() error("boom") end }
		T.ok(not C.TurnOff(), "a failing Set")
		_G.Polestar = {}
		T.ok(not C.TurnOff())
		_G.Polestar = nil
	end,
	label_while_both_score = function()
		local C = T.addon(FILES).Coexist
		_G.Polestar = { Gear = { IsEnabled = function() return true end } }
		T.eq(C.Label(), true)
		_G.Polestar = { Gear = { IsEnabled = function() return false end } }
		T.eq(C.Label(), false)
		_G.Polestar = nil
	end,
}
