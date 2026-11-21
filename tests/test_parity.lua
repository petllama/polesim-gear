local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Bands.lua",
	"Equip.lua", "Sources.lua", "Browser.lua" }

local function fixture()
	local text = assert(loadfile("tests/fixtures/parity.lua"))()
	local rows, best, gains = {}, {}, {}
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
		elseif f[1] == "B" then
			best[#best + 1] = { spec = f[2], level = tonumber(f[3]), id = tonumber(f[4]), role = f[5],
				bonus = tonumber(f[6]), score = tonumber(f[7]) }
		end
	end
	return rows, best, gains
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
}
