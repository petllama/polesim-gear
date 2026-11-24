local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Equip.lua", "Sources.lua", "Browser.lua", "Plan.lua", "Wishlist.lua", "View.lua" }
local function load(char)
	local ns = T.addon(FILES)
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = {}, char or {}
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	return ns
end
local function r(id, gain, kinds, at)
	return { c = { id = id, inst = { id = id, name = "I" .. id }, kinds = kinds or { quest = true } }, gain = gain, at = at }
end
local function model()
	return { level = 20,
		now = { head = { r(1, 5), r(2, 3) }, neck = { r(3, 9, { vendor = true }) }, chest = { r(4, 2, { world = true }) } },
		coming = { feet = { r(5, 7, { quest = true }, 22) } } }
end
local worn = { [1] = { inst = { id = 90 }, score = 10 }, [5] = { inst = { id = 91 }, score = 4 } }
-- The screenshot's weapons under a worn Wind Rider Staff (18.3) at 21: Staff of the Blessed Seer (2H
-- 48.7, dungeon), Evocator's Blade (1H 38.1, dungeon), The Stitcher (1H 15.9, an upcoming guide quest),
-- Skum's Bucket (off hand 6.5, dungeon), a vendor off hand (1.0). Rows as Browser.Gains makes them.
local function weaponModel()
	local W = 18.3
	local function row(id, inv, score, name, kinds, src)
		return { c = { id = id, score = score, inst = { id = id, inv = inv, name = name }, kinds = kinds, sources = src or {} },
			gain = inv == 17 and score - W or 99, base = W, vs2h = inv ~= 17 or nil,
			slot = { key = inv == 23 and "offhand" or "mainhand", label = inv == 23 and "Off hand" or "Main hand" } }
	end
	local D, Q = { dungeon = true }, { quest = true }
	local near = { { kind = "quest", ok = true, questId = 700, level = 21, route = { ahead = 3, guide = "G" } } }
	local m = { level = 21,
		now = { mainhand = { row(1, 17, 48.7, "Staff of the Blessed Seer", D), row(2, 21, 38.1, "Evocator's Blade", D) },
			offhand = { row(4, 23, 6.5, "Skum's Bucket", D) } },
		coming = {},
		under2h = { mainhand = { row(3, 21, 15.9, "The Stitcher", Q, near) }, offhand = { row(5, 23, 1.0, "Vendor Orb", { vendor = true }) } } }
	return m, { [16] = { inst = { id = 5306, inv = 17, name = "Wind Rider Staff" }, score = W } }
