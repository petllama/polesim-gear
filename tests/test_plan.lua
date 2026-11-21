local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Equip.lua", "Sources.lua", "Browser.lua", "Plan.lua" }
local function load(char)
	local ns = T.addon(FILES)
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = {}, char or {}
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	return ns
end
return {
	storage = function()
		local char = {}
		local ns = load(char)
		local P = ns.Plan
		T.eq(P.Get("shadow", "head"), nil)
		P.Set("shadow", "head", { id = 10, bonus = 3 })
		T.eq(char.plan.shadow.head, "10:3"); T.eq(P.Get("shadow", "head"), "10:3")
		T.eq(P.Get("holy", "head"), nil, "per spec")
		local id, bonus = P.Parse("10:3"); T.eq(id, 10); T.eq(bonus, 3)
		id, bonus = P.Parse("10:0"); T.eq(id, 10); T.eq(bonus, nil)
		T.eq(P.Parse("junk"), nil)
		P.Clear("shadow", "head")
		T.eq(P.Get("shadow", "head"), nil)
		local fired = 0
		ns.On("PLAN_CHANGED", function() fired = fired + 1 end)
		P.Set("shadow", "neck", { id = 2 }); P.Clear("shadow", "neck")
		T.eq(fired, 2)
	end,
	bad_saved_value = function()
		local ns = load({ plan = { shadow = "x" } })
		T.eq(ns.Plan.Get("shadow", "head"), nil)
		ns.Plan.Set("shadow", "head", { id = 1 })
		T.eq(ns.Plan.Get("shadow", "head"), "1:0")
	end,
}
