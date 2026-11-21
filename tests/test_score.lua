local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua" }
local W = { hit = 2.0, spellHit = 3.0, int = 0.5, dps = 4.0, rdps = 6.0, armor = 0.1 }
local function inst(stats) return { stats = stats, armor = 50, dps = 10.0, weapon = true, inv = 13 } end
return {
	forever_hit_and_roles = function()
		local S = T.addon(FILES).Score
		local i = inst({ hit = 1, int = 10 })
		local gear = 1 * (2 + 3) + 10 * 0.5 + 50 * 0.1
		T.near(S.Score(i, W, "rogue", "gear"), gear)
		T.near(S.Score(i, W, "rogue", "mh"), gear + 40)
		T.near(S.Score(i, W, "rogue", "oh"), gear + 20)
		T.near(S.Score(i, W, "rogue", "ranged"), gear + 60)
		T.near(S.Score(inst({ mhit = 1 }), W, "rogue", "gear"), 2 + 5)
	end,
	off_hand_dps_only_for_one_handers = function()
		local S = T.addon(FILES).Score
		local i = inst({})
		i.inv = 17
		T.near(S.Score(i, W, "rogue", "oh"), 5)
	end,
	spell_damage_and_feral = function()
		local S = T.addon(FILES).Score
		local w = { sp = 1, ap = 0.5, rap = 0.25 }
		T.near(S.StatScore({ spDmg = 4 }, w, "priest"), 4)
		T.near(S.StatScore({ ap = 4 }, w, "priest"), 3)
		T.near(S.StatScore({ apFeral = 10 }, w, "priest"), 0)
		T.near(S.StatScore({ apFeral = 10 }, w, "druid"), 5)
	end,
	nil_item = function()
		T.eq(T.addon(FILES).Score.Score(nil, W, "priest", "gear"), 0)
	end,
}
