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
	-- Item race masks use the same check: a Skyborne-only item (2^33) for a Windshaper, not for Undead.
	collect_item_race_masks = function()
		local B = T.addon(FILES).Browser
		local e = env()
		local saved = ITEMS[1]
		ITEMS[1] = rec(1, 1, 5, 10, { rm = 2 ^ 33 })
		local function ids()
			local out = {}
			for _, c in ipairs(B.Collect(e, 20, 0, 20, 20).head) do out[#out + 1] = c.id end
			return table.concat(out, ",")
		end
		local ok, err = pcall(function()
			T.eq(ids(), "4", "Undead: not a Skyborne item")
			e.player.raceBit = 2 ^ 33
			T.eq(ids(), "1,4", "Windshaper Skyborne")
			ITEMS[1].rm = 2 ^ 33 + 178
			T.eq(ids(), "1,4", "a Horde-side mask with the Skyborne bit")
			e.player.raceBit = 16
			T.eq(ids(), "1,4", "Undead too")
		end)
		ITEMS[1] = saved
		assert(ok, err)
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
	-- One item that throws (bad data, a Codex change) is skipped and reported once under its id; the
	-- rest of the build goes on.
	collect_isolates_an_item_error = function()
		local ns = T.addon(FILES)
		local reported = {}
		_G.geterrorhandler = function() return function(e) reported[#reported + 1] = e end end
		local e = env()
		local get = e.items.Get
		e.items.Get = function(id) if id == 4 then error("bad item 4") end return get(id) end
		local ids = {}
		for _, c in ipairs(ns.Browser.Collect(e, 20, 0, 20, 20).head) do ids[#ids + 1] = c.id end
		T.eq(table.concat(ids, ","), "1", "item 4 skipped, the others scored")
		T.eq(#reported, 1); T.ok(reported[1]:find("bad item 4", 1, true), reported[1])
		ns.Browser.Collect(e, 20, 0, 20, 20)
		T.eq(#reported, 1, "once per id per session")
		local m
		_G.C_Timer = { After = function(_, fn) fn() end }
		ns.Browser.Start(e, function(model) m = model end)
		T.ok(m and m.now.head[1].c.id == 1, "the build completes with the others")
	end,
	-- Frame budget: Collect yields after building the index, every YIELD_EVERY items in the window and
	-- after each slot's sort (no slice longer than ~8 ms with the real data under lua5.1).
	collect_yields_often = function()
		local ns = T.addon(FILES)
		local e = env()
		local list = {}
		for i = 1, 31 do ITEMS[1000 + i] = rec(1000 + i, 1, i, 10) list[i] = 1000 + i end
		list[32] = 5 -- rl 22: outside the window, not counted
		e.items.ByInv = function() return { [1] = list } end
		e.codex.Item = function() return { sources = { { type = "quest", quest = 500 } } } end
		local yields = 0
		ns.Browser.Collect(e, 20, 0, 20, 20, function() yields = yields + 1 end, { head = true })
		for i = 1, 31 do ITEMS[1000 + i] = nil end
		T.eq(ns.Browser.YIELD_EVERY, 10, "15 gave a 27.8 ms frame at level 60 with the GC running")
		T.eq(yields, 1 + 3 + 1, "index, items 10, 20 and 30, the sort")
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
		-- base: the score of everything the row replaces (Gain % = gain / base): the staff for the paired
		-- one-hander and off hand, the weaker ring
		T.near(g.mainhand[1].base, 10); T.near(g.mainhand[2].base, 10); T.near(g.offhand[1].base, 10)
		T.near(g.finger[1].base, 4)
	end,
	-- A two-hander replaces main AND off hand: gain and base both count the pair (Witching Stave against
	-- Mug + Runic Stave: +28.1 over 2.39, not over the Mug's 0.9).
	gains_two_hander_base = function()
		local B = T.addon(FILES).Browser
		local function c(id, inv, score) return { id = id, score = score, inst = { id = id, inv = inv, name = "I" .. id }, kinds = { quest = true } } end
		local band = { worn = { [16] = { inst = { id = 50, inv = 21 }, score = 0.9 }, [17] = { inst = { id = 51, inv = 23 }, score = 1.49 } } }
		local g = B.Gains({ mainhand = { c(1, 17, 30.52), c(2, 21, 3) }, offhand = { c(3, 23, 2) } }, band)
		T.eq(g.mainhand[1].c.id, 1); T.near(g.mainhand[1].gain, 30.52 - 2.39, 1e-9); T.near(g.mainhand[1].base, 2.39, 1e-9)
		T.eq(g.mainhand[1].note, "replaces your main and off hand")
		T.near(g.mainhand[2].base, 0.9, 1e-9, "a one-hander replaces the main hand"); T.near(g.offhand[1].base, 1.49, 1e-9)
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
		local flat = B.Flat(m.coming)
		T.eq(flat[1].c.id, 5); T.eq(flat[1].at, 22); T.near(flat[1].gain, 38, 1e-9, "int 20 x 2 - worn 2")
		T.eq(#B.Rows(flat, "quest"), 0)
	end,
	-- Coming up under a worn two-hander: a level 21 one-hander is paired with the best off hand available
	-- by level 21 (here a level 10 one, from no "coming" level), as the website picks the pair from every
	-- candidate up to that level; and the reverse for an off hand.
	coming_pairs_across_levels = function()
		local B = T.addon(FILES).Browser
		local e = env()
		e.ahead = 1
		local items = {
			[31] = rec(31, 23, 4, 10, { c = 4, sc = 0 }), [32] = rec(32, 13, 5, 21, { c = 2, sc = 4 }),
			[33] = rec(33, 13, 3, 12, { c = 2, sc = 4 }), [34] = rec(34, 23, 6, 21, { c = 4, sc = 0 }),
		}
		e.codex.Item = function() return { sources = { { type = "quest", quest = 100 } } } end
		e.at = function(level)
			return { w = level > 20 and W2 or W1, style = "any", worn = { [16] = { inst = { id = 99, inv = 17 }, score = 3 } } }
		end
		local function coming(byInv)
			e.items = { Get = function(id) return items[id] end, ByInv = function() return byInv end }
			local by = {}
			for _, r in ipairs(B.Flat(B.Build(e).coming)) do by[r.c.id] = r end
			return by
		end
		local by = coming({ [23] = { 31 }, [13] = { 32 } })
		T.ok(by[32], "the level 21 one-hander is coming up")
		T.eq(by[32].note, "with Item 31 in the off hand"); T.near(by[32].gain, 10 + 8 - 3, 1e-9)
		-- a better off hand of level 22 is not available at 21 (the weapons are collected once per band)
		e.ahead = 2
		items[35] = rec(35, 23, 9, 22, { c = 4, sc = 0 })
		by = coming({ [23] = { 31, 35 }, [13] = { 32 } })
		T.eq(by[32].note, "with Item 31 in the off hand", "at 21")
		local get, gets = e.items.Get, 0
		e.items.Get = function(id) if id == 31 then gets = gets + 1 end return get(id) end
		B.Build(e)
		-- now: rl + candidate; each coming level's own window: rl; the band's pairing pool, once: rl + candidate
		T.eq(gets, 2 + 2 + 2, "the pairing weapons are collected once per band, not per level")
		T.eq(by[35].note, "with Item 32 in the main hand"); T.near(by[35].gain, 18 + 10 - 3, 1e-9)
		e.ahead = 1
		by = coming({ [23] = { 34 }, [13] = { 33 } })
		T.ok(by[34], "the level 21 off hand is coming up")
		T.eq(by[34].note, "with Item 33 in the main hand"); T.near(by[34].gain, 12 + 6 - 3, 1e-9)
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
	-- The model keeps the best KEEP rows per kind but counts every upgrade of a slot (per source filter),
	-- and SlotAll scores that one slot again for the drill-down's "Show all (N)".
	show_all = function()
		local B = T.addon(FILES).Browser
		B.KEEP = 0
		local m = B.Build(env())
		T.eq(#m.now.head, 0, "trimmed")
		T.eq(m.counts.head.all, 2); T.eq(m.counts.head.quest, 1); T.eq(m.counts.head.dungeon, 1)
		T.eq(m.counts.head.crafted, 0)
		T.eq(B.Count(m, "head", "all"), 2); T.eq(B.Count(m, "neck", "quest"), 0)
		local all = B.SlotAll(env(), "head")
		T.eq(#all, 2); T.eq(all[1].c.id, 1); T.near(all[1].gain, 3); T.eq(all[2].c.id, 4)
		T.eq(#B.Rows(all, "dungeon"), 1)
		local got
		_G.C_Timer = { After = function(_, fn) fn() end }
		B.Start(env(), function(rows) got = rows end, function(en, y) return B.SlotAll(en, "head", y) end)
		T.eq(#got, 2, "over frames too")
	end,
	runs_in_steps = function()
		local B = T.addon(FILES).Browser
		local got
		_G.C_Timer = { After = function(_, fn) fn() end }
		B.Start(env(), function(model) got = model end)
		T.eq(B.Flat(got.coming)[1].c.id, 5)
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
		T.ok(done and B.Flat(done.coming)[1], "finished on later frames")
		_G.debugprofilestop = nil
	end,
	-- A build the window no longer wants (closed, scores changed): Cancel stops it before its next step
	-- and done is never called.
	start_cancel = function()
		local B = T.addon(FILES).Browser
		local frames = {}
		_G.C_Timer = { After = function(_, fn) frames[#frames + 1] = fn end }
		local called, steps = false, 0
		B.Build = function(_, yield) for _ = 1, 5 do steps = steps + 1 yield() end return {} end
		local h = B.Start(env(), function() called = true end)
		T.eq(steps, 1)
		h:Cancel()
		while #frames > 0 do table.remove(frames, 1)() end
		T.eq(steps, 1, "no further step"); T.ok(not called)
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
	-- A fatal error also goes to onError (the window stops saying "Scoring...").
	start_calls_on_error = function()
		local B = T.addon(FILES).Browser
		local frames, reported, failed = {}, nil, nil
		_G.C_Timer = { After = function(_, fn) frames[#frames + 1] = fn end }
		_G.geterrorhandler = function() return function(e) reported = e end end
		B.Build = function(_, yield) yield() error("late boom") end
		B.Start(env(), function() error("not done") end, nil, function(err) failed = err end)
		T.eq(failed, nil, "still running")
		while #frames > 0 do table.remove(frames, 1)() end
		T.ok(failed and failed:find("late boom"), tostring(failed)); T.ok(reported and reported:find("late boom"))
	end,
	trim_five_kinds_and_keep = function()
		local B = T.addon(FILES).Browser
		T.eq(table.concat(B.KINDS, ","), "quest,dungeon,crafted,vendor,world")
		local rows = {}
		for i = 1, 6 do rows[i] = { c = { id = i, inst = { id = i }, kinds = { vendor = true } }, gain = 10 - i } end
		rows[7] = { c = { id = 7, inst = { id = 7, bonus = 5 }, kinds = { world = true } }, gain = 1 }
		local t = B.Trim(rows, 2, { ["5:0"] = true })
		local ids = {}
		for _, r in ipairs(t) do ids[#ids + 1] = r.c.id end
		T.eq(table.concat(ids, ","), "1,2,5,7", "2 vendors, kept 5, the world one")
		T.eq(B.KeyOf({ id = 7, bonus = 5 }), "7:5"); T.eq(B.KeyOf({ id = 9 }), "9:0")
	end,
	coming_per_slot = function()
		local B = T.addon(FILES).Browser
		local e = env()
		local m = B.Build(e)
		T.eq(m.level, 20)
		T.eq(m.coming.head[1].c.id, 5); T.eq(m.coming.head[1].at, 22)
		T.eq(#m.coming.neck, 0)
		local flat = B.Flat(m.coming)
		T.eq(flat[1].c.id, 5, "Flat: every slot's coming rows, biggest gain first")
		B.KEEP = 0
		e.keep = { ["5:0"] = true }
		m = B.Build(e)
		T.eq(m.coming.head[1].c.id, 5, "kept although KEEP is 0")
		T.eq(#m.now.head, 0)
	end,
	slot_rows = function()
		local B = T.addon(FILES).Browser
		local function r(id, gain, kinds, at) return { c = { id = id, inst = { id = id }, kinds = kinds }, gain = gain, at = at } end
		local m = { level = 20,
			now = { head = { r(1, 3, { quest = true }), r(4, 1, { dungeon = true }) } },
			coming = { head = { r(5, 38, { crafted = true }, 22), r(6, 2, { quest = true }, 21) } } }
		local function ids(rows) local t = {} for _, x in ipairs(rows) do t[#t + 1] = x.c.id end return table.concat(t, ",") end
		T.eq(ids(B.SlotRows(m, "head", 0)), "1,4", "now only")
		T.eq(ids(B.SlotRows(m, "head", 1)), "1,6,4", "+1: level 21 rows")
		T.eq(ids(B.SlotRows(m, "head", 5)), "5,1,6,4")
		T.eq(ids(B.SlotRows(m, "head", 5, { quest = true })), "1,6", "only quest kinds")
		T.eq(ids(B.SlotRows(m, "neck", 5)), "", "no rows")
		T.ok(B.Pass(r(1, 1, { vendor = true, quest = true }), { quest = true }), "any enabled kind passes")
		T.ok(not B.Pass(r(1, 1, { world = true }), { quest = true, world = false }))
	end,
	worn_for_and_gear_score = function()
		local B = T.addon(FILES).Browser
		local function e(id, s) return { inst = { id = id }, score = s } end
		local worn = { [1] = e(1, 5), [11] = e(2, 4), [12] = e(3, 6), [13] = e(4, 2), [16] = e(5, 10) }
		local def = {}
		for _, d in ipairs(B.SLOTS) do def[d.key] = d end
		T.eq(B.WornFor(def.head, worn).inst.id, 1)
		T.eq(B.WornFor(def.finger, worn).inst.id, 2, "the weaker ring")
		T.eq(B.WornFor(def.trinket, worn), nil, "one trinket slot empty: the empty one")
		T.eq(B.WornFor(def.neck, worn), nil)
		T.near(B.GearScore(worn), 27)
		T.near(B.GearScore({}), 0)
	end,
	count_passing = function()
		local B = T.addon(FILES).Browser
		B.KEEP = 0
		local m = B.Build(env())
		T.eq(B.CountPassing(m, "head", nil), 2, "every kind")
		T.eq(B.CountPassing(m, "head", { quest = true }), 1)
		T.eq(B.CountPassing(m, "head", { quest = true, dungeon = true }), 2)
		T.eq(B.CountPassing(m, "head", { crafted = true }), 0)
		T.eq(B.CountPassing(m, "neck", nil), 0)
	end,
}