end
local ALL = { quest = true, dungeon = true, crafted = true, vendor = true, world = false }
return {
	upgrades_mode = function()
		local ns = load()
		local st = { spec = "shadow", filters = ALL, ahead = 0, show = "upgrades" }
		local es = ns.View.PlanEntries(model(), worn, st)
		local keys = {}
		for _, e in ipairs(es) do keys[#keys + 1] = e.def.key .. "#" .. e.priority end
		T.eq(table.concat(keys, ","), "neck#1,head#2", "biggest planned gain first; world off; feet beyond look ahead")
		T.eq(es[2].worn.inst.id, 90, "the current item")
		st.ahead = 2
		es = ns.View.PlanEntries(model(), worn, st)
		T.eq(es[2].def.key, "feet", "look ahead +2: the level 22 boots")
	end,
	pick_sorts_by_pick_gain = function()
		local ns = load({ plan = { shadow = { head = "2:0", neck = "77:0" } } })
		local es = ns.View.PlanEntries(model(), worn, { spec = "shadow", filters = ALL, ahead = 0, show = "upgrades" })
		T.eq(es[1].def.key, "head", "the pick's gain (3) ranks it; the missing pick goes last")
		T.eq(es[1].entry.plan.c.id, 2); T.near(es[1].entry.betterBy, 2, 1e-9)
		T.eq(es[2].def.key, "neck"); T.eq(es[2].entry.missing.id, 77); T.eq(es[2].priority, nil, "no number for a missing pick")
		T.ok(es[2].why:find("not available", 1, true), es[2].why)
	end,
	all_mode = function()
		local ns = load()
		local es = ns.View.PlanEntries(model(), worn, { spec = "shadow", filters = ALL, ahead = 0, show = "all" })
		T.eq(#es, #ns.Browser.SLOTS, "every slot")
		T.eq(es[1].def.key, "neck"); T.eq(es[2].def.key, "head")
		T.eq(es[3].entry.plan, nil, "then the rest in slot order, no upgrade"); T.eq(es[3].priority, nil)
		T.eq(es[3].def.key, "shoulder")
	end,
	wishlist_mode = function()
		local ns = load({ wish = { ["4:0"] = true, ["99:0"] = true } })
		local es = ns.View.PlanEntries(model(), worn, { spec = "shadow", filters = ALL, ahead = 0, show = "wishlist" })
		T.eq(#es, 2)
		T.eq(es[1].row.c.id, 4, "found (filters do not hide starred items)"); T.eq(es[1].def.key, "chest")
		T.eq(es[2].row, nil); T.eq(es[2].missing.id, 99); T.eq(es[2].why, "not an upgrade now")
	end,
	progress = function()
		local ns = load({ plan = { shadow = { neck = "3:0" } } })
		local m = model()
		local st = { spec = "shadow", filters = ALL, ahead = 0, show = "upgrades" }
		local done, total = ns.View.Progress(m, worn, st)
		T.eq(total, #ns.Browser.SLOTS - 1, "main + off hand count once"); T.eq(done, total - 2, "head and neck have upgrades now")
		st.filters = { quest = true }
		done = ns.View.Progress(m, worn, st)
		T.eq(done, total - 1, "vendor off: the neck counts as done")
		st.ahead = 5
		T.eq((ns.View.Progress(m, worn, st)), total - 1, "progress counts upgrades available NOW")
	end,
	-- st.preferQuest: the suggestion is the best upgrade from an upcoming guide quest within 2 levels of
	-- the model's level (the player's, not the look ahead); off -> the best overall.
	near_quest_suggestion = function()
		local ns = load()
		local m = model()
		local q = r(6, 2, { quest = true })
		q.c.sources = { { kind = "quest", ok = true, questId = 600, level = 21, route = { ahead = 4, guide = "G" } } }
		m.now.head[3] = q
		local st = { spec = "shadow", filters = ALL, ahead = 0, show = "upgrades", preferQuest = true }
		local function head(es) for _, e in ipairs(es) do if e.def.key == "head" then return e end end end
		local e = head(ns.View.PlanEntries(m, worn, st))
		T.eq(e.entry.plan.c.id, 6); T.eq(e.entry.best.c.id, 1); T.eq(e.entry.near, true)
		st.preferQuest = false
		e = head(ns.View.PlanEntries(m, worn, st))
		T.eq(e.entry.plan.c.id, 1, "setting off: BiS as before")
		-- a pick wins
		local ns2 = load({ plan = { shadow = { head = "2:0" } } })
		st.preferQuest = true
		e = head(ns2.View.PlanEntries(m, worn, st))
		T.eq(e.entry.plan.c.id, 2)
	end,
	weights = function()
		local ns = load()
		local rows = ns.View.WeightRows({ int = 0.4, spShadow = 1, sta = 0.1, armor = 0 }, nil)
		local t = {}
		for _, w in ipairs(rows) do t[#t + 1] = w.key .. "=" .. w.value end
		T.eq(table.concat(t, ","), "spShadow=1,int=0.4,sta=0.1", "zero weights left out, biggest first")
		T.eq(rows[1].label, ns.DATA.statLabels.spShadow or "spShadow")
		T.eq(#ns.View.WeightRows({ a = 3, b = 2, c = 1 }, 2), 2, "top N")
		local bands = ns.View.Bands("priest", "shadow")
		T.ok(#bands >= 2); T.eq(bands[1].lo, 1); T.eq(bands[2].lo, bands[1].upTo + 1)
		T.eq(ns.View.BandIndex(bands, bands[2].lo), 2)
	end,
	-- Weapons are ONE decision (the user's level 21 Shadow priest wearing Wind Rider Staff, 18.3): the
	-- Gear Plan suggests the best weapon set; an off hand only with a one-hander that is available or
	-- planned, and only when the pair beats the staff; under a two-hander plan the Off hand row "uses the
	-- two-hander". Row gains split so they sum to the set's gain.
	weapon_set_screenshot = function()
		local ns = load()
		local m, worn = weaponModel()
		local st = { spec = "shadow", filters = { quest = true }, ahead = 0, show = "all" }
		-- quests only: The Stitcher alone (15.9) loses to the staff: nothing to plan, no off hand
		local mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(mh.plan, nil, "no main hand"); T.eq(oh.plan, nil, "no off hand over a better staff"); T.ok(oh.twoHander)
		-- quests + dungeons: the best set is the two-hander Staff of the Blessed Seer (48.7) over
		-- Evocator's Blade + Skum's Bucket (44.6)
		st.filters = { quest = true, dungeon = true }
		mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(mh.plan.c.id, 1); T.near(mh.plan.gain, 30.4, 1e-9); T.ok(oh.twoHander); T.eq(oh.plan, nil)
		-- without the two-hander: Evocator's Blade + Skum's Bucket, gains split (19.8 + 6.5 = 26.3)
		table.remove(m.now.mainhand, 1)
		mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(mh.plan.c.id, 2); T.near(mh.plan.gain, 38.1 - 18.3, 1e-9); T.near(mh.plan.setGain, 26.3, 1e-9)
		T.eq(oh.plan.c.id, 4); T.near(oh.plan.gain, 6.5, 1e-9); T.near(oh.plan.setGain, 26.3, 1e-9)
		T.eq(oh.plan.note, "with Evocator's Blade (also planned)")
		T.eq(mh.plan.note, "with Skum's Bucket (also planned)")
		T.eq(oh.plan.setText, "Weapon set: +26.3 over Wind Rider Staff")
		T.ok(not oh.twoHander)
	end,
	-- Dual wield (0.7.0): one quest dagger is the best one-hander AND the best off hand; a quest choice
	-- gives one copy, so the set pairs it with the next off hand (the website's rule, armory set_oh).
	weapon_set_dual_wield_one_copy = function()
		local ns = load()
		local function row(id, score, name, key)
			return { c = { id = id, score = score, inst = { id = id, inv = 13, name = name }, kinds = { quest = true }, sources = {} },
				gain = score, base = 0, slot = { key = key, label = key } }
		end
		local m = { level = 30, coming = {},
			now = { mainhand = { row(1, 54.7, "Claw", "mainhand"), row(2, 40, "Knife", "mainhand") },
				offhand = { row(1, 24.0, "Claw", "offhand"), row(3, 20.0, "Shiv", "offhand") } } }
		local st = { spec = "assassination", filters = { quest = true }, ahead = 0, show = "all" }
		local mh, oh = ns.View.Weapons(m, {}, st, 0)
		T.eq(mh.plan.c.id, 1, "the claw in the main hand")
		T.eq(oh.plan.c.id, 3, "the next off hand, not a second claw")
		T.near(mh.plan.setGain, 74.7, 1e-9)
	end,
	-- The near-quest rule per item: The Stitcher from an upcoming guide quest is the main hand (its set
	-- with the best off hand, Skum's Bucket, still beats the staff: +4.1), BiS the two-hander (+30.4).
	weapon_set_near_quest = function()
		local ns = load()
		local m, worn = weaponModel()
		local st = { spec = "shadow", filters = { quest = true, dungeon = true }, ahead = 0, show = "all", preferQuest = true }
		local mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(mh.plan.c.id, 3); T.eq(mh.near, true); T.eq(mh.best.c.id, 1); T.near(mh.best.gain, 30.4, 1e-9)
		T.near(mh.plan.gain, 15.9 - 18.3, 1e-9); T.near(mh.plan.setGain, 15.9 + 6.5 - 18.3, 1e-9)
		T.eq(oh.plan.c.id, 4); T.eq(oh.plan.note, "with The Stitcher (also planned)")
	end,
	-- Picks fix their part of the set: an off-hand pick takes the best one-hander (no two-hander); a
	-- two-hander pick leaves the off hand to it; a one-hander pick takes the best off hand.
	weapon_set_picks = function()
		local m, worn = weaponModel()
		local st = { spec = "shadow", filters = { quest = true, dungeon = true, vendor = true }, ahead = 0, show = "all" }
		local ns = load({ plan = { shadow = { offhand = "5:0" } } })
		local mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(oh.plan.c.id, 5); T.ok(oh.isPick); T.eq(mh.plan.c.id, 2, "Evocator's Blade, not the staff")
		T.near(mh.plan.setGain, 38.1 + 1 - 18.3, 1e-9)
		ns = load({ plan = { shadow = { mainhand = "1:0", offhand = "5:0" } } })
		mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(mh.plan.c.id, 1); T.ok(oh.twoHander); T.eq(oh.plan, nil)
		ns = load({ plan = { shadow = { mainhand = "3:0" } } })
		mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(mh.plan.c.id, 3); T.ok(mh.isPick); T.eq(oh.plan.c.id, 4); T.eq(oh.plan.note, "with The Stitcher (also planned)")
		-- an off-hand pick whose pair loses to the staff is still the plan, with the best one-hander
		st.filters = { quest = true, vendor = true }
		ns = load({ plan = { shadow = { offhand = "5:0" } } })
		mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(oh.plan.c.id, 5); T.eq(mh.plan.c.id, 3); T.near(mh.plan.setGain, 15.9 + 1 - 18.3, 1e-9)
	end,
	-- Worn one-hander + off hand: a better off hand alone; a two-hander only when it beats the best pair.
	weapon_set_worn_pair = function()
		local ns = load()
		local function row(id, inv, score, gain, base, name)
			return { c = { id = id, score = score, inst = { id = id, inv = inv, name = name or ("I" .. id) }, kinds = { quest = true }, sources = {} },
				gain = gain, base = base, slot = { key = inv == 23 and "offhand" or "mainhand" } }
		end
		local worn = { [16] = { inst = { id = 90, inv = 21, name = "Shiv" }, score = 101 }, [17] = { inst = { id = 91, inv = 23, name = "Runic" }, score = 3.2 } }
		local st = { spec = "shadow", filters = { quest = true }, ahead = 0, show = "all" }
		local m = { level = 21, now = { mainhand = {}, offhand = { row(4, 23, 7.2, 4.0, 3.2, "Shimmering") } }, coming = {} }
		local mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(mh.plan, nil); T.eq(oh.plan.c.id, 4); T.near(oh.plan.gain, 4.0, 1e-9); T.eq(oh.plan.note, nil)
		worn[16] = { inst = { id = 90, inv = 21, name = "Knife" }, score = 5 }
		worn[17] = { inst = { id = 91, inv = 23, name = "Runic" }, score = 3 }
		m.now.mainhand = { row(1, 17, 48.7, 40.7, 8), row(2, 21, 38.1, 33.1, 5) }
		m.now.offhand = { row(4, 23, 6.5, 3.5, 3) }
		mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(mh.plan.c.id, 1, "40.7 over 33.1 + 3.5"); T.ok(oh.twoHander)
		m.now.mainhand[2] = row(2, 21, 45, 40, 5)
		mh, oh = ns.View.Weapons(m, worn, st, 0)
		T.eq(mh.plan.c.id, 2, "40 + 3.5 over 40.7"); T.near(mh.plan.gain, 40, 1e-9); T.near(mh.plan.setGain, 43.5, 1e-9)
		T.eq(oh.plan.c.id, 4); T.near(oh.plan.gain, 3.5, 1e-9); T.eq(oh.plan.setText, "Weapon set: +43.5 over Knife + Runic")
	end,
	-- The Gear Plan rows and the progress count the weapon set once (the "uses the two-hander" off hand
	-- is not a slot to finish).
	weapon_set_entries_and_progress = function()
		local ns = load()
		local m, worn = weaponModel()
		local st = { spec = "shadow", filters = { quest = true, dungeon = true }, ahead = 0, show = "all" }
		local by = {}
		for _, e in ipairs(ns.View.PlanEntries(m, worn, st)) do by[e.def.key] = e end
		T.eq(by.mainhand.entry.plan.c.id, 1); T.ok(by.offhand.entry.twoHander); T.eq(by.offhand.priority, nil)
		st.show = "upgrades"
		for _, e in ipairs(ns.View.PlanEntries(m, worn, st)) do T.ok(e.def.key ~= "offhand", "no off-hand row") end
		local done, total = ns.View.Progress(m, worn, st)
		T.eq(total, #ns.Browser.SLOTS - 1, "main and off hand: one weapon set"); T.eq(done, total - 1)
		st.filters = { quest = true }
		done = ns.View.Progress(m, worn, st)
		T.eq(done, total, "the staff is the best set from quests")
	end,
	badge_slots = function()
		local ns = load({ plan = { shadow = { neck = "3:0" } } })
		local B = ns.Browser
		local def = {}
		for _, d in ipairs(B.SLOTS) do def[d.key] = d end
		local function e(key, isPick) return { def = def[key], entry = { plan = {}, isPick = isPick } } end
		local worn = { [11] = { score = 5 }, [12] = { score = 3 }, [13] = { score = 2 } }
		local neck = e("neck", true)
		local b, of = ns.View.BadgeSlots({ neck, e("finger"), e("trinket"), { def = def.head, entry = {} } }, worn)
		T.eq(of[2], neck, "the entry behind the dot (the slot tooltip names its item)"); T.eq(of[1], nil)
		T.eq(b[2], "pick"); T.eq(b[12], "suggestion", "the weaker ring"); T.eq(b[14], "suggestion", "the empty trinket slot")
		T.eq(b[1], nil, "no plan")
	end,
}
