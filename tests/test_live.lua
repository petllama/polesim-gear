local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua", "Live.lua" }
return {
	stats_mapping = function()
		local L = T.addon(FILES).Live
		local s, armor, dps = L.Stats({ ITEM_MOD_INTELLECT_SHORT = 7, ITEM_MOD_CRIT_RATING_SHORT = 14,
			ITEM_MOD_SPELL_POWER_SHORT = 12, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 3, RESISTANCE0_NAME = 40,
			ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12.5, ITEM_MOD_HIT_SPELL_RATING_SHORT = 10 }, nil)
		T.eq(s.int, 7); T.near(s.crit, 1); T.eq(s.sp, 12); T.eq(s.spDmg, 3); T.near(s.spellHit, 1)
		T.eq(armor, 40); T.eq(dps, 12.5); T.eq(s.armor, nil)
	end,
	fills_missing_equip_families = function()
		local L = T.addon(FILES).Live
		local rec = { s = { int = 5, sp = 8, mp5 = 2 } }
		local s, _, _, filled = L.Stats({ ITEM_MOD_INTELLECT_SHORT = 5 }, rec)
		T.eq(s.sp, 8); T.eq(s.mp5, 2)
		T.ok(filled.sp and filled.mp5, "filled stats are marked"); T.eq(filled.int, nil)
		s, _, _, filled = L.Stats({ ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 8 }, rec)
		T.eq(s.sp, nil, "the spell family came from the client: no double count"); T.eq(s.spDmg, 8)
		T.eq(filled.sp, nil); T.ok(filled.mp5)
		s, _, _, filled = L.Stats({ ITEM_MOD_STAMINA_SHORT = 1 }, { s = { int = 5 } })
		T.eq(s.int, nil, "base stats never come from the table"); T.eq(next(filled), nil)
	end,
	-- The random suffix of a link: the field that is one of the item's known suffixes (armory.item_from_link).
	bonus_from_link = function()
		local ns = T.addon(FILES)
		local rec = ns.Items.Get(6540)
		T.eq(ns.Live.Bonus("|cff1eff00|Hitem:6540::::::::18:::::1:12720:::|h[x]|h|r", rec), 12720)
		T.eq(ns.Live.Bonus("item:6540::::::::18::::::::", rec), nil)
		T.eq(ns.Live.Bonus("item:6540::::::::18:::::1:99999:::", rec), nil, "not one of its suffixes")
		T.eq(ns.Live.Bonus("item:6540:12720", nil), nil, "unknown item")
	end,
	instance = function()
		local ns = T.addon(FILES)
		local client = {
			Info = function() return "INVTYPE_LEGS", 14, 4, 1, 2 end,
			Stats = function() return { ITEM_MOD_INTELLECT_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 3, RESISTANCE0_NAME = 28 } end,
		}
		local i = ns.Live.Instance("|cff1eff00|Hitem:6540::::::::18:::::1:12720:::|h[Willow Pants of the Owl]|h|r", client)
		T.eq(i.id, 6540); T.eq(i.inv, 7); T.eq(i.rl, 14); T.eq(i.armor, 28); T.eq(i.stats.int, 3); T.eq(i.c, 4)
		T.eq(i.bonus, 12720, "the suffix, so Equip tells copies apart")
		local w = ns.DATA.specs.priest.shadow.bands[1].w
		T.near(ns.Score.Score(i, w, "priest", "gear"),
			ns.Score.Score(ns.Score.Instance(ns.Items.Get(6540), 12720), w, "priest", "gear"), 1e-9, "live = table")
		local pending = { Info = function() return nil end, Stats = function() return nil end }
		local none, why = ns.Live.Instance("item:6540", pending)
		T.eq(none, nil); T.eq(why, "pending")
		T.eq(ns.Live.Instance("item:6540", { Info = function() return "INVTYPE_BODY" end, Stats = client.Stats }), nil, "shirt")
	end,
	-- An equip bonus the client leaves out comes from the table, and the instance says which.
	instance_marks_filled = function()
		local ns = T.addon(FILES)
		local rec = ns.Items.Get(11288) -- Greater Magic Wand: sp from its equip line
		T.ok(rec and rec.s.sp, "fixture item has table spell power")
		local client = {
			Info = function() return "INVTYPE_RANGEDRIGHT", 13, 2, 19, 2 end,
			Stats = function() return { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = rec.dps } end,
		}
		local i = ns.Live.Instance("item:11288", client)
		T.eq(i.stats.sp, rec.s.sp); T.ok(i.filled.sp)
		T.eq(i.weapon, true)
	end,
	-- The client knows the item but has no stats yet: the shipped facts (with the link's suffix).
	instance_from_table_when_no_stats = function()
		local ns = T.addon(FILES)
		local client = { Info = function() return "INVTYPE_LEGS", 13, 4, 1, 2 end, Stats = function() return nil end }
		local i = ns.Live.Instance("item:6540::::::::18:::::1:12720:::", client)
		T.eq(i.bonus, 12720); T.eq(i.stats.int, ns.Score.Instance(ns.Items.Get(6540), 12720).stats.int)
		T.ok(i.stats.int and i.stats.int > 0)
	end,
}
