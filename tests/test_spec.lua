local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Spec.lua" }

-- A Forever talent tree for Spec.Detect: nodes = { { id, x, rank, groups }, ... }, groups =
-- { { id, name, order }, ... } (nil: no GetGroupDisplayInfoByTreeID); fail = { name = true } makes that
-- C_Traits/C_ClassTalents function raise.
local function talents(nodes, groups, fail)
	fail = fail or {}
	local function api(name, fn)
		return function(...)
			if fail[name] then error(name .. " failed") end
			return fn(...)
		end
	end
	local byId = {}
	for _, n in ipairs(nodes) do byId[n[1]] = n end
	_G.C_ClassTalents = { GetActiveConfigID = api("GetActiveConfigID", function() return 7 end) }
	_G.C_Traits = {
		GetConfigInfo = api("GetConfigInfo", function(cfg) return cfg == 7 and { treeIDs = { 70 } } or nil end),
		GetTreeNodes = api("GetTreeNodes", function()
			local ids = {}
			for _, n in ipairs(nodes) do ids[#ids + 1] = n[1] end
			return ids
		end),
		GetNodeInfo = api("GetNodeInfo", function(_, id)
			local n = byId[id]
			if n.broken then error("node " .. id) end
			return { ID = id, posX = n[2], ranksPurchased = n[3], groupIDs = n[4] or {}, isVisible = true }
		end),
	}
	if groups then
		C_Traits.GetGroupDisplayInfoByTreeID = api("GetGroupDisplayInfoByTreeID", function()
			local out = {}
			for _, g in ipairs(groups) do
				out[#out + 1] = { groupID = g[1], treeID = 70, displayName = g[2], orderIndex = g[3], icon = 0 }
			end
			return out
		end)
	end
end

local GROUPS = { { 33, "Shadow", 3 }, { 11, "Discipline", 1 }, { 22, "Holy", 2 } } -- listed out of order
-- Three columns at x 1000-1600, 3000-3600, 5000-5600, four nodes each; ranks[col][row] points.
local function grid(ranks, withGroups)
	local nodes, gids = {}, { 11, 22, 33 }
	for col = 1, 3 do
		for row = 1, 4 do
			nodes[#nodes + 1] = { col * 100 + row, 1000 + (col - 1) * 2000 + (row % 2) * 600,
				(ranks[col] or {})[row] or 0, withGroups and { gids[col] } or nil }
		end
	end
	return nodes
end

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
	detect_by_group_ids = function()
		local S = T.addon(FILES).Spec
		talents(grid({ { 1 }, { 5, 5 }, { 3 } }, true), GROUPS)
		local key, points = S.Detect("priest")
		T.eq(key, "holy"); T.eq(points[1], 1); T.eq(points[2], 10); T.eq(points[3], 3)
	end,
	detect_loose_nodes_by_x = function()
		local S = T.addon(FILES).Spec
		talents(grid({ {}, { 1 }, { 5, 5, 5 } }, false), GROUPS) -- groups known, nodes carry none
		local key, points = S.Detect("priest")
		T.eq(key, "shadow"); T.eq(points[2], 1); T.eq(points[3], 15)
	end,
	detect_without_group_api = function()
		local S = T.addon(FILES).Spec
		talents(grid({ { 4, 4 }, {}, { 1 } }, true), nil)
		T.eq(C_Traits.GetGroupDisplayInfoByTreeID, nil)
		local key, points = S.Detect("priest")
		T.eq(key, "discipline"); T.eq(points[1], 8); T.eq(points[3], 1)
	end,
	detect_survives_api_errors = function()
		local S = T.addon(FILES).Spec
		for _, name in ipairs({ "GetActiveConfigID", "GetConfigInfo", "GetTreeNodes" }) do
			talents(grid({ { 5 } }, true), GROUPS, { [name] = true })
			T.eq((S.Detect("priest")), nil, name)
		end
		talents(grid({ {}, { 5 } }, true), GROUPS, { GetGroupDisplayInfoByTreeID = true })
		T.eq((S.Detect("priest")), "holy", "groups failed: columns by x")
		local nodes = grid({ { 9 }, { 2 } }, true)
		nodes[1].broken = true -- the 9-point node
		talents(nodes, GROUPS)
		T.eq((S.Detect("priest")), "holy", "a failing node is skipped")
		_G.C_Traits, _G.C_ClassTalents = nil, nil
		T.eq((S.Detect("priest")), nil, "no talent API")
	end,
	no_points_is_the_default = function()
		local ns = T.addon(FILES)
		ns.char = { spec = "auto" }
		talents(grid({}, true), GROUPS)
		local key, source = ns.Spec.Current("priest")
		T.eq(key, "shadow"); T.eq(source, "default")
	end,
	ties_go_left_most = function()
		local S = T.addon(FILES).Spec
		talents(grid({ {}, { 5 }, { 5 } }, true), GROUPS)
		T.eq((S.Detect("priest")), "holy")
		talents(grid({ { 5 }, {}, { 5 } }, true), GROUPS)
		T.eq((S.Detect("priest")), "discipline")
	end,
	class_without_column_order = function()
		local ns = T.addon(FILES)
		ns.DATA.specs.mage = { frost = ns.DATA.specs.priest.shadow, fire = ns.DATA.specs.priest.shadow }
		ns.char = { spec = "auto" }
		ns.Context = { ClassKey = function() return "mage" end }
		talents(grid({ { 5 } }, true), GROUPS)
		T.eq((ns.Spec.Detect("mage")), nil)
		local key, source = ns.Spec.Current("mage")
		T.eq(key, "fire", "first spec by name when there is no default"); T.eq(source, "default")
		local said
		ns.Print = function(...) said = table.concat({ ... }, " ") end
		SlashCmdList.POLESIMGEAR("spec")
		T.ok(said and said:find("spec fire (default)", 1, true), said)
		T.ok(said:find("auto|fire|frost", 1, true), said)
	end,
}
