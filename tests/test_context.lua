local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Bands.lua",
	"Spec.lua", "Equip.lua", "Context.lua" }
-- Context is client glue (checked in game); offline only its shape with nothing worn.
return {
	get = function()
		local ns = T.addon(FILES)
		_G.GetInventoryItemLink = function() return nil end
		ns.char = { spec = "auto" }
		local ctx = ns.Context.Get()
		T.eq(ctx.cls, "priest"); T.eq(ctx.spec, "shadow"); T.eq(ctx.specSource, "default")
		T.eq(ctx.level, 20); T.eq(ctx.lo, 20); T.eq(ctx.band.upTo, 29); T.eq(ctx.ref, "spShadow")
		T.eq(ctx.faction, "H"); T.eq(ctx.classBit, 16); T.eq(ctx.raceBit, 16)
		T.eq(next(ctx.worn), nil)
		T.eq(ns.Context.Get(), ctx, "cached")
		local changed = false
		ns.On("SCORES_CHANGED", function() changed = true end)
		ns.Fire("STATE", "PLAYER_LEVEL_UP", 30)
		T.ok(changed)
		T.eq(ns.Context.Get().band.upTo, 39)
		T.eq(ns.Context.At(60).band.upTo, 60)
	end,
}
