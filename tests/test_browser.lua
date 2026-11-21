local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua", "Sources.lua", "Browser.lua" }

local function rec(id, inv, int, rl, extra)
	local r = { id = id, name = "Item " .. id, q = 2, rl = rl, inv = inv, c = 4, sc = 1, ar = 0, dps = 0, s = { int = int },
		b = 0, sfx = {}, cm = 0, rm = 0, u = false }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end
local ITEMS = {
	[1] = rec(1, 1, 5, 10), [2] = rec(2, 1, 9, 10), [3] = rec(3, 1, 9, 10), [4] = rec(4, 1, 4, 12),
	[5] = rec(5, 1, 20, 22), [6] = rec(6, 1, 30, 10), [7] = rec(7, 1, 30, 10, { sc = 2 }),
}
local SOURCES = {
	[1] = { { type = "quest", quest = 100 } }, [2] = { { type = "quest", quest = 500 } }, [4] = { { type = "drop", npc = 7 } },
	[5] = { { type = "craft", skill = 100, profession = "Tailoring" } }, [6] = { { type = "quest", quest = 300 } },
	[7] = { { type = "quest", quest = 100 } },
}
local QUESTS = { [100] = { id = 100, title = "Wanted", level = 12, pre = { 600 } }, [500] = { id = 500, title = "Done", level = 12 },
	[300] = { id = 300, title = "Alliance", level = 12, faction = "A" }, [600] = { id = 600, title = "First Steps", level = 10 } }

local W1, W2 = { int = 1 }, { int = 2 }
local function env()
	return {
		cls = "priest", level = 20, ahead = 5,
		items = { Get = function(id) return ITEMS[id] end, ByInv = function() return { [1] = { 1, 2, 3, 4, 5, 6, 7 } } end },
		codex = {
			Item = function(id)
				if id == 3 then return { status = "retired", sources = { { type = "quest", quest = 100 } } } end
				return { sources = SOURCES[id] or {} }
			end,
			Quest = function(id) return QUESTS[id] end, Zone = function() return nil end,
			Npc = function() return { name = "Boss", level = 20, boss = true, instance = "DM" } end,
			Instance = function() return { name = "The Deadmines", kind = "dungeon" } end,
		},
		player = { faction = "H", classBit = 16, raceBit = 16, completed = function(q) return q == 500 end },
		routeStep = function(q) return q == 100 and 7 or nil end,
		at = function(level)
			return { w = level > 20 and W2 or W1, style = "any", worn = { [1] = { inst = { id = 99, inv = 1 }, score = 2 } } }
		end,
	}
end

