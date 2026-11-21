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
	-- Ratings to % with the shipped divisors (ns.DATA.rating), rounded to 2 decimals like a suffix's.
	rating_rounding = function()
		local ns = T.addon(FILES)
		local s = ns.Live.Stats({ ITEM_MOD_CRIT_RATING_SHORT = 10, ITEM_MOD_HIT_MELEE_RATING_SHORT = 7 }, nil)
		T.eq(s.crit, 0.71); T.eq(s.mhit, 0.7)
		ns.DATA.rating.crit = 7
		T.eq(ns.Live.Stats({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14 }, nil).spellCrit, 2, "divisor from the data")
	end,
	-- Two client names for one bonus (mp5 as MANA_REGENERATION and POWER_REGEN0; melee and ranged
	-- hit/crit) count once: the larger, not the sum.
	duplicate_names_count_once = function()
		local L = T.addon(FILES).Live
		local s = L.Stats({ ITEM_MOD_MANA_REGENERATION_SHORT = 4, ITEM_MOD_POWER_REGEN0_SHORT = 4,
			ITEM_MOD_HEALTH_REGEN_SHORT = 2, ITEM_MOD_HEALTH_REGENERATION_SHORT = 3,
			ITEM_MOD_HIT_MELEE_RATING_SHORT = 10, ITEM_MOD_HIT_RANGED_RATING_SHORT = 10,
			ITEM_MOD_CRIT_MELEE_RATING_SHORT = 14, ITEM_MOD_CRIT_RANGED_RATING_SHORT = 28 }, nil)
		T.eq(s.mp5, 4); T.eq(s.hp5, 3); T.eq(s.mhit, 1); T.eq(s.mcrit, 2)
	end,
	-- An item not in the shipped table has no class mask: it scores only when the class can use it by
	-- armor/weapon proficiency (Equip.CanUse); a class restriction on such an item is not known.
	unlisted_item_by_proficiency = function()
		local ns = T.addon(FILES)
		T.eq(ns.Items.Get(999999), nil)
		local function at(c, sc, loc)
			return ns.Live.Instance("item:999999", { Info = function() return loc or "INVTYPE_CHEST", 10, c, sc, 2 end,
				Stats = function() return { ITEM_MOD_INTELLECT_SHORT = 5 } end })
		end
		local cloth, plate, sword = at(4, 1), at(4, 4), at(2, 7, "INVTYPE_WEAPON")
		T.eq(cloth.cm, 0)
		T.ok(ns.Equip.CanUse(cloth, "priest", 20), "cloth")
		T.ok(not ns.Equip.CanUse(plate, "priest", 60), "plate")
		T.ok(not ns.Equip.CanUse(sword, "priest", 60), "sword")
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
		T.eq(ns.Live.Bonus("|cff1eff00|Hitem:6540::::::::18::::1:12720::::|h[x]|h|r", rec), 12720)
		T.eq(ns.Live.Bonus("item:6540::::::::18::::::::", rec), nil)
		T.eq(ns.Live.Bonus("item:6540::::::::18::::1:99999::::", rec), nil, "not one of its suffixes")
		T.eq(ns.Live.Bonus("item:6540:12720", nil), nil, "unknown item")
	end,
	-- Only the bonus-ID list counts (numBonusIDs is the 13th field after "item:", the layout of the
	-- client's item strings), plus the classic suffixID field (7th) when it is one of the item's
	-- suffixes: a uniqueID, link level or modifier value equal to a suffix id is not a suffix.
	bonus_list_only = function()
		local ns = T.addon(FILES)
		local rec = ns.Items.Get(6540)
		T.eq(ns.Live.Bonus("item:6540::::::::18::::2:5:12720::::", rec), 12720, "second of two bonus ids")
		T.eq(ns.Live.Bonus("item:6540:::::::12720:18::::::::", rec), nil, "uniqueID")
		T.eq(ns.Live.Bonus("item:6540::::::::12720::::::::", rec), nil, "link level")
		T.eq(ns.Live.Bonus("item:6540::::::::18::::0:1:9:12720:::", rec), nil, "a modifier value")
		T.eq(ns.Live.Bonus("item:6540::::::::18::::1:5:1:9:12720:::", rec), nil, "modifier after a non-suffix bonus")
		T.eq(ns.Live.Bonus("item:6540::::::12720::18::::::::", rec), 12720, "classic suffixID field")
		T.eq(ns.Live.Bonus("item:6540::::::-12720::18::::::::", rec), nil, "negative suffixID")
	end,
	instance = function()
		local ns = T.addon(FILES)
		local client = {
			Info = function() return "INVTYPE_LEGS", 14, 4, 1, 2 end,
			Stats = function() return { ITEM_MOD_INTELLECT_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 3, RESISTANCE0_NAME = 28 } end,
		}
		local i = ns.Live.Instance("|cff1eff00|Hitem:6540::::::::18::::1:12720::::|h[Willow Pants of the Owl]|h|r", client)
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
		local i = ns.Live.Instance("item:6540::::::::18::::1:12720::::", client)
		T.eq(i.bonus, 12720); T.eq(i.stats.int, ns.Score.Instance(ns.Items.Get(6540), 12720).stats.int)
		T.ok(i.stats.int and i.stats.int > 0)
		T.eq(i.fromTable, true, "built from the table: tagged so callers do not keep it")
		local live = ns.Live.Instance("item:6540::::::::18::::1:12720::::",
			{ Info = client.Info, Stats = function() return { ITEM_MOD_INTELLECT_SHORT = 3 } end })
		T.eq(live.fromTable, nil, "client stats: not tagged")
	end,
}
