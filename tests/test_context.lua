local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Bands.lua",
	"Spec.lua", "Equip.lua", "Context.lua" }
-- Context is client glue (checked in game); offline only its shape with nothing worn.
return {
	mage = function()
		local ns = T.addon(FILES)
		require("wow").class = { "Mage", "MAGE", 8 }
		_G.GetInventoryItemLink = function() return nil end
		ns.char = { spec = "auto" }
		local ctx = ns.Context.Get()
		T.eq(ctx.cls, "mage"); T.eq(ctx.spec, "frost"); T.eq(ctx.specSource, "default")
		T.eq(ctx.ref, "spFrost"); T.eq(ctx.classBit, 128)
		ns.char.spec = "arcane"
		ns.Fire("STATE", "SPEC")
		T.eq(ns.Context.Get().ref, "spArcane")
	end,
	-- A class with no shipped weights: one chat line at login, then nothing (no context, no errors).
	unsupported_class = function()
		local ns = T.addon(FILES)
		require("wow").class = { "Warrior", "WARRIOR", 1 }
		local said = {}
		ns.Print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
		T.eq(ns.Context.ClassKey(), nil)
		T.eq(ns.Context.Get(), nil)
		ns._frame.scripts.OnEvent(ns._frame, "PLAYER_LOGIN")
		ns._frame.scripts.OnEvent(ns._frame, "PLAYER_LOGIN")
		T.eq(#said, 1)
		T.eq(said[1], "Warrior isn't supported yet")
		T.eq(ns.Context.Unsupported(), "Warrior isn't supported yet")
	end,
	supported_class_says_nothing = function()
		local ns = T.addon(FILES)
		local said = 0
		ns.Print = function() said = said + 1 end
		ns._frame.scripts.OnEvent(ns._frame, "PLAYER_LOGIN")
		T.eq(said, 0)
		T.eq(ns.Context.Unsupported(), nil)
	end,
	-- No weights or no band for this class/spec/level: the outcome is kept until STATE too.
	no_band_cached = function()
		local ns = T.addon(FILES)
		_G.GetInventoryItemLink = function() return nil end
		ns.char = { spec = "auto" }
		local calls = 0
		ns.Bands.For = function() calls = calls + 1 return nil end
		T.eq(ns.Context.Get(), nil); T.eq(ns.Context.Get(), nil)
		T.eq(calls, 1)
		ns.Fire("STATE", "PLAYER_LEVEL_UP", 21)
		T.eq(ns.Context.Get(), nil)
		T.eq(calls, 2)
	end,
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
	-- Skyborne (ChrRaces 95 High Order, Alliance; 96 Windshaper, Horde) has the Codex's race-mask bits
	-- 2^32 / 2^33, not 1 << (id - 1) (which overflows); a race with no known bit gets none (never excluded).
	race_bits = function()
		local ns = T.addon(FILES)
		_G.GetInventoryItemLink = function() return nil end
		ns.char = { spec = "auto" }
		local R = ns.Context.RaceBit
		T.eq(R(5, "Scourge", "Horde"), 16); T.eq(R(1, "Human", "Alliance"), 1); T.eq(R(8, "Troll", "Horde"), 128)
		T.eq(R(95, "Skyborne", "Alliance"), 2 ^ 32); T.eq(R(96, "Skyborne", "Horde"), 2 ^ 33)
		T.eq(R(nil, "Skyborne", "Horde"), 2 ^ 33, "by the race file and faction")
		T.eq(R(70, "Dracthyr", "Alliance"), nil, "unknown race: no bit")
		_G.UnitRace = function() return "Windshaper Skyborne", "Skyborne", 96 end
		T.eq(ns.Context.Get().raceBit, 2 ^ 33)
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
	-- Talents not readable yet at the first read after login: the default is not kept; a short timer
	-- reads them again (a few times at most) and rescoring follows once a spec is found.
	spec_retried_when_talents_unreadable = function()
		local W = require("wow")
		local ns = T.addon(FILES)
		ns.char = { spec = "auto" }
		_G.GetInventoryItemLink = function() return nil end
		local found, calls = nil, 0
		ns.Spec.Detect = function() calls = calls + 1 return found end
		T.eq(ns.Context.Get().specSource, "default")
		T.eq(#W.timers, 1, "a retry is queued")
		ns.Context.Get()
		T.eq(#W.timers, 1, "only one at a time")
		local changed = 0
		ns.On("SCORES_CHANGED", function() changed = changed + 1 end)
		W.flush()
		T.eq(changed, 0, "still nothing: no rescoring")
		T.eq(#W.timers, 1, "tries again")
		found = "holy"
		W.flush()
		T.eq(changed, 1, "found: scores change")
		local ctx = ns.Context.Get()
		T.eq(ctx.spec, "holy"); T.eq(ctx.specSource, "talents")
		T.eq(#W.timers, 0, "no more retries")
	end,
	spec_retries_are_bounded = function()
		local W = require("wow")
		local ns = T.addon(FILES)
		ns.char = { spec = "auto" }
		_G.GetInventoryItemLink = function() return nil end
		ns.Spec.Detect = function() return nil end -- a character with no talent points
		ns.Context.Get()
		for _ = 1, 10 do W.flush() end
		T.eq(#W.timers, 0, "gives up")
		T.eq(ns.Context.Get().specSource, "default")
		ns.Fire("STATE", "PLAYER_ENTERING_WORLD")
		ns.Context.Get()
		T.eq(#W.timers, 1, "entering the world tries again")
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