return {
	collect_now = function()
		local B = T.addon(FILES).Browser
		local cands = B.Collect(env(), 20, 0, 20, 20)
		local ids = {}
		for _, c in ipairs(cands.head) do ids[#ids + 1] = c.id end
		T.eq(table.concat(ids, ","), "1,4", "2 done, 3 retired, 5 too high, 6 Alliance, 7 leather")
		local one = cands.head[1]
		T.near(one.score, 5); T.ok(one.kinds.quest)
		T.eq(one.sources[1].route, 7); T.eq(one.sources[1].needs, "First Steps")
		T.ok(cands.head[2].kinds.dungeon)
	end,
	-- With the real item index's Rl, items outside the level window are never decoded; scores are not kept.
	collect_decodes_only_the_window = function()
		local ns = T.addon(FILES)
		local e, got = env(), {}
		e.items.Rl = function(id) return ITEMS[id].rl end
		local get = e.items.Get
		e.items.Get = function(id) got[id] = (got[id] or 0) + 1 return get(id) end
		local cands = ns.Browser.Collect(e, 20, 22, 22, 25)
		T.eq(cands.head[1].id, 5)
		T.eq(got[1], nil, "rl 10: not decoded"); T.eq(got[5], 1, "once")
		T.ok(ns.Score.BestSuffix(ITEMS[5], W1, "priest", "gear") ~= cands.head[1].inst, "not kept by Score")
	end,
	gains = function()
		local B = T.addon(FILES).Browser
		local function c(id, inv, score) return { id = id, score = score, inst = { id = id, inv = inv, name = "I" .. id }, kinds = { quest = true } } end
		local staff = { inst = { id = 50, inv = 17 }, score = 10 }
		local band = { worn = { [16] = staff, [11] = { inst = { id = 60, inv = 11 }, score = 4 }, [12] = { inst = { id = 61, inv = 11 }, score = 6 } } }
		local g = B.Gains({ mainhand = { c(1, 17, 12), c(2, 21, 7) }, offhand = { c(3, 23, 5) }, finger = { c(60, 11, 9), c(4, 11, 5) } }, band)
		T.near(g.mainhand[1].gain, 2); T.eq(g.mainhand[1].c.id, 1)
		T.near(g.mainhand[2].gain, 2); T.eq(g.mainhand[2].note, "with I3 in the off hand")
		T.near(g.offhand[1].gain, 2); T.eq(g.offhand[1].note, "with I2 in the main hand")
		T.eq(#g.finger, 1, "the worn ring is not an upgrade"); T.near(g.finger[1].gain, 1)
	end,
	-- As armory._upgrades: "worn" is the same item with the same suffix; a unique ring worn with another
	-- suffix can only replace that one.
	gains_suffix_and_unique = function()
		local B = T.addon(FILES).Browser
		local function c(id, bonus, score, unique)
			return { id = id, score = score, inst = { id = id, bonus = bonus, inv = 11, unique = unique, name = "I" .. id }, kinds = { quest = true } }
		end
		local band = { worn = { [11] = { inst = { id = 60, bonus = 1, inv = 11 }, score = 4 }, [12] = { inst = { id = 61, bonus = 1, inv = 11, unique = true }, score = 6 } } }
		local g = B.Gains({ finger = { c(61, 2, 8, true), c(60, 2, 7) } }, band)
		T.eq(#g.finger, 2)
		T.eq(g.finger[1].c.id, 60); T.near(g.finger[1].gain, 3, 1e-9, "another suffix: against the weaker")
		T.eq(g.finger[2].c.id, 61); T.near(g.finger[2].gain, 2, 1e-9, "unique: against the one worn")
		T.eq(g.finger[2].note, "unique: replaces the one you wear")
	end,
	build = function()
		local B = T.addon(FILES).Browser
		local m = B.Build(env())
		local best = B.Best(m.now, "all")
		T.eq(#best, 1); T.eq(best[1].c.id, 1); T.near(best[1].gain, 3)
		T.eq(B.Best(m.now, "dungeon")[1].c.id, 4)
		T.eq(#B.Best(m.now, "crafted"), 0)
		T.eq(m.coming[1].c.id, 5); T.eq(m.coming[1].at, 22); T.near(m.coming[1].gain, 38, 1e-9, "int 20 x 2 - worn 2")
		T.eq(#B.Rows(m.coming, "quest"), 0)
	end,
	-- The model keeps per slot (and for "coming up") the best KEEP rows of each source kind: every filter
	-- still finds its own top rows, and a long tail of small upgrades is not held while the window is open.
	trim_keeps_the_top_of_each_kind = function()
		local B = T.addon(FILES).Browser
		local rows = {}
		for i = 1, 10 do rows[i] = { c = { id = i, kinds = { quest = true } }, gain = 100 - i } end
		rows[11] = { c = { id = 11, kinds = { crafted = true } }, gain = 1 }
		rows[12] = { c = { id = 12, kinds = { crafted = true, quest = true } }, gain = 0.5 }
		local t = B.Trim(rows, 3)
		local ids = {}
		for _, r in ipairs(t) do ids[#ids + 1] = r.c.id end
		T.eq(table.concat(ids, ","), "1,2,3,11,12", "3 quests (and 12, among the 3 crafted)")
		T.eq(#B.Trim(rows, 50), 12)
	end,
	runs_in_steps = function()
		local B = T.addon(FILES).Browser
		local got
		_G.C_Timer = { After = function(_, fn) fn() end }
		B.Start(env(), function(model) got = model end)
		T.eq(got.coming[1].c.id, 5)
	end,
	-- Over frames: each frame resumes the build until its time budget is spent (debugprofilestop, ms),
	-- then waits for the next frame; without the clock, one step per frame.
	runs_within_a_frame_budget = function()
		local B = T.addon(FILES).Browser
		local frames, clock = {}, 0
		_G.C_Timer = { After = function(_, fn) frames[#frames + 1] = fn end }
		_G.debugprofilestop = function() clock = clock + B.FRAME_MS / 2 + 0.1 return clock end
		local e, yields = env(), 0
		local get = e.items.Get
		e.items.Get = function(id) return get(id) end
		local done
		local orig = B.Build
		B.Build = function(en, yield)
			for _ = 1, 4 do yields = yields + 1 yield() end
			return orig(en)
		end
		B.Start(e, function(model) done = model end)
		T.eq(done, nil, "not all in the first frame")
		T.eq(yields, 2, "two steps fit the budget")
		while #frames > 0 do table.remove(frames, 1)() end
		T.ok(done and done.coming[1], "finished on later frames")
		_G.debugprofilestop = nil
	end,
	start_reports_errors = function()
		local B = T.addon(FILES).Browser
		local got, called
		_G.C_Timer = { After = function(_, fn) fn() end }
		_G.geterrorhandler = function() return function(e) got = e end end
		B.Build = function() error("boom") end
		B.Start(env(), function() called = true end)
		T.ok(got and got:find("boom"), tostring(got)); T.ok(not called)
	end,
}
