local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Spec.lua" }
return {
	pick = function()
		local S = T.addon(FILES).Spec
		T.eq(S.Pick({ 0, 5, 31 }, { "Discipline", "Holy", "Shadow" }, "priest"), "shadow")
		T.eq(S.Pick({ 21, 0, 5 }, nil, "priest"), "discipline", "by column order")
		T.eq(S.Pick({ 0, 0, 0 }, nil, "priest"), nil)
		T.eq(S.Pick({ 0, 9, 0 }, { "Disziplin", "Heilig", "Schatten" }, "priest"), "holy", "localised names: order")
	end,
	columns_by_x = function()
		local col = T.addon(FILES).Spec.ColumnsByX({ 100, 110, 500, 510, 900, 905 }, 3)
		T.eq(col(105), 1); T.eq(col(505), 2); T.eq(col(903), 3)
	end,
	override = function()
		local ns = T.addon(FILES)
		ns.char = { spec = "holy" }
		local key, source = ns.Spec.Current("priest")
		T.eq(key, "holy"); T.eq(source, "chosen")
	end,
}
