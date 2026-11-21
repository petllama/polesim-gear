local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Equip.lua", "Sources.lua", "Browser.lua", "Groups.lua" }
local function row(id, gain, sources, at)
	local kinds = {}
	for _, s in ipairs(sources) do kinds[s.kind] = true end
	return { c = { id = id, inst = { id = id, name = "I" .. id }, sources = sources, kinds = kinds }, gain = gain, at = at }
end
local codex = { Zone = function(id) return ({ [40] = { name = "Westfall" }, [12] = { name = "Elwynn Forest" }, [1411] = { name = "Durotar" } })[id] end,
	Instance = function(k) return { name = k == "DM" and "The Deadmines" or "Wailing Caverns", levels = k == "DM" and { 10, 16, 21 } or { 10, 17, 22 } } end }
local function model()
	local q1 = { kind = "quest", questId = 100, title = "Wanted", level = 22, zoneId = 40, where = "Westfall", ok = true }
	local q2 = { kind = "quest", questId = 101, title = "Lost", level = 18, zoneId = 40, where = "Westfall", ok = true, elite = true }
	local q3 = { kind = "quest", questId = 102, title = "Wolves", level = 10, zoneId = 12, where = "Elwynn Forest", ok = true }
	local d1 = { kind = "dungeon", instanceKey = "DM", npcName = "Boss", boss = true, chance = 12, ok = true }
	local d2 = { kind = "dungeon", instanceKey = "WC", npcName = "Snake", chance = 5, ok = true }
	local c1 = { kind = "crafted", profession = "Tailoring", skill = 75, ok = true }
	local v1 = { kind = "vendor", npcName = "Huklah", zoneId = 1411, cost = 500, ok = true }
	local w1 = { kind = "world", minLevel = 15, maxLevel = 25, ok = true }
	return { level = 20,
		now = { head = { row(1, 5, { q1, d1 }), row(2, 3, { q2 }) }, neck = { row(3, 4, { q3, d1 }) },
			chest = { row(4, 2, { c1 }), row(5, 1, { v1 }), row(6, 6, { w1 }) } },
		coming = { feet = { row(7, 9, { d2 }, 23) } } }
