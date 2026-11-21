local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua", "Tooltip.lua" }
local ctx = { cls = "priest", spec = "shadow", ref = "spShadow", lo = 30, band = { upTo = 39 }, level = 34,
	w = { int = 0.5, spShadow = 1 } }
local inst = { id = 1, inv = 1, stats = { int = 10, spShadow = 3 }, armor = 0, dps = 0, weapon = false, rl = 30 }
local function text(L)
	local out = {}
	for _, l in ipairs(L) do out[#out + 1] = l[1] .. "|" .. (l[2] or "") end
	return table.concat(out, "\n")
end
return {
	short = function()
		local L = T.addon(FILES).Tooltip.Lines({ score = 8, gain = 2, base = 6 }, inst, ctx, false, false)
		T.eq(L[1][1], "Score 8.0"); T.eq(L[1][2], "+2.0 (+33%)")
		T.eq(L[2][1], "Shadow, levels 30-39: points of Shadow spell damage")
		T.eq(L[#L][1], "Shift: how?")
	end,
	label_and_equipped = function()
		local L = T.addon(FILES).Tooltip.Lines({ score = 8, gain = 0, base = 8, equipped = true }, inst, ctx, false, true)
		T.eq(L[1][1], "PoleSim score 8.0"); T.eq(L[1][2], "equipped")
	end,
	how = function()
		local L = T.addon(FILES).Tooltip.Lines({ score = 8, gain = 2, base = 6, note = "against your weaker one" }, inst, ctx, true, false)
		local s = text(L)
		T.ok(s:find("Intellect 10 x 0.5", 1, true), s)
		T.ok(s:find("Shadow spell damage 3 x 1|3.00", 1, true), s)
		T.ok(s:find("minus worn|6.00", 1, true), s)
		T.ok(s:find("against your weaker one", 1, true), s)
	end,
	future_level = function()
		local far = { id = 2, inv = 1, stats = {}, armor = 0, dps = 0, rl = 37 }
		local L = T.addon(FILES).Tooltip.Lines({ score = 1, gain = 1, base = 0 }, far, ctx, false, false)
		T.eq(L[1][2], "+1.0")
		T.ok(L[3][1]:find("requires level 37", 1, true))
	end,
	-- An equip bonus the client did not report (filled from the item table) says so in the how? sum.
	filled_labelled = function()
		local filled = { id = 3, inv = 1, stats = { int = 10, spShadow = 3 }, armor = 0, dps = 0, rl = 30, filled = { spShadow = true } }
		local s = text(T.addon(FILES).Tooltip.Lines({ score = 8, gain = 2, base = 6 }, filled, ctx, true, false))
		T.ok(s:find("Shadow spell damage 3 x 1 (item table)|3.00", 1, true), s)
		T.ok(s:find("Intellect 10 x 0.5|", 1, true), s)
		T.ok(not s:find("Intellect 10 x 0.5 (item table)", 1, true), s)
	end,
}
