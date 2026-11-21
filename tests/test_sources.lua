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
	quest_races_high_bits = function() -- (Era races still correct)
		local S = T.addon(FILES).Sources
		T.eq(select(2, S.QuestOk(q({ races = 4294967373 }), player, 20)), "other races")
		T.ok(S.QuestOk(q({ races = 4294967373 }), { faction = "A", classBit = 16, raceBit = 1, completed = player.completed }, 20))
	end,
	-- Codex race masks are doubles: Era races in the low bits, Skyborne at 2^32 (Alliance) / 2^33 (Horde).
	-- A mask with no bit above 2^32 is a Classic mask, not a Skyborne lock; a race with no bit (nil)
	-- is never excluded.
	race_ok = function()
		local S = T.addon(FILES).Sources
		local A_SIDE, H_SIDE = 2 ^ 32 + 77, 2 ^ 33 + 178 -- the whole-side masks of 3,467 quests
		local SKY_A, SKY_H = 2 ^ 32, 2 ^ 33
		T.ok(S.RaceOk(A_SIDE, SKY_A)); T.ok(not S.RaceOk(A_SIDE, SKY_H))
		T.ok(S.RaceOk(H_SIDE, SKY_H)); T.ok(not S.RaceOk(H_SIDE, SKY_A))
		T.ok(S.RaceOk(SKY_A, SKY_A), "Skyborne-only (Alliance)"); T.ok(not S.RaceOk(SKY_A, 1), "not for Humans")
		T.ok(S.RaceOk(SKY_H, SKY_H)); T.ok(not S.RaceOk(SKY_H, 16))
		T.ok(S.RaceOk(SKY_A + SKY_H, SKY_H), "both Skyborne"); T.ok(not S.RaceOk(SKY_A + SKY_H, 2))
		T.ok(S.RaceOk(77, SKY_A), "a Classic mask does not lock Skyborne out")
		T.ok(S.RaceOk(16, SKY_H))
		T.ok(S.RaceOk(A_SIDE, 1)); T.ok(S.RaceOk(A_SIDE, 64)); T.ok(not S.RaceOk(A_SIDE, 16))
		T.ok(S.RaceOk(H_SIDE, 16)); T.ok(not S.RaceOk(H_SIDE, 8))
		T.ok(S.RaceOk(5, 4)); T.ok(not S.RaceOk(5, 2)); T.ok(S.RaceOk(255, 128))
		T.ok(S.RaceOk(0, 1)); T.ok(S.RaceOk(nil, 1)); T.ok(S.RaceOk(-1, SKY_A), "-1: every race")
		T.ok(S.RaceOk(1, nil), "no known bit: never excluded")
	end,
	quest_races_skyborne = function()
		local S = T.addon(FILES).Sources
		local skyA = { faction = "A", classBit = 16, raceBit = 2 ^ 32, completed = player.completed }
		local skyH = { faction = "H", classBit = 16, raceBit = 2 ^ 33, completed = player.completed }
		T.ok(S.QuestOk(q({ races = 4294967373 }), skyA, 20), "Alliance side mask")
		T.ok(S.QuestOk(q({ races = 8589934770 }), skyH, 20), "Horde side mask")
		T.ok(S.QuestOk(q({ races = 2 ^ 33 }), skyH, 20), "Skyborne-only")
		T.eq(select(2, S.QuestOk(q({ races = 2 ^ 33 }), player, 20)), "other races", "Undead: Skyborne-only quest")
		T.eq(select(2, S.QuestOk(q({ races = 4294967373 }), skyH, 20)), "other races")
	end,
	views = function()
		local S = T.addon(FILES).Sources
		local codex = {
			Item = function(id)
				if id == 1 then return { status = "retired", sources = {} } end
				return { sources = {
					{ type = "quest", quest = 100, choice = true },
					{ type = "drop", npc = 7, chance = 12.5 },
					{ type = "drop", npc = 8 }, -- open world
					{ type = "drop", npc = 9, instance = "MC" }, -- raid
					{ type = "craft", skill = 150, profession = "Tailoring" },
					{ type = "vendor", npc = 3 },
				} }
			end,
			Quest = function(id) return { id = id, title = "Wanted", level = 22, zone = 40 } end,
			Zone = function() return { name = "Westfall" } end,
			Npc = function(id)
				if id == 7 then return { name = "Boss", level = 24, boss = true, instance = "DM" } end
				return { name = "Mob", level = 20 }
			end,
			Instance = function(key) return { name = key == "DM" and "The Deadmines" or "Molten Core", kind = key == "DM" and "dungeon" or "raid" } end,
		}
		T.eq(S.For(1, codex, player, 20), nil, "retired")
		local v = S.For(2, codex, player, 20)
		T.eq(#v, 3)
		T.eq(v[1].kind, "quest"); T.ok(v[1].ok); T.eq(v[1].text, "Quest: Wanted (22), a choice"); T.eq(v[1].where, "Westfall")
		T.eq(v[2].kind, "dungeon"); T.eq(v[2].text, "Drop: Boss (boss), 12.5%"); T.eq(v[2].where, "The Deadmines"); T.ok(v[2].ok)
		T.eq(v[3].kind, "crafted"); T.ok(not v[3].ok); T.eq(v[3].why, "skill 150 (about level 30)")
		T.eq(v[3].text, "Crafted: Tailoring 150")
	end,
	-- A container (Codex `object` source) inside a dungeon counts as a dungeon source, as on the website
	-- (armory: in-instance containers); one in the open world or in a raid is not one of the kinds.
	dungeon_chests = function()
		local S = T.addon(FILES).Sources
		local OBJECTS = { [10] = { id = 10, name = "Rookery Egg", instance = "UBRS" }, [11] = { id = 11, name = "Chest" },
			[12] = { id = 12, name = "Cache", instance = "MC" } }
		local codex = {
			Item = function() return { sources = {
				{ type = "object", object = 10, chance = 3 }, { type = "object", object = 11 },
				{ type = "object", object = 12 }, { type = "object", object = 13 },
			} } end,
			Quest = function() return nil end,
			Object = function(id) return OBJECTS[id] end,
			Instance = function(key)
				if key == "MC" then return { name = "Molten Core", kind = "raid" } end
				return { name = "Upper Blackrock Spire", kind = "dungeon" }
			end,
		}
		local v = S.For(2, codex, player, 20)
		T.eq(#v, 1)
		T.eq(v[1].kind, "dungeon"); T.ok(v[1].ok); T.eq(v[1].where, "Upper Blackrock Spire")
		T.eq(v[1].text, "Container: Rookery Egg, 3%")
		codex.Object = nil -- an older Polestar without Codex.Object: no source, no error
		T.eq(#S.For(2, codex, player, 20), 0)
	end,
	-- A Codex that changed upstream (a function gone, a read that errors) costs the item its sources, never
	-- an error in the browser.
	views_guarded = function()
		local S = T.addon(FILES).Sources
		local codex = {
			Item = function() return { sources = { { type = "drop", npc = 7 }, { type = "quest", quest = 1 } } } end,
			Quest = function() error("changed upstream") end,
		}
		local v = S.For(2, codex, player, 20)
		T.eq(type(v), "table"); T.eq(#v, 0)
		codex.Item = function() error("changed upstream") end
		T.eq(#S.For(2, codex, player, 20), 0)
		T.ok(S.lastError, "kept for the window to mention")
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
