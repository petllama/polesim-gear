-- Melee/hunter weapons (PoleSim design 2026-11-22-melee-weapon-weights): weapon speed relative to the band's
-- reference weapon, off-hand DPS/speed, weapon-type rules, dual wield, the weapon-model gate.
local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Bands.lua",
	"Equip.lua", "Spec.lua" }
-- synthetic band weights (the results run has not happened yet)
local W = { str = 1, dps = 5, speed = 2, ohDps = 2.5, ohSpeed = -1, rdps = 4, rspeed = 1.5,
	_mhSpeed = 2.6, _ohSpeed = 1.6, _rSpeed = 2.8 }
local function weapon(dps, speed, inv, extra)
	local i = { stats = {}, armor = 0, dps = dps, speed = speed, weapon = true, inv = inv or 13, c = 2, sc = 7 }
	for k, v in pairs(extra or {}) do i[k] = v end
	return i
end

return {
	reference_speed_scores_dps_alone = function()
		local S = T.addon(FILES).Score
		T.near(S.Score(weapon(20, 2.6), W, "rogue", "mh"), 100)
		T.near(S.Score(weapon(20, 3.1), W, "rogue", "mh"), 101)
		T.near(S.Score(weapon(20, 2.2), W, "rogue", "mh"), 99.2)
	end,
	-- armory.SPEED_RANGE: the speed weights hold within +-0.6 s of the reference weapon (PoleSim's linearity
	-- check), so a weapon's speed difference counts at most that far
	speed_term_clamped_to_the_measured_range = function()
		local S = T.addon(FILES).Score
		T.eq(S.SPEED_RANGE, 0.6)
		T.near(S.Score(weapon(20, 3.6), W, "rogue", "mh"), 101.2)
		T.near(S.Score(weapon(20, 1.6), W, "rogue", "mh"), 98.8)
		T.near(S.Score(weapon(10, 2.6), W, "rogue", "oh"), 25 - 0.6)
		local p = S.Parts(weapon(20, 3.8), W, "rogue", "mh")
		T.near(p[2][2], 0.6)
		T.near(p[2][5], 1.2)
	end,
	off_hand_own_weights_else_half = function()
		local S = T.addon(FILES).Score
		T.near(S.Score(weapon(10, 1.4), W, "rogue", "oh"), 25 + (1.4 - 1.6) * -1)
		T.near(S.Score(weapon(10, 1.4), { dps = 5 }, "rogue", "oh"), 25)
	end,
	ranged_speed = function()
		local S = T.addon(FILES).Score
		T.near(S.Score(weapon(10, 3.0, 15), W, "hunter", "ranged"), 40 + 0.2 * 1.5)
	end,
	no_anchor_no_speed_term = function()
		local S = T.addon(FILES).Score
		T.near(S.Score(weapon(20, 3.6), { dps = 5, speed = 2 }, "rogue", "mh"), 100)
	end,
	parts_show_speed_and_off_hand = function()
		local S = T.addon(FILES).Score
		local p = S.Parts(weapon(20, 3.1), W, "rogue", "mh")
		T.eq(#p, 2)
		T.eq(p[2][1], "speed")
		T.near(p[2][2], 0.5)
		T.near(p[2][5], 1.0)
		local o = S.Parts(weapon(12, 1.3), W, "rogue", "oh")
		T.eq(o[1][3] .. "," .. o[2][3], "ohDps,ohSpeed")
	end,
	shipped_items_carry_speed = function()
		local ns = T.addon(FILES)
		local it = ns.Items.Get(15242) -- Honed Stiletto
		T.near(it.speed, 1.4)
		T.near(ns.Score.Instance(it).speed, 1.4)
		T.eq(ns.Items.Get(6540).speed, nil, "not a weapon")
	end,
	weapon_model_gate = function()
		local ns = T.addon(FILES)
		local Sp = ns.Spec
		T.ok(Sp.Supported("priest", "shadow"), "casters need no weapon model")
		T.ok(Sp.Supported("warrior", "arms"), "arms: its bands carry weaponModel (melee results run)")
		T.ok(not Sp.Supported("warrior", "protection"), "tanks wait for their weapon-model bands")
		ns.DATA.specs.warrior.arms.weaponModel = nil
		T.ok(not Sp.Supported("warrior", "arms"), "no weaponModel, no scores")
		ns.DATA.specs.warrior.protection.weaponModel = 1
		T.ok(Sp.Supported("warrior", "protection"), "lights up once the bands carry weaponModel")
		T.eq(table.concat(Sp.Keys("warrior"), ","), "fury,protection")
		T.eq(table.concat(Sp.ORDER.rogue, ","), "assassination,combat,subtlety")
	end,
	dagger_rule_blocks_the_main_hand = function()
		local ns = T.addon(FILES)
		local E = ns.Equip
		local rules = ns.DATA.specs.rogue.assassination.rules
		local sword = weapon(20, 2.6, 13, { id = 1, sc = 7 })
		local worn = {}
		local c = E.Compare(sword, W, "rogue", worn, false, rules)
		T.eq(c.gain, 0)
		T.ok(c.blocked and c.blocked:find("dagger"), "reason")
		local dagger = weapon(20, 1.8, 13, { id = 2, sc = 15 })
		T.ok(not E.Compare(dagger, W, "rogue", worn, false, rules).blocked, "daggers are fine")
		-- dual wield: the sword still fits the off hand
		local oh = E.Compare(sword, W, "rogue", worn, true, rules)
		T.eq(oh.slot, 17)
		T.ok(oh.gain > 0 and not oh.blocked, "off hand")
	end,
	hunter_ranged_rule = function()
		local ns = T.addon(FILES)
		local rules = ns.DATA.specs.hunter.marksmanship.rules
		local thrown = weapon(10, 2.0, 25, { id = 3, sc = 16 })
		local c = ns.Equip.Compare(thrown, W, "hunter", {}, false, rules)
		T.ok(c.blocked and c.blocked:find("bow, gun or crossbow"), "thrown is no hunter weapon")
		T.ok(not ns.Equip.Compare(weapon(10, 2.0, 15, { id = 4, sc = 2 }), W, "hunter", {}, false, rules).blocked, "bow")
	end,
	browser_off_hand_lists_one_handers_when_dual_wielding = function()
		local ns = T.addon({ "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
			"Equip.lua", "Sources.lua", "Browser.lua" })
		local B = ns.Browser
		local oh = { key = "offhand" }
		T.eq(table.concat(B.Invs(oh, "dw", true), ","), "13,22")
		T.eq(#B.Invs(oh, "dw", false), 0, "no Dual Wield yet: no off-hand weapons")
		T.eq(table.concat(B.Invs(oh, "shield", true), ","), "14", "a shield spec never gets one-handers there")
	end,
	can_dw_by_class_level_and_style = function()
		local ns = T.addon({ "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
			"Bands.lua", "Equip.lua", "Spec.lua", "Context.lua" })
		local C = ns.Context
		T.ok(C.CanDw("rogue", 10, { style = "dw" }), "rogues dual wield from 10")
		T.ok(not C.CanDw("rogue", 9, { style = "dw" }))
		T.ok(not C.CanDw("warrior", 19, { style = "dw" }), "warriors from 20")
		T.ok(C.CanDw("warrior", 20, { style = "dw" }))
		T.ok(not C.CanDw("warrior", 30, { style = "2h" }), "Arms plays a two-hander")
		T.ok(not C.CanDw("shaman", 60, { style = "2h" }), "no shaman dual wield in Forever")
		T.ok(not C.CanDw("hunter", 30, { style = "2h" }))
	end,
	weight_rows_skip_the_anchors = function()
		local ns = T.addon({ "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
			"Equip.lua", "Sources.lua", "Browser.lua", "Plan.lua", "Wishlist.lua", "View.lua" })
		local keys = {}
		for _, r in ipairs(ns.View.WeightRows(W)) do keys[#keys + 1] = r.key end
		table.sort(keys)
		T.eq(table.concat(keys, ","), "dps,ohDps,ohSpeed,rdps,rspeed,speed,str")
	end,
	tooltip_says_why_not = function()
		local ns = T.addon({ "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
			"Equip.lua", "Tooltip.lua" })
		local cmp = { score = 100, gain = 0, base = 50, slot = 16, blocked = "Backstab, Ambush and Mutilate need a dagger in the main hand" }
		local ctx = { spec = "assassination", lo = 30, band = { upTo = 39 }, ref = "agi", level = 30, w = W, cls = "rogue" }
		local lines = ns.Tooltip.Lines(cmp, weapon(20, 2.6), ctx, true, true)
		T.eq(lines[1][2], "not for Assassination")
		local found, minus = false, false
		for _, l in ipairs(lines) do
			if l[1] == cmp.blocked then found = true end
			if l[1] == "  minus worn" then minus = true end
		end
		T.ok(found, "the rule's reason"); T.ok(not minus, "no gain sum for a blocked item")
		local how = ns.Tooltip.Lines({ score = 102, gain = 2, base = 100, slot = 16 }, weapon(20, 3.6), ctx, true, true)
		local speedLine = false
		for _, l in ipairs(how) do if l[1]:find("Weapon speed", 1, true) then speedLine = true end end
		T.ok(speedLine, "how? shows the speed part")
	end,
	dual_wield_one_hander_takes_the_better_hand = function()
		local E = T.addon(FILES).Equip
		local mh = weapon(30, 2.6, 13, { id = 10 })
		local worn = { [16] = { inst = mh, score = 150 } }
		local fast = weapon(12, 1.4, 13, { id = 11 })
		local c = E.Compare(fast, W, "rogue", worn, true, nil)
		T.eq(c.slot, 17, "a weak one-hander goes to the empty off hand")
		T.near(c.gain, 30 + 0.2)
		local single = E.Compare(fast, W, "rogue", worn, false, nil)
		T.eq(single.slot, 16, "no dual wield: main hand only")
	end,
}
