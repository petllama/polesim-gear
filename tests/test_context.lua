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
		T.eq(ns.Context.At(nil), nil)
	end,
	-- GET_ITEM_INFO_RECEIVED fires for every item the client loads: only a worn item that was not
	-- loaded yet scores again.
	item_info_for_pending_items_only = function()
		local ns = T.addon(FILES)
		ns.char = { spec = "auto" }
		_G.GetInventoryItemLink = function(_, slot) return slot == 7 and "|Hitem:6540::::::::18|h[x]|h" or nil end
		local loaded = false
		ns.Live = { Instance = function(link)
			if not loaded then return nil, "pending" end
			return ns.Score.Instance(ns.Items.Get(tonumber(link:match("item:(%d+)"))))
		end }
		local ctx = ns.Context.Get()
		T.eq(ctx.worn[7], nil)
		local fired = 0
		ns.On("SCORES_CHANGED", function() fired = fired + 1 end)
		ns._frame.scripts.OnEvent(ns._frame, "GET_ITEM_INFO_RECEIVED", 1234, true)
		T.eq(fired, 0, "another item"); T.eq(ns.Context.Get(), ctx)
		loaded = true
		ns._frame.scripts.OnEvent(ns._frame, "GET_ITEM_INFO_RECEIVED", 6540, true)
		T.eq(fired, 1)
		T.ok(ns.Context.Get().worn[7], "scored once loaded")
		ns._frame.scripts.OnEvent(ns._frame, "GET_ITEM_INFO_RECEIVED", 6540, true)
		T.eq(fired, 1, "no longer pending")
	end,
	-- The spec is read from the talents again only when talents change (or the player picks one).
	spec_cached_until_talents_change = function()
		local ns = T.addon(FILES)
		ns.char = { spec = "auto" }
		_G.GetInventoryItemLink = function() return nil end
		local detect, calls = ns.Spec.Detect, 0
		ns.Spec.Detect = function(...) calls = calls + 1 return detect(...) end
		ns.Context.Get()
		T.eq(calls, 1)
		ns.Fire("STATE", "PLAYER_EQUIPMENT_CHANGED")
		ns.Fire("STATE", "PLAYER_LEVEL_UP", 21)
		ns.Context.Get()
		T.eq(calls, 1, "equipment and level keep the spec")
		for i, e in ipairs({ "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "SPEC" }) do
			ns.Fire("STATE", e)
			ns.Context.Get()
			T.eq(calls, 1 + i, e)
		end
		ns.char.spec = "holy"
		ns.Fire("STATE", "SPEC")
		T.eq(ns.Context.Get().spec, "holy")
	end,
	-- Best suffixes are kept per item and band until the scores change.
	best_suffix_cached = function()
		local ns = T.addon(FILES)
		local w = ns.DATA.specs.priest.shadow.bands[1].w
		local it = ns.Items.Get(6540)
		local a = ns.Score.BestSuffix(it, w, "priest", "gear")
		T.eq(ns.Score.BestSuffix(it, w, "priest", "gear"), a, "cached")
		local w2 = ns.DATA.specs.priest.shadow.bands[2].w
		T.ok(ns.Score.BestSuffix(it, w2, "priest", "gear") ~= a, "per band")
		ns.Fire("STATE", "PLAYER_LEVEL_UP", 30)
		T.ok(ns.Score.BestSuffix(it, w, "priest", "gear") ~= a, "cleared with the scores")
	end,
}
