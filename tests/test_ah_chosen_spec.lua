-- Regression (0.7.7, a player's report): the AH scan scores with the spec chosen in Settings, even
-- with no talent points (default Holy), and a Settings change rescores the cached scan.
local T = require("t")
local F = require("winfix")
local A = require("ahstub")
local function setup(L)
	local ns = T.addon(F.files())
	local W = require("wow")
	W.level = L
	require("ui").install()
	W.class = { "Paladin", "PALADIN", 2 }
	_G.UnitRace = function() return "Human", "Human", 1 end
	_G.UnitFactionGroup = function() return "Alliance" end
	_G.GetInventoryItemLink = function() return nil end
	_G.C_Traits, _G.C_ClassTalents = nil, nil
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = {}, { spec = "retribution" }
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	ns.Print = function() end
	return ns, W
end
return {
	chosen_ret_without_talents_scores_ret = function()
		local ns, W = setup(40)
		local ctx = ns.Context.Get()
		T.eq(ctx.spec, "retribution"); T.eq(ctx.specSource, "chosen")
		T.ok(ctx.w == ns.Bands.For("paladin", "retribution", 40).w, "Ret band")
		-- one plate helm with Strength/Stamina, one cloth helm with Intellect: scored with Ret's weights
		local api, log = A.stub({ A.result(10763, 100) }, 50) -- any shipped wearable item id works
		_G.C_AuctionHouse = api
		assert(ns.AH.Scan())
		while log.pending do
			local p = log.pending; log.pending = nil
			ns._frame.scripts.OnEvent(ns._frame, p == "updated" and "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
		end
		local n = 0 while #W.timers > 0 and n < 10000 do W.flush() n = n + 1 end
		local r = ns.AH.Rows()[1]
		T.ok(r, "an upgrade row")
		local ret = ns.Score.Score(r.c.inst, ns.Bands.For("paladin", "retribution", 40).w, "paladin", "gear")
		T.ok(math.abs(r.gain - ret) < 1e-6, "gain = Ret score (nothing worn)")
		ns.TabSettings.SetSpec("holy")
		n = 0 while #W.timers > 0 and n < 10000 do W.flush() n = n + 1 end
		local holy = ns.Score.Score(r.c.inst, ns.Bands.For("paladin", "holy", 40).w, "paladin", "gear")
		T.ok(math.abs(ns.AH.Rows()[1].gain - holy) < 1e-6, "rescored with Holy after Settings")
	end,
}
