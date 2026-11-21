local T = require("t")
local FILES = { "Core.lua", "Coexist.lua" }
local KEY = "POLESIMGEAR_POLESTAR_GEAR"
local function W() return require("wow") end
local function event(ns, name, ...) ns._frame.scripts.OnEvent(ns._frame, name, ...) end
-- The addon after ADDON_LOADED, a priest, Polestar's Gear on: -> ns, shown (StaticPopup_Show keys),
-- set (the last Polestar.Set call)
local function prompt()
	local ns = T.addon(FILES)
	PoleSimGearDB, PoleSimGearCharDB = nil, nil
	event(ns, "ADDON_LOADED", "PoleSimGear")
	ns.Context = { ClassKey = function() return "priest" end }
	ns.Print = function() end
	local shown, set = {}, {}
	_G.StaticPopup_Show = function(which) shown[#shown + 1] = which end
	_G.Polestar = {
		Set = function(path, v) set[1], set[2] = path, v end,
		Gear = { IsEnabled = function() return set[2] ~= false end },
	}
	return ns, shown, set
end
local function done()
	_G.Polestar, _G.StaticPopup_Show = nil, nil
end
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
	-- The one-time prompt: after login (5 s), only while Polestar's Gear is on, never in combat.
	prompt_yes = function()
		local ns, shown, set = prompt()
		event(ns, "PLAYER_LOGIN")
		T.eq(#shown, 0, "not at once")
		W().flush()
		T.eq(#shown, 1); T.eq(shown[1], KEY)
		local d = StaticPopupDialogs[KEY]
		T.ok(d and d.button1 and d.button2 and d.timeout == 0 and d.hideOnEscape)
		T.eq(d.OnAccept(), nil, "hides the dialog")
		T.eq(set[1], "gear.enabled"); T.eq(set[2], false)
		T.eq(ns.db.askedPolestarGear, "yes")
		ns.Coexist.MaybeAsk()
		T.eq(#shown, 1, "never again")
		done()
	end,
	-- Yes when Set fails: the message says whether the value was stored (a Polestar listener erred after
	-- storing it: /reload applies it) or not (turn it off by hand), read back through Polestar.Get.
	prompt_yes_fallbacks = function()
		local ns, shown = prompt()
		local said = {}
		ns.Print = function(msg) said[#said + 1] = msg end
		local stored
		_G.Polestar.Get = function() return stored end
		_G.Polestar.Set = function(_, v) stored = v error("listener") end
		ns.Coexist.MaybeAsk()
		StaticPopupDialogs[KEY].OnAccept()
		T.ok(said[1] and said[1]:find("/reload", 1, true), "stored, a listener erred: " .. tostring(said[1]))
		_G.Polestar.Set = function() error("Set changed upstream") end
		stored = nil
		StaticPopupDialogs[KEY].OnAccept()
		T.ok(said[2] and said[2]:find("Questing > Rewards & gear > Gear advice", 1, true), "not stored: " .. tostring(said[2]))
		T.ok(not said[2]:find("/reload", 1, true))
		_G.Polestar.Set = function(_, v) stored = v end
		StaticPopupDialogs[KEY].OnAccept()
		T.ok(said[3]:find("Polestar options: Questing > Rewards & gear > Gear advice", 1, true), "the options path: " .. said[3])
		done()
	end,
	prompt_no = function()
		local ns, shown, set = prompt()
		ns.Coexist.MaybeAsk()
		T.eq(#shown, 1)
		StaticPopupDialogs[KEY].OnCancel({}, nil, "clicked")
		T.eq(set[1], nil, "Polestar's setting untouched")
		T.eq(ns.db.askedPolestarGear, "no")
		T.eq(ns.Coexist.Label(), true, "our line is labelled")
		ns.Coexist.MaybeAsk()
		T.eq(#shown, 1, "never again")
		done()
	end,
	-- The client cancels a dialog it could not show (no free frame: OnCancel(nil, data)) or that another
	-- one replaced ("override"): no answer yet, so the next login asks again.
	prompt_not_answered = function()
		local ns, shown = prompt()
		ns.Coexist.MaybeAsk()
		StaticPopupDialogs[KEY].OnCancel(nil, nil)
		StaticPopupDialogs[KEY].OnCancel({}, nil, "override")
		T.eq(ns.db.askedPolestarGear, nil)
		done()
	end,
	prompt_waits_for_combat_end = function()
		local ns, shown = prompt()
		_G.InCombatLockdown = function() return true end
		ns.Coexist.MaybeAsk()
		T.eq(#shown, 0, "not in combat")
		event(ns, "PLAYER_REGEN_ENABLED")
		T.eq(#shown, 0, "still in combat")
		_G.InCombatLockdown = function() return false end
		event(ns, "PLAYER_REGEN_ENABLED")
		T.eq(#shown, 1, "after combat")
		event(ns, "PLAYER_REGEN_ENABLED")
		T.eq(#shown, 1, "once")
		done()
	end,
	prompt_silent_without_module = function()
		local ns, shown = prompt()
		_G.Polestar = {}
		ns.Coexist.MaybeAsk()
		_G.Polestar = { Gear = { IsEnabled = function() return false end } }
		ns.Coexist.MaybeAsk()
		T.eq(#shown, 0)
		T.eq(ns.db.askedPolestarGear, nil, "nothing remembered: asked if the module comes back on")
		done()
	end,
	prompt_not_for_other_classes = function()
		local ns, shown = prompt()
		ns.Context.ClassKey = function() return nil end
		ns.Coexist.MaybeAsk()
		T.eq(#shown, 0)
		done()
	end,
	-- /psg polestar forgets the answer and asks again (for testing; also how to change one's mind).
	slash_asks_again = function()
		local ns, shown = prompt()
		ns.db.askedPolestarGear = "no"
		SlashCmdList.POLESIMGEAR("polestar")
		T.eq(ns.db.askedPolestarGear, nil)
		T.eq(#shown, 1)
		done()
	end,
	ask_again = function()
		local ns, shown = prompt()
		ns.db.askedPolestarGear = "no"
		ns.Coexist.AskAgain()
		T.eq(ns.db.askedPolestarGear, nil, "the answer is cleared")
		T.eq(shown[#shown], KEY, "asked again now")
		done()
	end,
}
