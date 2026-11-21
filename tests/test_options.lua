local T = require("t")
local FILES = { "Core.lua", "Options.lua" }
local function load(db, char)
	local ns = T.addon(FILES)
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = db, char
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	return ns
end
return {
	defaults = function()
		local ns = load({}, {})
		local O = ns.Options
		T.eq(O.Get("tooltip"), true); T.eq(O.Get("arrows"), true); T.eq(O.Get("rewardMark"), true); T.eq(O.Get("ahead"), 0)
		T.eq(O.Get("preferQuest"), true, "prefer upcoming guide quests: on by default")
		local v = O.View()
		T.eq(v.show, "upgrades"); T.eq(v.ahead, 0); T.eq(v.tab, "plan")
		T.eq(v.filters.quest, true); T.eq(v.filters.vendor, true); T.eq(v.filters.world, false, "BoE / World off by default")
	end,
	set_fires_and_saves = function()
		local db = {}
		local ns = load(db, {})
		local got = {}
		ns.On("OPTIONS", function(k, v) got[#got + 1] = k .. "=" .. tostring(v) end)
		ns.Options.Set("arrows", false)
		T.eq(db.options.arrows, false); T.eq(ns.Options.Get("arrows"), false); T.eq(got[1], "arrows=false")
		ns.Options.Set("nonsense", 1)
		T.eq(#got, 1, "unknown keys are refused")
	end,
	-- A change made before ADDON_LOADED (another addon's file, a slash command run early) is queued and
	-- saved at load: the player's latest word wins over the saved value.
	set_before_load_applied_at_load = function()
		local ns = T.addon(FILES)
		local got = {}
		ns.On("OPTIONS", function(k, v) got[#got + 1] = k .. "=" .. tostring(v) end)
		T.eq(ns.Options.Set("arrows", false), true)
		T.eq(ns.Options.Get("arrows"), false, "the session sees it at once")
		local db = { options = { arrows = true, tooltip = false } }
		_G.PoleSimGearDB, _G.PoleSimGearCharDB = db, {}
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
		T.eq(db.options.arrows, false, "saved at load"); T.eq(ns.Options.Get("arrows"), false)
		T.eq(ns.Options.Get("tooltip"), false, "other saved values kept")
		T.eq(got[#got], "arrows=false", "fired again once it is saved")
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
		db.options.arrows = true
		ns.Fire("DB_READY")
		T.eq(db.options.arrows, true, "applied once")
	end,
	view_ahead_defaults_from_option = function()
		local ns = load({ options = { ahead = 3 } }, {})
		T.eq(ns.Options.View().ahead, 3, "first use: the account default")
		local char = { view = { ahead = 1, filters = { quest = false } } }
		ns = load({ options = { ahead = 3 } }, char)
		local v = ns.Options.View()
		T.eq(v.ahead, 1, "the character's own"); T.eq(v.filters.quest, false); T.eq(v.filters.dungeon, true, "missing keys filled")
	end,
	bad_saved_values_repaired = function()
		local ns = load({ options = "x" }, { view = { show = "nope", ahead = 9, filters = 4 } })
		T.eq(ns.Options.Get("tooltip"), true)
		local v = ns.Options.View()
		T.eq(v.show, "upgrades"); T.eq(v.ahead, 5, "clamped 0..5"); T.eq(v.filters.quest, true)
	end,
}
