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
		T.eq(#v, 5)
		T.eq(v[1].kind, "quest"); T.ok(v[1].ok); T.eq(v[1].text, "Quest: Wanted (22), a choice"); T.eq(v[1].where, "Westfall")
		T.eq(v[2].kind, "dungeon"); T.eq(v[2].text, "Drop: Boss (boss), 12.5%"); T.eq(v[2].where, "The Deadmines"); T.ok(v[2].ok)
		T.eq(v[3].kind, "crafted"); T.ok(not v[3].ok); T.eq(v[3].why, "skill 150 (about level 30)")
		T.eq(v[3].text, "Crafted: Tailoring 150")
		T.eq(v[4].kind, "vendor"); T.eq(v[4].text, "Vendor: Mob")
		T.eq(v[5].kind, "world", "the open-world drop: kept drops go after the other sources"); T.eq(v[5].text, "Drop: Mob (20)")
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
	-- An item with no required level (quest rewards, the Virtuous set sold by Mokvar for 100g) from a
	-- source with no level of its own (vendor, dungeon container): its item level stands in, as on the
	-- website (armory.source_views: item level > the level + 5 is not yet).
	level_less_items = function()
		local S = T.addon(FILES).Sources
		local codex = {
			Item = function() return { sources = { { type = "vendor", npc = 3 }, { type = "object", object = 10 } } } end,
			Npc = function() return { name = "Mokvar" } end,
			Object = function() return { name = "Chest", instance = "DM" } end,
			Instance = function() return { name = "The Deadmines", kind = "dungeon" } end,
		}
		local v = S.For(2, codex, player, 18, { rl = 0, il = 66 })
		T.eq(#v, 2)
		for _, x in ipairs(v) do T.ok(not x.ok, x.kind); T.eq(x.why, "item level 66") end
		for _, x in ipairs(S.For(2, codex, player, 18, { rl = 0, il = 23 })) do T.ok(x.ok, "item level 23 at 18") end
		for _, x in ipairs(S.For(2, codex, player, 18, { rl = 10, il = 66 })) do T.ok(x.ok, "a required level: the level gate") end
		for _, x in ipairs(S.For(2, codex, player, 18)) do T.ok(x.ok, "no item record: no rule") end
	end,
	-- A reputation requirement (Items `rep`: faction, standing 0 Hated .. 7 Exalted) stays an upgrade with
	-- the standing on the vendor, as on the website.
	reputation_note = function()
		local S = T.addon(FILES).Sources
		local codex = {
			Item = function() return { sources = { { type = "vendor", npc = 3 } } } end,
			Npc = function() return { name = "Quartermaster" } end,
			Faction = function(id) return id == 509 and { name = "The League of Arathor" } or nil end,
		}
		local v = S.For(2, codex, player, 30, { rl = 28, il = 33, rep = { 509, 5 } })
		T.ok(v[1].ok); T.eq(v[1].text, "Vendor: Quartermaster (needs The League of Arathor: Honored)")
		v = S.For(2, codex, player, 30, { rl = 28, il = 33, rep = { 77, 7 } })
		T.eq(v[1].text, "Vendor: Quartermaster (needs faction 77: Exalted)")
	end,
	needs = function()
		local S = T.addon(FILES).Sources
		local codex = { Quest = function(id) return { id = id, title = "First " .. id } end }
		T.eq(S.Needs(q({ pre = { 500, 600 } }), codex, player.completed), "First 600")
		T.eq(S.Needs(q({ pre = { 500 } }), codex, player.completed), nil)
		T.eq(S.Needs(q({ preAny = { 700, 500 } }), codex, player.completed), nil)
		T.eq(S.Needs(q({ preAny = { 700, 800 } }), codex, player.completed), "First 700")
	end,
	-- The fields the Sources tab groups and labels by.
	grouping_fields = function()
		local S = T.addon(FILES).Sources
		local codex = {
			Quest = function(id) return { id = id, title = "Wanted", level = 22, zone = 40,
				objectives = { { type = "kill", elites = { H = { rank = 1, lvl = 24 } } } } } end,
			Zone = function(id) return id == 40 and { name = "Westfall" } or nil end,
			Npc = function(id) return { name = "Boss", level = 24, boss = true, instance = "DM" } end,
			Object = function(id) return { id = id, name = "Chest", instance = "DM" } end,
			Instance = function(key) return { name = "The Deadmines", kind = "dungeon", levels = { 10, 16, 21 } } end,
		}
		local v = S.View({ type = "quest", quest = 100 }, codex, player, 20)
		T.eq(v.questId, 100); T.eq(v.title, "Wanted"); T.eq(v.level, 22); T.eq(v.zoneId, 40); T.eq(v.where, "Westfall")
		T.eq(v.elite, true, "hostile elites at an objective for the Horde")
		local a = S.View({ type = "quest", quest = 100 }, codex, { faction = "A", classBit = 16, raceBit = 1,
			completed = player.completed }, 20)
		T.eq(a.elite, false, "none for the Alliance")
		local d = S.View({ type = "drop", npc = 7, chance = 12.5 }, codex, player, 20)
		T.eq(d.instanceKey, "DM"); T.eq(d.npcName, "Boss"); T.eq(d.boss, true); T.eq(d.chance, 12.5)
		T.eq(d.levels[2], 16)
		local o = S.View({ type = "object", object = 5, chance = 3 }, codex, player, 20)
		T.eq(o.instanceKey, "DM"); T.eq(o.container, "Chest"); T.eq(o.chance, 3)
		local c = S.View({ type = "craft", skill = 75, skillLine = 197, profession = "Tailoring" }, codex, player, 20)
		T.eq(c.profession, "Tailoring"); T.eq(c.skill, 75); T.eq(c.skillLine, 197)
	end,
	vendors = function()
		local S = T.addon(FILES).Sources
		local NPCS = {
			[1] = { name = "Huklah", faction = "H", spawns = { { map = 1411, x = 40.6, y = 67.9 } } },
			[2] = { name = "Smith", faction = "A", spawns = { { map = 1429, x = 41, y = 65 } } },
			[3] = { name = "Goblin", faction = "AH", spawns = { { map = 1434, x = 27, y = 77 } } },
			[4] = { name = "Nobody" }, -- no faction known, no spawn
		}
		local codex = { Npc = function(id) return NPCS[id] end, Zone = function(id) return id == 1411 and { name = "Durotar" } or nil end }
		local v = S.View({ type = "vendor", npc = 1, cost = 12345 }, codex, player, 20)
		T.eq(v.kind, "vendor"); T.ok(v.ok); T.eq(v.npcId, 1); T.eq(v.npcName, "Huklah"); T.eq(v.cost, 12345)
		T.eq(v.zoneId, 1411); T.eq(v.where, "Durotar"); T.eq(v.text, "Vendor: Huklah")
		T.eq(v.spot.map, 1411); T.near(v.spot.x, 40.6)
		T.eq(S.View({ type = "vendor", npc = 2 }, codex, player, 20), nil, "Alliance vendor: hidden for the Horde")
		T.eq(S.View({ type = "vendor", npc = 3 }, codex, player, 20).kind, "vendor", "both sides")
		local n = S.View({ type = "vendor", npc = 4 }, codex, player, 20)
		T.eq(n.kind, "vendor", "faction unknown: shown"); T.eq(n.where, nil); T.eq(n.spot, nil)
		T.eq(S.View({ type = "vendor", npc = 99 }, codex, player, 20).npcName, nil, "npc unknown: still a vendor")
		-- No faction known for the character (Context: Neutral/unknown): every vendor is shown, no error.
		local nofac = { classBit = 16, raceBit = 16, completed = player.completed }
		T.eq(S.View({ type = "vendor", npc = 2 }, codex, nofac, 20).npcName, "Smith", "faction nil: Alliance vendor shown")
		T.eq(S.View({ type = "vendor", npc = 1 }, codex, nofac, 20).npcName, "Huklah", "faction nil: Horde vendor shown")
	end,
	world = function()
		local S = T.addon(FILES).Sources
		local NPCS = { [8] = { name = "Ogre", level = 21, spawns = { { map = 1431, x = 50, y = 50 } } },
			[9] = { name = "Dragon", level = 40 } }
		local codex = {
			Item = function() return { sources = {
				{ type = "world", minLevel = 15, maxLevel = 25 },
				{ type = "drop", npc = 8, chance = 0.5 }, { type = "drop", npc = 8, chance = 4 },
				{ type = "drop", npc = 8, chance = 2 }, { type = "drop", npc = 8, chance = 1 },
				{ type = "drop", npc = 9, chance = 9 },
			} } end,
			Npc = function(id) return NPCS[id] end,
		}
		local w = S.View({ type = "world", minLevel = 15, maxLevel = 25 }, codex, player, 20)
		T.eq(w.kind, "world"); T.ok(w.ok); T.eq(w.text, "World drop, levels 15-25"); T.eq(w.minLevel, 15)
		local d = S.View({ type = "drop", npc = 8, chance = 4 }, codex, player, 20)
		T.eq(d.kind, "world"); T.ok(d.ok); T.eq(d.npcId, 8); T.eq(d.npcName, "Ogre"); T.eq(d.chance, 4)
		T.eq(d.text, "Drop: Ogre (21), 4%"); T.eq(d.zoneId, 1431); T.eq(d.where, nil, "zone name read later (Groups)")
		local far = S.View({ type = "drop", npc = 9, chance = 9 }, codex, player, 20)
		T.ok(not far.ok); T.eq(far.why, "mob level 40")
		local all = S.For(1, codex, player, 20)
		local drops = {}
		for _, v in ipairs(all) do if v.npcId then drops[#drops + 1] = v.chance end end
		T.eq(table.concat(drops, ","), "4,2,1", "the best WORLD_KEEP (3) open-world drops: usable first, then by chance")
		drops = {}
		for _, v in ipairs(S.For(1, codex, player, 40)) do if v.npcId then drops[#drops + 1] = v.chance end end
		T.eq(table.concat(drops, ","), "9,4,2", "all usable: by chance")
		T.eq(all[1].text, "World drop, levels 15-25", "other sources keep their order, first")
	end,
}
