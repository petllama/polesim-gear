local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Bands.lua" }

local function fixture()
	local text = assert(loadfile("tests/fixtures/parity.lua"))()
	local rows, best = {}, {}
	for line in text:gmatch("[^\n]+") do
		local f = {}
		for x in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = x end
		if f[1] == "R" then
			rows[#rows + 1] = { spec = f[2], level = tonumber(f[3]), id = tonumber(f[4]), bonus = tonumber(f[5]),
				role = f[6], score = tonumber(f[7]), parts = f[8] }
		elseif f[1] == "B" then
			best[#best + 1] = { spec = f[2], level = tonumber(f[3]), id = tonumber(f[4]), role = f[5],
				bonus = tonumber(f[6]), score = tonumber(f[7]) }
		end
	end
	return rows, best
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
