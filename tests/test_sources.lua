local T = require("t")
local FILES = { "Core.lua", "Sources.lua" }
local done = { [500] = true }
local player = { faction = "H", classBit = 16, raceBit = 16, completed = function(q) return done[q] == true end }
local function q(kw)
	local t = { id = 100, level = 20, title = "Q" }
	for k, v in pairs(kw or {}) do t[k] = v end
	return t
end
return {
	quest_ok = function()
		local S = T.addon(FILES).Sources
		T.ok(S.QuestOk(q(), player, 20))
		T.eq(select(2, S.QuestOk(q({ faction = "A" }), player, 20)), "other faction")
		T.eq(select(2, S.QuestOk(q({ classes = 8 }), player, 20)), "other classes")
		T.ok(S.QuestOk(q({ classes = 16 }), player, 20))
		T.eq(select(2, S.QuestOk(q({ races = 1 }), player, 20)), "other races")
		T.ok(S.QuestOk(q({ races = 255 }), player, 20), "every race")
		T.eq(select(2, S.QuestOk(q({ id = 500 }), player, 20)), "done")
		T.eq(select(2, S.QuestOk(q({ level = 30 }), player, 20)), "quest from level 25")
		-- (plan: level 30 / minLevel 18 at 20 was "ok", but a level 30 quest is red at 20 (> lim + 5) in the
		-- plan's code and the website alike; minLevel replacing level - 5 is shown with these instead)
		T.ok(S.QuestOk(q({ level = 25, minLevel = 18 }), player, 20), "min level 18")
		T.eq(select(2, S.QuestOk(q({ level = 25, minLevel = 21 }), player, 20)), "quest from level 21", "min level wins over level - 5")
		T.eq(select(2, S.QuestOk(q({ level = 26, minLevel = 18 }), player, 20)), "level 26 quest")
	end,
	-- The Codex's race masks carry bits above 32 (Elwynn quests: 4294967373 = 2^32 + 0x4D): the client's
	-- bit library works on the low 32 bits, so an Alliance-races quest is still other races for Undead.
	quest_races_high_bits = function()
		local S = T.addon(FILES).Sources
		T.eq(select(2, S.QuestOk(q({ races = 4294967373 }), player, 20)), "other races")
		T.ok(S.QuestOk(q({ races = 4294967373 }), { faction = "A", classBit = 16, raceBit = 1, completed = player.completed }, 20))
	end,
	needs = function()
		local S = T.addon(FILES).Sources
		local codex = { Quest = function(id) return { id = id, title = "First " .. id } end }
		T.eq(S.Needs(q({ pre = { 500, 600 } }), codex, player.completed), "First 600")
		T.eq(S.Needs(q({ pre = { 500 } }), codex, player.completed), nil)
		T.eq(S.Needs(q({ preAny = { 700, 500 } }), codex, player.completed), nil)
		T.eq(S.Needs(q({ preAny = { 700, 800 } }), codex, player.completed), "First 700")
	end,
}