end
return {
	build = function()
		local G = T.addon(FILES).Groups
		local g = G.Build(model(), 0, codex)
		T.eq(#g.dungeon, 1, "WC only coming at 23: not within look ahead 0")
		T.eq(g.dungeon[1].name, "The Deadmines"); T.eq(g.dungeon[1].count, 2); T.eq(g.dungeon[1].levels, "16-21")
		T.eq(g.dungeon[1].rows[1].c.id, 1, "best gain first"); T.eq(g.dungeon[1].rows[1].src.npcName, "Boss")
		T.eq(#g.quest, 2); T.eq(g.quest[1].name, "Westfall"); T.eq(g.quest[1].count, 2, "two quests")
		T.eq(g.quest[1].quests[1].title, "Wanted", "quests by best gain"); T.eq(g.quest[1].quests[2].elite, true)
		T.eq(g.quest[1].quests[1].rows[1].c.id, 1)
		T.eq(g.crafted[1].name, "Tailoring"); T.eq(g.crafted[1].count, 1)
		T.eq(g.vendor[1].name, "Durotar"); T.eq(g.vendor[1].rows[1].src.npcName, "Huklah")
		T.eq(#g.world, 1); T.eq(g.world[1].c.id, 6)
		g = G.Build(model(), 5, codex)
		T.eq(#g.dungeon, 2, "+5: the level 23 boots from Wailing Caverns")
		T.eq(g.dungeon[1].name, "The Deadmines", "more upgrades first"); T.eq(g.dungeon[2].name, "Wailing Caverns")
	end,
	-- One row per item per instance: the likeliest source is the row's, the others are its detail.
	dungeon_one_row_per_item = function()
		local G = T.addon(FILES).Groups
		local function d(npc, chance, boss) return { kind = "dungeon", instanceKey = "DM", npcName = npc, boss = boss or false, chance = chance, ok = true } end
		local chest = { kind = "dungeon", instanceKey = "DM", container = "Chest", chance = 0.9, ok = true }
		local m = { level = 20, coming = {}, now = {
			head = { row(1, 5, { d("Trash", 0.5), d("Smite", 12, true), chest, d("Cookie", 3, true), d("Sneed", 0.2, true) }) },
			neck = { row(2, 7, { d("Miner", 0.4), d("Watchman", 0.3) }) },
			chest = { row(3, 2, { d("VanCleef", 20, true) }) } } }
		local g = G.Build(m, 0, codex).dungeon[1]
		T.eq(g.count, 3); T.eq(#g.rows, 3, "one row per item")
		T.eq(g.rows[1].c.id, 2, "by gain"); T.eq(g.rows[2].c.id, 1); T.eq(g.rows[3].c.id, 3)
		local r = g.rows[2]
		T.eq(r.src.npcName, "Smite", "the likeliest source")
		T.eq(r.otherCount, 4); T.eq(#r.others, 3, "top 3 others")
		T.eq(r.others[1].npcName, "Cookie"); T.eq(r.others[2].container, "Chest"); T.eq(r.others[3].npcName, "Trash")
		T.eq(r.rare, false)
		T.eq(g.rows[1].rare, true, "best chance under 1%: rare")
		T.eq(g.rows[1].src.npcName, "Miner"); T.eq(g.rows[1].otherCount, 1)
		T.eq(g.rows[3].otherCount, 0); T.eq(#g.rows[3].others, 0)
		-- Boss loot lists carry world drops at 0.01-0.9% (the Codex's Deadmines bosses): a boss's sub-1%
		-- drop is as unlikely as a trash mob's.
		m.now.feet = { row(4, 1, { d("Sneed", 0.2, true) }) }
		g = G.Build(m, 0, codex).dungeon[1]
		T.eq(g.rows[4].c.id, 4); T.eq(g.rows[4].rare, true, "a boss's sub-1% drop: rare")
	end,
	-- An item listed in two slots counts once and keeps its best gain.
	dungeon_item_in_two_slots = function()
		local G = T.addon(FILES).Groups
		local s = { kind = "dungeon", instanceKey = "DM", npcName = "Boss", boss = true, chance = 10, ok = true }
		local m = { level = 20, coming = {}, now = { mainhand = { row(1, 3, { s }) }, offhand = { row(1, 4, { s }) } } }
		local g = G.Build(m, 0, codex).dungeon[1]
		T.eq(g.count, 1); T.eq(#g.rows, 1); T.eq(g.rows[1].gain, 4)
	end,
	-- The same dedupe for vendors (per zone), professions and quests (per quest).
	others_one_row_per_item = function()
		local G = T.addon(FILES).Groups
		local v1 = { kind = "vendor", npcName = "A", zoneId = 1411, cost = 500, ok = true }
		local v2 = { kind = "vendor", npcName = "B", zoneId = 1411, cost = 400, ok = true }
		local c1 = { kind = "crafted", profession = "Tailoring", skill = 75, ok = true }
		local c2 = { kind = "crafted", profession = "Tailoring", skill = 90, ok = true }
		local q = { kind = "quest", questId = 100, title = "Wanted", zoneId = 40, where = "Westfall", ok = true }
		local qc = { kind = "quest", questId = 100, title = "Wanted", zoneId = 40, where = "Westfall", ok = true, text = "a choice" }
		local m = { level = 20, coming = {}, now = { head = { row(1, 5, { v1, v2, c1, c2, q, qc }) } } }
		local g = G.Build(m, 0, codex)
		T.eq(#g.vendor[1].rows, 1); T.eq(g.vendor[1].rows[1].src.npcName, "A", "no chances: source order")
		T.eq(g.vendor[1].rows[1].otherCount, 1); T.eq(g.vendor[1].rows[1].others[1].npcName, "B")
		T.eq(#g.crafted[1].rows, 1); T.eq(g.crafted[1].rows[1].otherCount, 1)
		T.eq(#g.quest[1].quests[1].rows, 1); T.eq(#g.quest[1].rows, 1); T.eq(g.quest[1].count, 1)
	end,
	unknown_zone = function()
		local G = T.addon(FILES).Groups
		local m = { level = 20, now = { head = { row(1, 5, { { kind = "vendor", npcName = "X", ok = true } }) } }, coming = {} }
		local g = G.Build(m, 0, { Zone = function() return nil end })
		T.eq(g.vendor[1].name, "Unknown zone")
	end,
}
