local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Bands.lua",
	"Equip.lua", "Sources.lua", "Browser.lua" }

local function fixture()
	local text = assert(loadfile("tests/fixtures/parity.lua"))()
	local rows, best, gains, world, sets = {}, {}, {}, {}, {}
	for line in text:gmatch("[^\n]+") do
		local f = {}
		for x in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = x end
		if f[1] == "R" then
			rows[#rows + 1] = { spec = f[2], level = tonumber(f[3]), id = tonumber(f[4]), bonus = tonumber(f[5]),
				role = f[6], score = tonumber(f[7]), parts = f[8] }
		elseif f[1] == "G" then
			gains[#gains + 1] = { spec = f[2], level = tonumber(f[3]), gear = f[4], slot = f[5], id = tonumber(f[6]),
				bonus = tonumber(f[7]), pair = tonumber(f[8]), pairBonus = tonumber(f[9]), delta = tonumber(f[10]),
				pct = tonumber(f[11]) }
		elseif f[1] == "S" then
			local function ib(x) local id, b = x:match("^(%d+):(%d+)$") return tonumber(id), tonumber(b) end
			local e = { spec = f[2], level = tonumber(f[3]), gear = f[4], set = f[5], setGain = tonumber(f[6]), cands = {},
				mhGain = tonumber(f[11]), ohGain = tonumber(f[13]), twoHander = f[14] == "1" }
			for i = 7, 9 do local id, b = ib(f[i]) e.cands[#e.cands + 1] = { id = id, bonus = b } end
			e.mh, e.mhBonus = ib(f[10])
			e.oh, e.ohBonus = ib(f[12])
			sets[#sets + 1] = e
		elseif f[1] == "W" then
			world[#world + 1] = { id = tonumber(f[2]), world = f[3] == "1", generic = f[4] == "1" }
		elseif f[1] == "B" then
			best[#best + 1] = { spec = f[2], level = tonumber(f[3]), id = tonumber(f[4]), role = f[5],
				bonus = tonumber(f[6]), score = tonumber(f[7]) }
		end
	end
	return rows, best, gains, world, sets
end

local function weights(ns, specKey, level)
	local cls, spec = specKey:match("(%a+)/(%a+)")
	return ns.Bands.For(cls, spec, level).w, cls
end

return {
	scores_equal_the_website = function()
		local ns = T.addon(FILES)
		local rows = fixture()
		T.ok(#rows > 500, "fixture rows")
		for _, r in ipairs(rows) do
			local w, cls = weights(ns, r.spec, r.level)
			local inst = ns.Score.Instance(ns.Items.Get(r.id), r.bonus ~= 0 and r.bonus or nil)
			local where = r.spec .. " " .. r.level .. " " .. r.id .. "." .. r.bonus
			T.near(ns.Score.Score(inst, w, cls, r.role), r.score, 1e-6, where)
			local want = {}
			for k, amount, wk, wt, pts in r.parts:gmatch("(%w+):([^:,]+):(%w+):([^:,]+):([^:,]+)") do
				want[k .. ">" .. wk] = tonumber(pts)
			end
			local n = 0
			for _, p in ipairs(ns.Score.Parts(inst, w, cls, r.role)) do
				n = n + 1
				T.near(p[5], want[p[1] .. ">" .. p[3]] or 1e9, 1.5e-3, where .. " " .. p[1] .. ">" .. p[3])
			end
			local m = 0
			for _ in pairs(want) do m = m + 1 end
			T.eq(n, m, where .. " part count")
		end
	end,
	-- Weapon gains and Gain % (the website's upgrades() main/off hand lists): a two-hander against main +
	-- off hand, one-handers and off hands under a worn two-hander with the pair the website counted.
	-- Browser.Gains must give the same gain, and gain / base the same %.
	weapon_gains_equal_the_website = function()
		local ns = T.addon(FILES)
		local _, _, gains = fixture()
		T.ok(#gains > 20, "gain rows " .. #gains)
		local SLOT = { mainhand = 16, offhand = 17 }
		local seen2h = false
		for _, g in ipairs(gains) do
			local w, cls = weights(ns, g.spec, g.level)
			local function cand(id, bonus, role)
				local it = ns.Items.Get(id)
				local inst = ns.Score.Instance(it, bonus ~= 0 and bonus or nil)
				return { id = id, inst = inst, score = ns.Score.Score(inst, w, cls, role), kinds = { quest = true } }
			end
			local worn = {}
			for slot, id, bonus in g.gear:gmatch("(%a+):(%d+)%.?(%d*)") do
				local c = cand(tonumber(id), tonumber(bonus) or 0, slot == "offhand" and "oh" or "mh")
				worn[SLOT[slot]] = { inst = c.inst, score = c.score }
			end
			local c = cand(g.id, g.bonus, g.slot == "offhand" and "oh" or "mh")
			local pair = { mainhand = {}, offhand = {} }
			if g.pair ~= 0 then
				local key = g.slot == "mainhand" and "offhand" or "mainhand"
				pair[key][1] = cand(g.pair, g.pairBonus, key == "offhand" and "oh" or "mh")
			end
			local rows = ns.Browser.Gains({ [g.slot] = { c } }, { worn = worn }, pair)[g.slot]
			local where = g.spec .. " " .. g.level .. " " .. g.gear .. " " .. g.slot .. " " .. g.id
			T.eq(#rows, 1, where)
			local r = rows[1]
			T.near(r.gain, g.delta, 0.006, where .. " gain")
			if g.pct then T.near(100 * r.gain / r.base, g.pct, 0.06, where .. " %") else T.ok(r.base <= 0.01, where) end
			if c.inst.inv == 17 and worn[17] then seen2h = true end
		end
		T.ok(seen2h, "a two-hander against main + off hand")
	end,
	-- The best weapon set (armory summary, PoleSim Gear's View.Weapons): from the same candidates (the
	-- website's best one-hander, off hand and two-hander) the addon plans the same hands with the same
	-- split gains, and "uses the two-hander" where the website does. S rows: worn staff whose pair loses or
	-- wins, nothing beats the worn staff, worn MH + OH against a two-hander, a better worn one-hander kept.
	weapon_sets_equal_the_website = function()
		local files = { unpack(FILES) }
		for _, f in ipairs({ "Plan.lua", "Wishlist.lua", "View.lua" }) do files[#files + 1] = f end
		local ns = T.addon(files)
		local _, _, _, _, sets = fixture()
		T.ok(#sets >= 8, "fixture S rows " .. #sets)
		local kinds = {}
		for _, s in ipairs(sets) do
			kinds[s.set] = true
			local w, cls = weights(ns, s.spec, s.level)
			local function cand(id, bonus, role)
				local inst = ns.Score.Instance(ns.Items.Get(id), bonus ~= 0 and bonus or nil)
				return { id = id, inst = inst, score = ns.Score.Score(inst, w, cls, role), kinds = { quest = true }, sources = {} }
			end
			local worn = {}
			for slot, id, bonus in s.gear:gmatch("(%a+):(%d+)%.?(%d*)") do
				local c = cand(tonumber(id), tonumber(bonus) or 0, slot == "offhand" and "oh" or "mh")
				worn[slot == "offhand" and 17 or 16] = { inst = c.inst, score = c.score }
			end
			local mhC, ohC = {}, {}
			for i, x in ipairs(s.cands) do
				if x.id ~= 0 then
					if i == 2 then ohC[#ohC + 1] = cand(x.id, x.bonus, "oh") else mhC[#mhC + 1] = cand(x.id, x.bonus, "mh") end
				end
			end
			table.sort(mhC, function(a, b) return a.score > b.score end)
			local now, low = ns.Browser.Gains({ mainhand = mhC, offhand = ohC }, { worn = worn })
			local model = { level = s.level, now = now, coming = {}, under2h = low }
			local mh, oh = ns.View.Weapons(model, worn, { spec = "x" }, 0)
			local where = s.spec .. " " .. s.level .. " " .. s.gear
			T.eq(mh.plan and mh.plan.c.id or 0, s.mh, where .. " main hand")
			T.eq(oh.plan and oh.plan.c.id or 0, s.oh, where .. " off hand")
			if mh.plan then T.near(mh.plan.gain, s.mhGain, 0.006, where .. " main-hand gain") end
			if oh.plan then T.near(oh.plan.gain, s.ohGain, 0.006, where .. " off-hand gain") end
			T.eq(oh.twoHander or false, s.twoHander, where .. " uses the two-hander")
			local total = (mh.plan and (mh.plan.setGain or mh.plan.gain) or 0)
			if not mh.plan and oh.plan then total = oh.plan.gain end
			T.near(total, s.setGain, 0.006, where .. " set gain")
		end
		T.ok(kinds["2h"] and kinds.pair and kinds.current, "two-hander, pair and current sets")
	end,
	best_suffix_equals_the_website = function()
		local ns = T.addon(FILES)
		local _, best = fixture()
		for _, b in ipairs(best) do
			local w, cls = weights(ns, b.spec, b.level)
			local inst, s = ns.Score.BestSuffix(ns.Items.Get(b.id), w, cls, b.role)
			T.eq(inst.bonus or 0, b.bonus, b.spec .. " " .. b.level .. " " .. b.id)
			T.near(s, b.score, 1e-6)
		end
	end,
	-- The generic-world-drop rule (armory.generic_world_drop): from the shipped quality and whether the
	-- Codex has a world source, Sources.GenericWorld agrees with the website for every fixture item.
	world_drops_equal_the_website = function()
		local ns = T.addon(FILES)
		local _, _, _, world = fixture()
		T.ok(#world >= 10, "fixture W rows")
		for _, r in ipairs(world) do
			local srcs = { { type = "drop", npc = 1 } }
			if r.world then srcs[2] = { type = "world", minLevel = 10, maxLevel = 30 } end
			T.eq(ns.Sources.GenericWorld({ quality = 0, sources = srcs }, ns.Items.Get(r.id)), r.generic, "item " .. r.id)
		end
	end,
	-- Caster weapons' spell power is computed by the client (no stat code, equip spell or API stat): the
	-- shipped table must carry it, so the window scores Living Root like the live tooltip does
	-- (C_Item.GetItemStats: healing 45, spell damage 15; 23.2 for Shadow at 20, not 5.2).
	caster_weapon_shipped_equals_live = function()
		local files = { unpack(FILES) }
		files[#files + 1] = "Live.lua"
		local ns = T.addon(files)
		local w = weights(ns, "priest/shadow", 20)
		local shipped = ns.Score.Instance(ns.Items.Get(6631))
		local live = ns.Live.Instance("item:6631", {
			Info = function() return "INVTYPE_2HWEAPON", 18, 2, 10, 3, nil, "Living Root" end,
			Stats = function() return { ITEM_MOD_SPELL_HEALING_DONE_SHORT = 45, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 15,
				ITEM_MOD_SPIRIT_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 2, RESISTANCE3_NAME = 9,
				ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 14.66 } end })
		T.eq(shipped.stats.heal, 45); T.eq(shipped.stats.spDmg, 15); T.near(shipped.dps, 14.66, 1e-9)
		local a, b = ns.Score.Score(shipped, w, "priest", "mh"), ns.Score.Score(live, w, "priest", "mh")
		T.near(a, b, 1e-9); T.ok(a > 20, "Living Root scores " .. a)
	end,
}
